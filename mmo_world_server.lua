-- world_server.lua
-- Server-authoritative movement + view streaming + heartbeat-based player cleanup.

local modem = peripheral.find("modem", rednet.open)

local world = require("mmo_world_atlas")
local entities = require("mmo_entities")
local mobs = {}	-- array of entities

-- Tunables
local VIEW_W, VIEW_H = 51, 17 -- adv computer fits nicely; tweak per UI
local HEARTBEAT_TTL = 12 -- seconds; if no heartbeat, drop player
local CLEANUP_PERIOD = 5 -- how often we scan for dead sessions
local HALF_W, HALF_H = math.floor(VIEW_W/2), math.floor(VIEW_H/2)

-- tick + movement rate
local TICK_HZ = 10					-- server ticks per second
local MOVE_COOLDOWN_TICKS = 2		-- 1 tile every 2 ticks => 5 tiles/sec at 10Hz

-- Dialogue tuning
local DIALOGUE_TRIGGER_RADIUS = 2         -- distance to start talking
local TYPEWRITER_CHARS_PER_TICK = 2       -- feel free to tweak
local DIALOGUE_LINE_HOLD_TICKS = 10       -- pause after each full line
local DIALOGUE_END_HOLD_TICKS  = 12       -- pause after last line

-- remember which client ID to send frames to
local sessions = {}					-- sessions[player_id] = computerID

local PROTO_MMO = "mmo"
rednet.host(PROTO_MMO, "mmo")

-- Players: [player_id] = { x=.., y=.., last_seen=os.clock() }
local players = {}

local function now() return os.clock() end


local function is_pos_free(wx, wy)
	if world.is_blocked(wx, wy) then return false end
	if world.is_inside(wx, wy) then return false end
	for _, p in pairs(players) do if p.x==wx and p.y==wy then return false end end
	for _, e in ipairs(mobs)   do if e.x==wx and e.y==wy then return false end end
	return true
end

local function spawn_n_mobs_random(kind, n)
	for i=1,n do
		local tries = 300
		repeat
			local wx = math.random(10, 240)
			local wy = math.random(10, 90)
			if is_pos_free(wx, wy) then
				table.insert(mobs, entities.new(kind, wx, wy))
				break
			end
			tries = tries - 1
		until tries <= 0
	end
end

local function spawn_npc(x, y, lines, name, visual)
	local npc = entities.new("npc", x, y, {
		name  = name or "NPC",
		lines = lines or {},
		-- optional visual overrides:
		glyph = visual and visual.glyph or "N",
		fg    = visual and visual.fg    or "0",  -- "0".."f" (term.blit hex)
		bg    = visual and visual.bg    or "3"
	})
	table.insert(mobs, npc)
end

-- Spawn Mobs
spawn_n_mobs_random("goblin", 16)
spawn_n_mobs_random("raider", 8)
spawn_n_mobs_random("dragon", 4)

local function is_occupied(wx, wy, except_id)
	for id, p in pairs(players) do
		if id ~= except_id and p.x == wx and p.y == wy then
			return true
		end
	end
	for _, e in ipairs(mobs) do 
		if e.x==wx and e.y==wy then 
			return true 	
		end 
	end
	return false
end

local function find_free_spawn(pref_x, pref_y, max_radius)
	pref_x = pref_x or 5
	pref_y = (pref_y-1) or 5
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

--42 Char Max a line

-- Spawn Npc's

-- Firstia
local npc_x, npc_y = find_free_spawn(130, 51, 5)
spawn_npc(npc_x, npc_y, {
  "Welcome adventurer, to the town of Firstia",
  "I am the Noble of these lands",
  "Please don't piss in the water supply",
  "We've had alot of people doing that lately",
  "Besides that, good luck and safe travels!"
}, "Lady Firstia", { glyph = "N", fg = "0", bg = "2" })

npc_x, npc_y = find_free_spawn(107, 47, 5)
spawn_npc(npc_x, npc_y, {
  "Ayyyyyy I'm J-O-R-K-I-N over here",
  "Or to be specific, Grand Magus Jorkin",
  "... over here",
  "I am the strongest wizard in Firstia",
  "I can teach you the secrets of magic",
  "As long as the secrets are cantrip level"
}, "Grand Magus Jorkin", { glyph = "N", fg = "0", bg = "b" })

npc_x, npc_y = find_free_spawn(92, 30, 5)
spawn_npc(npc_x, npc_y, {
  "Grab an ale and groop some soup you sloot",
  "Welcome the Karp Tavern!",
  "Today's soup is Griffin Noodle"
}, "Ms Tankard", { glyph = "N", fg = "0", bg = "4" })

npc_x, npc_y = find_free_spawn(91, 39, 5)
spawn_npc(npc_x, npc_y, {
  "Hey there fuckaroo my tits are down here",
  "I didn't put on this corset that squeezes",
  "My organs into a meatball for nothing",
  "But my cleavage do be boombastic tho",
  "So make sure to leave a good tip"
}, "Froth the Busty Lass", { glyph = "N", fg = "0", bg = "a" })

npc_x, npc_y = find_free_spawn(132, 26, 5)
spawn_npc(npc_x, npc_y, {
  "P r a i s e  Beeeee Hallelujah",
  "Drink a shot of fireball my child",
  "And smoke a pack of these menthol cigs",
  "As is his will.  Glory be to the hellz"
}, "High Priestess Natas", { glyph = "N", fg = "0", bg = "e" })

npc_x, npc_y = find_free_spawn(136, 40, 5)
spawn_npc(npc_x, npc_y, {
  "Oh god the spiders want my sperm cells",
  "Sorry I've been huffing soldering fumes",
  "I'm the town smith! I can craft,",
  "Any gear you can think of, as long as",
  "You bounce on it crazy style ;)"
}, "Alex the Smithy", { glyph = "N", fg = "0", bg = "1" })

npc_x, npc_y = find_free_spawn(142, 51, 5)
spawn_npc(npc_x, npc_y, {
  "Mess with Sir Buckle get the FUCKLE!!",
  "To be fair, I don't know what that is",
  "But I DO KNOW about Law and Order!",
  "Try not to break any laws adventurer"
}, "Sir Buckle", { glyph = "N", fg = "0", bg = "8" })

npc_x, npc_y = find_free_spawn(147, 41, 5)
spawn_npc(npc_x, npc_y, {
  "Ahhh! Don't shoot!!! I'm innocent!!",
  "Oh wait... You're not a town guard.",
  "I'm defitenly not innocent >:)",
  "That orphanage had it 2 good for 2 long",
  "If you need anything illegal done..",
  "Hit me up, maybe we make a deal."
}, "Looty McSticky-Fingers", { glyph = "N", fg = "0", bg = "7" })

npc_x, npc_y = find_free_spawn(157, 64, 5)
spawn_npc(npc_x, npc_y, {
  "Have you seen my wife around?",
  "I brought her some sheet metal to eat!",
  "Nothing bad happens to the Kennedy's!"
}, "JFK", { glyph = "N", fg = "0", bg = "b" })

npc_x, npc_y = find_free_spawn(171, 62, 5)
spawn_npc(npc_x, npc_y, {
  "Mooooooooo."
}, "Cow", { glyph = "N", fg = "0", bg = "f" })

-- MangoBay
npc_x, npc_y = find_free_spawn(232, 76, 5)
spawn_npc(npc_x, npc_y, {
  "Welcome to MangoBay! Grab a Pina Colada,",
  "and take it easy for a while!",
  "Wait... you've heard of me??",
  "Don't worry I haven't done capitalism",
  "in a while.  I'm on vacation!!",
  "I'm actually working on an MMO,",
  "WITHIN THIS MMO! INCEPTION FUCKERS!!!"
}, "Gold Magikarp", { glyph = "N", fg = "0", bg = "4" })

npc_x, npc_y = find_free_spawn(237, 94, 5)
spawn_npc(npc_x, npc_y, {
  "Great day for fishing, ain't it?",
  "Let minnow what you think of my jokes",
  "Aren't you kraken up?",
  "No?? You gotta be squidding me",
  "Well don't be crabby, try this one",
  "What has 8 arms and tells time?",
  "..... a Clock-topus"
}, "Iron Magikarp", { glyph = "N", fg = "0", bg = "8" })

npc_x, npc_y = find_free_spawn(204, 91, 5)
spawn_npc(npc_x, npc_y, {
  "We grow a lot of fruit here at MangoBay",
  "Coconuts, Mangos, Pineapples, n stuff",
  "We also have some... other crops ;)",
  "If you're cool you can buy some",
  "We got weed, ketamine, klonopin, & acid",
  "Oh shit, its the boat police! Act cool"
}, "Sapphire Magikarp", { glyph = "N", fg = "0", bg = "3" })

npc_x, npc_y = find_free_spawn(241, 39, 5)
spawn_npc(npc_x, npc_y, {
  "Eeeeeeeeeeee my brother sent me",
  "To get water from this well",
  "But told me I can only carry it",
  "with my hands... EEEEEEEEEEEEE",
  "I've been here 3 days ;-;"
}, "Copper Magikarp", { glyph = "N", fg = "0", bg = "1" })

-- Mountain
npc_x, npc_y = find_free_spawn(235, 4, 5)
spawn_npc(npc_x, npc_y, {
  "Well met adventurer, you've managed to",
  "climb my great mountain. My secret",
  "sanctuary of eep. Where I train, in the",
  "mystic arts of cool rocks, eep, and",
  "crafting memes so Gold will msg me back!",
  "Take a breath and recover, but beware",
  "ALL THE ROCKS ON THIS MOUNTAIN ARE MINE!"
}, "Ashe the Eeper of Worlds", { glyph = "N", fg = "0", bg = "a" })

-- Hive
npc_x, npc_y = find_free_spawn(15, 28, 5)
spawn_npc(npc_x, npc_y, {
  "... it didn't have to end this way",
  "We could have been bees",
  "This should have been good news",
  "We tried to live like a pet. A pet...",
  "But then the villager's started wanting",
  "Food.. Not just honey and violence",
  "We couldn't produce enough to feed them",
  "So I had to make a difficult decision...",
  "To burn it all down & unfound this place",
  "Bee gods forgive me for my crimes...",
  "Welp! Time for the fortress style!"
}, "Andy the Unfounder", { glyph = "N", fg = "0", bg = "e" })

npc_x, npc_y = find_free_spawn(52, 24, 5)
spawn_npc(npc_x, npc_y, {
  "Welcome traveler! To the Hive!!",
  "Oh wait, I guess I can't say that anymore",
  "The whole city was destroyed by our leader",
  "And now we must go find new homes..."
}, "Bee-atrice", { glyph = "N", fg = "0", bg = "1" })

npc_x, npc_y = find_free_spawn(27, 60, 5)
spawn_npc(npc_x, npc_y, {
  "Where will I go? What will I do?",
  "He took it all, my job, my home, my kids",
  "My life is empty now & the colony is gone",
  "This is a catastro-bee"
}, "Dr Bumble", { glyph = "N", fg = "0", bg = "1" })

npc_x, npc_y = find_free_spawn(29, 46, 5)
spawn_npc(npc_x, npc_y, {
  "Our leader didn't take that guy's kids",
  "I did >:)",
  "Got any baby oil on you?"
}, "Bee Diddy", { glyph = "N", fg = "0", bg = "1" })

--Castle
npc_x, npc_y = find_free_spawn(95, 9, 5)
spawn_npc(npc_x, npc_y, {
  "Welcome Adventurer! To my castle",
  "I am Devin, the King... of... ",
  "CHESTICUFFS!!! Challenge me, if you dare"
}, "King Devin", { glyph = "N", fg = "0", bg = "f" })

--Mines
npc_x, npc_y = find_free_spawn(40, 93, 5)
spawn_npc(npc_x, npc_y, {
  "When I was a kid I yearned for the mines",
  "And now that I'm in the mines, I yearn",
  "For quartz.  That yummy yummy quartz",
  "I've been mining quartz & shitting gravel",
  "For over 20 years"
}, "Cory Quartz-Eater", { glyph = "N", fg = "0", bg = "a" })

local function spawn_if_needed(id)
	if not players[id] then
		local sx, sy = find_free_spawn(125, 50)
		players[id] = {
			x = sx, y = sy,
			last_dx = 0, last_dy = 0,
			last_seen = now(),
			-- Input
			input_dir = nil,
			move_cd = 0,
			-- Player Stats
			lv = 10,
			hp = 100, hp_max = 100,
			mp = 50,  mp_max = 50,
			-- Dialogue (nil when not talking)
			dialogue = nil,      -- { speaker, lines, li, ci, hold, done, npc_x, npc_y }
			mode = "play"   -- "play" | "dialogue"
		}
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
				stamp(rows, sx, sy, "&", "f", "e")
			end
		end
	end
	-- draw ME last at center so I’s on top
	stamp(rows, HALF_W+1, HALF_H+1, "@", "f", "b")
end

local function overlay_entities(rows, center_x, center_y)
	local x0 = center_x - HALF_W
	local y0 = center_y - HALF_H
	for _, e in ipairs(mobs) do
		local sx = (e.x - x0) + 1
		local sy = (e.y - y0) + 1
		if sx>=1 and sx<=VIEW_W and sy>=1 and sy<=VIEW_H then
			local ch = e.glyph or "E"
			stamp(rows, sx, sy, ch, e.fg or "f", e.bg or "e")
		end
	end
end

local function make_view_packet(id, p)
	local rows = world.get_view(p.x, p.y, VIEW_W, VIEW_H)
	overlay_players(rows, id, p.x, p.y)
	overlay_entities(rows, p.x, p.y)

	local dlg = nil
	if p.dialogue then
		local line = p.dialogue.lines[p.dialogue.li] or ""
		dlg = {
			speaker = p.dialogue.speaker,
			line_i  = p.dialogue.li,
			line_n  = #p.dialogue.lines,
			text    = string.sub(line, 1, p.dialogue.ci),
		}
	end

	return {
		type = "state",
		player = {
			x = p.x, y = p.y,
			lv = p.lv,
			hp = p.hp, hp_max = p.hp_max,
			mp = p.mp, mp_max = p.mp_max,
			mode = p.mode, 
		},
		rows = rows,
		view_w = VIEW_W, view_h = VIEW_H,
		dialogue = dlg
	}
end

local function find_nearest_npc(px, py, radius)
	local best, bestd = nil, math.huge
	for _, e in ipairs(mobs) do
		if e.kind == "npc" then
			local d = math.abs(px - e.x) + math.abs(py - e.y)
			if d <= radius and d < bestd then best, bestd = e, d end
		end
	end
	return best
end

local function start_dialogue(p, npc)
	p.mode = "dialogue"
	p.dialogue = {
		speaker = npc.name or "NPC",
		lines   = npc.lines or {},
		li      = 1,     -- line index
		ci      = 0,     -- char index (typewriter progress)
		done    = false,
		npc_x   = npc.x, npc_y = npc.y
	}
end

local function tick_typewriter(p)
	if not p.dialogue or p.dialogue.done then return end
	local line = p.dialogue.lines[p.dialogue.li] or ""
	if p.dialogue.ci < #line then
		p.dialogue.ci = math.min(#line, p.dialogue.ci + TYPEWRITER_CHARS_PER_TICK)
	end
end

local function advance_or_close_dialogue(p)
	local d = p.dialogue
	if not d then return end
	local line = d.lines[d.li] or ""
	if d.ci < #line then
		-- finish current line instantly
		d.ci = #line
		return
	end
	-- already finished line -> go next or close
	d.li = d.li + 1
	d.ci = 0
	if d.li > #d.lines then
		p.dialogue = nil
		p.mode = "play"
	end
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
				overlay_entities(rows, p.x, p.y)   
				rednet.send(sender, textutils.serialize({
					type = "handshake_ack",
					player = {
						x = p.x, y = p.y,
						lv = p.lv,
						hp = p.hp, hp_max = p.hp_max,
						mp = p.mp, mp_max = p.mp_max
					},
					rows = rows,
					view_w = VIEW_W, view_h = VIEW_H
				}), PROTO_MMO)

			elseif t == "input_state" and msg.player_id then
				local id = msg.player_id
				sessions[id] = sender
				spawn_if_needed(id); touch(id)
				players[id].input_dir = msg.dir

			elseif msg.type == "interact" then
				local p = players[msg.player_id]
				if p then
					if p.mode ~= "dialogue" then
						local npc = find_nearest_npc(p.x, p.y, DIALOGUE_TRIGGER_RADIUS)
						if npc then start_dialogue(p, npc) end
					else
						advance_or_close_dialogue(p)
					end
				end

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
			-- player stats - example regen
			p.hp = math.min(p.hp_max, p.hp + 0)	-- set to >0 if you want regen
			p.mp = math.min(p.mp_max, p.mp + 0)	-- set to >0 if you want regen

			-- cooldown
			if p.move_cd and p.move_cd > 0 then
				p.move_cd = p.move_cd - 1
			end

			if p.mode == "dialogue" then
				tick_typewriter(p)   -- just animate the text; no movement
			else
				-- apply input at fixed rate
				if (p.move_cd or 0) <= 0 and p.input_dir then
					local dx, dy = 0, 0
					if p.input_dir == "w" then dy = -1
					elseif p.input_dir == "s" then dy = 1
					elseif p.input_dir == "a" then dx = -1
					elseif p.input_dir == "d" then dx = 1 end
					if dx ~= 0 or dy ~= 0 then
						try_move(id, dx, dy)	-- already checks map + player collision
						p.last_dx = dx
						p.last_dy = dy
						p.move_cd = MOVE_COOLDOWN_TICKS
					end
				end
			end
		end

		for _, e in ipairs(mobs) do
			e:step(players, mobs)
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
