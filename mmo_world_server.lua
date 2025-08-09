-- world_server.lua
-- Server-authoritative movement + view streaming + heartbeat-based player cleanup.

local modem = peripheral.find("modem", rednet.open)

local world = require("mmo_world_atlas")

-- Tunables
local VIEW_W, VIEW_H = 51, 19 -- adv computer fits nicely; tweak per UI
local HEARTBEAT_TTL = 12 -- seconds; if no heartbeat, drop player
local CLEANUP_PERIOD = 5 -- how often we scan for dead sessions
local HALF_W, HALF_H = math.floor(VIEW_W/2), math.floor(VIEW_H/2)

-- tick + movement rate
local TICK_HZ = 10					-- server ticks per second
local MOVE_COOLDOWN_TICKS = 2		-- 1 tile every 2 ticks => 5 tiles/sec at 10Hz

-- remember which client ID to send frames to
local sessions = {}					-- sessions[player_id] = computerID

local PROTO_MMO = "mmo"
rednet.host(PROTO_MMO, "mmo")

-- Players: [player_id] = { x=.., y=.., last_seen=os.clock() }
local players = {}

local function now() return os.clock() end


local function rect_contains(x, y, x1, y1, x2, y2)
	return x >= x1 and x <= x2 and y >= y1 and y <= y2
end

local function is_occupied(wx, wy, except_id)
	for id, p in pairs(players) do
		if id ~= except_id and p.x == wx and p.y == wy then
			return true
		end
	end
	return false
end

local function find_free_spawn(pref_x, pref_y, max_radius)
	pref_x = pref_x or 5
	pref_y = pref_y or 5
	max_radius = max_radius or 20

	-- Try the preferred spot first
	if not world.is_blocked(pref_x, pref_y) and not is_occupied(pref_x, pref_y) then
		return pref_x, pref_y
	end

	-- Spiral search outwards
	for r = 1, max_radius do
		for dx = -r, r do
			local wx = pref_x + dx
			local wy1 = pref_y - r
			local wy2 = pref_y + r
			if not world.is_blocked(wx, wy1) and not is_occupied(wx, wy1) then
				return wx, wy1
			end
			if not world.is_blocked(wx, wy2) and not is_occupied(wx, wy2) then
				return wx, wy2
			end
		end
		for dy = -r+1, r-1 do
			local wy = pref_y + dy
			local wx1 = pref_x - r
			local wx2 = pref_x + r
			if not world.is_blocked(wx1, wy) and not is_occupied(wx1, wy) then
				return wx1, wy
			end
			if not world.is_blocked(wx2, wy) and not is_occupied(wx2, wy) then
				return wx2, wy
			end
		end
	end
	-- Fallback: drop at pref regardless (last resort)
	return pref_x, pref_y
end

local function spawn_if_needed(id)
	if not players[id] then
		local sx, sy = find_free_spawn(50, 50)	-- center-ish for 100x100
		players[id] = { x = sx, y = sy, last_seen = os.clock() }
	end
end

local function touch(id)
	local p = players[id]
	if p then p.last_seen = now() end
end

local function try_move(id, dx, dy)
	local p = players[id]
	if not p then return false end
	local nx, ny = p.x + dx, p.y + dy
	if world.is_blocked(nx, ny) then return false end
	if is_occupied(nx, ny, id) then return false end
	p.x, p.y = nx, ny
	return true
end

-- Stamp a single glyph onto a term.blit row triplet at (sx, sy)
local function stamp(rows, sx, sy, ch, fg, bg)
	if sy < 1 or sy > #rows then return end
	local r = rows[sy]
	if sx < 1 or sx > #r.c then return end
	-- replace exactly one character/fg/bg at sx
	r.c  = r.c:sub(1, sx-1) .. ch .. r.c:sub(sx+1)
	r.fg = r.fg:sub(1, sx-1) .. fg .. r.fg:sub(sx+1)
	r.bg = r.bg:sub(1, sx-1) .. bg .. r.bg:sub(sx+1)
end

-- Draw all visible players onto the rows (centered at p.x,p.y)
local function overlay_players(rows, me_id, center_x, center_y)
	local x0 = center_x - HALF_W
	local y0 = center_y - HALF_H
	for id, op in pairs(players) do
		if id ~= me_id then
			-- screen coords relative to the viewport origin
			local sx = (op.x - x0) + 1
			local sy = (op.y - y0) + 1
			if sx >= 1 and sx <= VIEW_W and sy >= 1 and sy <= VIEW_H then
				-- render other players as '&' in bright cyan on black (tweak as you like)
				stamp(rows, sx, sy, "&", "f", "e")
			end
		end
	end
	-- draw ME last at center so I’s on top
	stamp(rows, HALF_W+1, HALF_H+1, "@", "f", "b")
end

local function make_view_packet(id, p)
	local rows = world.get_view(p.x, p.y, VIEW_W, VIEW_H)
	overlay_players(rows, id, p.x, p.y)
	return {
		type = "state",
		player = { x = p.x, y = p.y },
		rows   = rows,
		view_w = VIEW_W, view_h = VIEW_H
	}
end

local next_cleanup = now() + CLEANUP_PERIOD
local tick_timer = os.startTimer(1 / TICK_HZ)

print("[WORLD] Server online.")

while true do
	local ev, p1, p2 = os.pullEvent()  -- timer/rednet
	if ev == "rednet_message" then
		local sender, raw = p1, p2
		local ok, msg = pcall(textutils.unserialize, raw)
		if ok and type(msg) == "table" then
			local t = msg.type
			if t == "handshake" and msg.player_id then
				local id = msg.player_id
				sessions[id] = sender
				spawn_if_needed(id); touch(id)
				local p = players[id]
				local rows = world.get_view(p.x, p.y, VIEW_W, VIEW_H)
				overlay_players(rows, id, p.x, p.y)
				rednet.send(sender, textutils.serialize({
					type="handshake_ack", player={x=p.x,y=p.y}, rows=rows, view_w=VIEW_W, view_h=VIEW_H
				}), PROTO_MMO)

			elseif t == "input_state" and msg.player_id then
				local id = msg.player_id
				sessions[id] = sender
				spawn_if_needed(id); touch(id)
				players[id].input_dir = msg.dir

			elseif t == "heartbeat" and msg.player_id then
				sessions[msg.player_id] = sender
				touch(msg.player_id)

			elseif t == "logout" and msg.player_id then
				players[msg.player_id] = nil
				sessions[msg.player_id] = nil
				rednet.send(sender, textutils.serialize({type="bye"}), PROTO_MMO)
			end
		end

	elseif ev == "timer" and p1 == tick_timer then
		-- process one fixed tick
		for id, p in pairs(players) do
			-- cooldown
			if p.move_cd and p.move_cd > 0 then
				p.move_cd = p.move_cd - 1
			end
			-- apply input at fixed rate
			if (p.move_cd or 0) <= 0 and p.input_dir then
				local dx, dy = 0, 0
				if p.input_dir == "w" then dy = -1
				elseif p.input_dir == "s" then dy = 1
				elseif p.input_dir == "a" then dx = -1
				elseif p.input_dir == "d" then dx = 1 end
				if dx ~= 0 or dy ~= 0 then
					try_move(id, dx, dy)	-- already checks map + player collision
					p.move_cd = MOVE_COOLDOWN_TICKS
				end
			end
		end
		-- push frames to connected clients
		for id, cid in pairs(sessions) do
			local p = players[id]
			if p and cid then
				rednet.send(cid, textutils.serialize(make_view_packet(id, p)), PROTO_MMO)
			else
				sessions[id] = nil
			end
		end

		-- cleanup cadence
		local tnow = now()
		if tnow >= next_cleanup then
			next_cleanup = tnow + CLEANUP_PERIOD
			for id, p in pairs(players) do
				if (tnow - (p.last_seen or 0)) > HEARTBEAT_TTL then
					players[id] = nil
					sessions[id] = nil
				end
			end
		end

		-- schedule next tick
		tick_timer = os.startTimer(1 / TICK_HZ)
	end
end
