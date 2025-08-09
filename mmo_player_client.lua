-- mmo_player_client.lua
-- Disk-drive auth (player card), password check via master_server.lua, then MMO client.
-- Renders a viewport centered on the player. Sends WASD to server, heartbeats periodically.
-- Advanced Computer required.

local modem = peripheral.find("modem", rednet.open)

local drive = peripheral.find("drive")
if not drive then error("No disk drive found") end

local PROTO_MMO = "mmo"
local PROTO_MS  = "master"

local MASTER_ID = rednet.lookup(PROTO_MS,  "master")
if not MASTER_ID then error("Master server not found") end

local WORLD_ID  = rednet.lookup(PROTO_MMO, "mmo")
if not WORLD_ID then error("MMO world server not found") end

-- ========== Master Server helpers (matches your master_server.lua) ==========
local function ms_lookup_player(id)
	local req = { type = "lookup_player", id = id }
	rednet.send(MASTER_ID, textutils.serialize(req), PROTO_MS)
	local _, raw = rednet.receive(PROTO_MS, 3)
	if not raw then return nil end
	local resp = textutils.unserialize(raw)
	if resp and resp.status == "found" then return resp.data end
	return nil
end

-- ========== Player card auth ==========
local function wait_for_card()
	while not fs.exists("disk/.player_id") do sleep(0.5) end
end
local function read_player_id()
	local f = fs.open("disk/.player_id", "r")
	local id = f.readAll()
	f.close()
	return id
end

local function authenticate()
	term.clear(); term.setCursorPos(1,1)
	print("Insert player card to log in...")
	wait_for_card()
	local id = read_player_id()
	if not id or id == "" then
		print("Bad card. Try again."); drive.ejectDisk(); sleep(1); return nil
	end

	local player = ms_lookup_player(id)
	if not player then
		print("Unknown player. See admin to register."); drive.ejectDisk(); sleep(2); return nil
	end

	write(("Welcome, %s\nEnter password: "):format(player.name))
	local pass = read("*")
	if pass ~= player.password then
		print("Incorrect password."); drive.ejectDisk(); sleep(1.5); return nil
	end

	print("Authenticated. Starting MMO...")
	sleep(0.4)
	return { id = id, name = player.name }
end

-- ========== Render helpers ==========
local function blit_rows(rows, ox, oy)
	for i=1,#rows do
		local r = rows[i]
		term.setCursorPos(ox, oy + i - 1)
		term.blit(r.c, r.fg, r.bg)
	end
end

-- ========== World Server handshake ==========
local function ws_handshake(player_id)
	rednet.send(WORLD_ID, textutils.serialize({ type="handshake", player_id=player_id }), PROTO_MMO)
	local _, raw = rednet.receive(PROTO_MMO, 3)
	if not raw then return nil, "No world server response" end
	local resp = textutils.unserialize(raw)
	if not resp or resp.type ~= "handshake_ack" then return nil, "Bad world handshake" end
	return resp
end

-- ========== Input/render loop ==========
local function gameplay_loop(player_id, handshake, player_name, stats)
	local HUD_ROWS = 2
	local view_w, view_h = handshake.view_w, handshake.view_h
	local termW, termH = term.getSize()
	local ox = math.floor((termW - view_w)/2) + 1
	local oy = math.floor((termH - HUD_ROWS - view_h)/2) + 1
	if oy < 1 then oy = 1 end

	stats.lv     = handshake.player.lv
	stats.hp     = handshake.player.hp
	stats.hp_max = handshake.player.hp_max
	stats.mp     = handshake.player.mp
	stats.mp_max = handshake.player.mp_max

	-- ========== UI Functions ==========
	local function fit_text(s, maxw)
		if #s <= maxw then return s end
		if maxw <= 1 then return s:sub(1, maxw) end
		return s:sub(1, maxw-1) .. "…"
	end

	local function draw_hud_bottom()
		local w, h = term.getSize()
		local y1, y2 = h-1, h
		term.setBackgroundColor(colors.black)

		-- Line 1: name + level (white on black)
		local lvStr = ("  Lv %d"):format(stats.lv or 1)
		local lvW   = #lvStr
		
		local nameMax = w - lvW
		local nameTxt = fit_text(player_name, nameMax)
		
		if nameMax > 0 and #nameTxt > 0 then
			term.setCursorPos(1, y1)
			term.blit(nameTxt, string.rep("0", #nameTxt), string.rep("f", #nameTxt))
			-- pad leftover gap (if any) up to the start of the Lv block
			if #nameTxt < nameMax then
				local gap = nameMax - #nameTxt
				term.blit(string.rep(" ", gap), string.rep("0", gap), string.rep("f", gap))
			end
		else
			-- clear line if name area is zero
			term.setCursorPos(1, y1)
			term.blit(string.rep(" ", nameMax), string.rep("0", nameMax), string.rep("f", nameMax))
		end

		-- draw Lv block right-aligned
		local lvX = w - lvW + 1
		term.setCursorPos(lvX, y1)
		term.blit(lvStr, string.rep("0", lvW), string.rep("f", lvW))

		-- ===== Line 2: HP red, spacer white, MP blue =====
		local hpTxt = ("Hp %d/%d"):format(stats.hp or 0, stats.hp_max or 0)
		local mpTxt = ("Mp %d/%d"):format(stats.mp or 0, stats.mp_max or 0)
		local spacer = "  "

		local c2 = hpTxt .. spacer .. mpTxt
		if #c2 > w then c2 = fit_text(c2, w) end

		local hpLen = math.min(#hpTxt, #c2)
		local spLen = math.max(0, math.min(#spacer, #c2 - hpLen))
		local mpLen = math.max(0, #c2 - hpLen - spLen)

		local fg2 = string.rep("e", hpLen) .. string.rep("0", spLen) .. string.rep("b", mpLen) -- red/white/blue
		local bg2 = string.rep("f", #c2)                                                        -- black

		term.setCursorPos(1, y2)
		term.blit(c2, fg2, bg2)
		if #c2 < w then
			term.blit(string.rep(" ", w-#c2), string.rep("0", w-#c2), string.rep("f", w-#c2))
		end
	end

	term.setBackgroundColor(colors.black)
	term.setCursorBlink(false)
	term.clear()

	blit_rows(handshake.rows, ox, oy)
	draw_hud_bottom()

	local cur_dir = nil
	local function send_dir(dir)
		if dir ~= cur_dir then
			cur_dir = dir
			rednet.send(WORLD_ID, textutils.serialize({type="input_state", player_id=player_id, dir=cur_dir}), PROTO_MMO)
		end
	end

	local running = true
	local function inputs()
		while running do
			local ev, p = os.pullEventRaw()
			if ev == "key" then
				local k = keys.getName(p)
				if k == "w" or k == "a" or k == "s" or k == "d" then
					send_dir(k)
				elseif k == "q" then
					running = false
				end
			elseif ev == "key_up" then
				local k = keys.getName(p)
				if cur_dir == k then
					send_dir(nil)
				end
			elseif ev == "terminate" then
				running = false
			end
		end
	end

	local function heartbeat()
		while running do
			rednet.send(WORLD_ID, textutils.serialize({type="heartbeat", player_id=player_id}), PROTO_MMO)
			-- optional: re-assert input state to be safe
			rednet.send(WORLD_ID, textutils.serialize({type="input_state", player_id=player_id, dir=cur_dir}), PROTO_MMO)
			sleep(3)
		end
	end

	local function updates()
		while running do
			local _, raw = rednet.receive(PROTO_MMO, 1)
			if raw then
				local st = textutils.unserialize(raw)
				if st and st.type == "state" then
					stats.lv     = handshake.player.lv
					stats.hp     = handshake.player.hp
					stats.hp_max = handshake.player.hp_max
					stats.mp     = handshake.player.mp
					stats.mp_max = handshake.player.mp_max

					term.setBackgroundColor(colors.black); term.clear()

					blit_rows(st.rows, ox, oy)       -- draw the new frame
					draw_hud_bottom()    
				end
			end
		end
	end

	parallel.waitForAny(inputs, heartbeat, updates)

	-- Try to logout cleanly
	rednet.send(WORLD_ID, textutils.serialize({ type="logout", player_id=player_id }), PROTO_MMO)
end

-- ========== Main ==========

while true do
	local auth = authenticate()

	local player_name = auth and auth.name or "Player"
	local last_stats = {
		lv = 10,
		hp = 100, hp_max = 100,
		mp = 50,  mp_max = 50
	}

	if auth then
		local handshake, err = ws_handshake(auth.id)
		if not handshake then
			print(err or "World handshake failed.")
			drive.ejectDisk(); sleep(2)
		else
			pcall(gameplay_loop, auth.id, handshake, player_name, last_stats)
			drive.ejectDisk()
		end
	end
	print("\n(Press any key to return to login...)"); os.pullEvent("key")
end
