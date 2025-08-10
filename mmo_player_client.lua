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

	local in_dialogue = false

	-- ========== UI Functions ==========
	local function fit_text(s, maxw)
		if #s <= maxw then return s end
		if maxw <= 1 then return s:sub(1, maxw) end
		return s:sub(1, maxw-1) .. "…"
	end

	local function draw_box(x, y, w, h)
		local top    = "+" .. string.rep("-", w-2) .. "+"
		local mid    = "|" .. string.rep(" ", w-2) .. "|"
		term.setCursorPos(x, y); write(top)
		for i=1,h-2 do term.setCursorPos(x, y+i); write(mid) end
		term.setCursorPos(x, y+h-1); write(top)
	end

	local function draw_dialogue_box(dlg, hud_reserved_rows)
		if not dlg then return end
		local w, h = term.getSize()
		local box_h = 5
		local box_w = math.min(w-2, 46)  -- keep it tidy
		local bx = math.floor((w - box_w)/2) + 1
		local by = h - box_h - (hud_reserved_rows or 1)

		term.setTextColor(colors.white); term.setBackgroundColor(colors.black)
		draw_box(bx, by, box_w, box_h)

		-- Title
		local title = (" %s (%d/%d) "):format(dlg.speaker or "NPC", dlg.line_i or 1, dlg.line_n or 1)
		term.setCursorPos(bx + 2, by); write(title)

		-- Text (single line; can wrap later)
		local maxw = box_w - 4
		local s = dlg.text or ""
		if #s > maxw then s = s:sub(1, maxw) end
		term.setCursorPos(bx + 2, by + 2); write(s)

		-- Hint
		term.setCursorPos(bx + 2, by + box_h - 2); write("Press E to continue")
	end

	local function draw_hud_bottom()
		local w, h = term.getSize()
		local y1, y2 = h-1, h
		term.setBackgroundColor(colors.black)

		-- Line 1: name + level + hp + mp
		local lvStr = ("  Lv %d"):format(stats.lv or 1)
		local hpStr = ("Hp %d/%d"):format(stats.hp or 0, stats.hp_max or 0)
		local mpStr = ("Mp %d/%d"):format(stats.mp or 0, stats.mp_max or 0)
		local spacerStr = "  "

		local totalW = #spacerStr + #lvStr + #spacerStr + #hpStr + #spacerStr + #mpStr
		
		local nameMax = w - totalW
		local nameTxt = fit_text(player_name, nameMax)
		local remainingSpace = nameMax - #nameTxt
		
		term.setCursorPos(1, y1)

		-- Draw Name
		term.blit(nameTxt, string.rep("0", #nameTxt), string.rep("f", #nameTxt))
		if remainingSpace > 0 then term.blit(string.rep(" ", remainingSpace), string.rep("f", remainingSpace), string.rep("f", remainingSpace)) end

		-- Draw Level
		term.blit(spacerStr, string.rep("f", #spacerStr), string.rep("f", #spacerStr))
		term.blit(lvStr, string.rep("0", #lvStr), string.rep("f", #lvStr))

		-- Draw Health
		term.blit(spacerStr, string.rep("f", #spacerStr), string.rep("f", #spacerStr))
		term.blit(hpStr, string.rep("e", #hpStr), string.rep("f", #hpStr))

		-- Draw Mana
		term.blit(spacerStr, string.rep("f", #spacerStr), string.rep("f", #spacerStr))
		term.blit(mpStr, string.rep("b", #mpStr), string.rep("f", #mpStr))
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
				if (k == "w" or k == "a" or k == "s" or k == "d") and not in_dialogue then
					send_dir(k)
				elseif k == "q" then
					running = false
				elseif k == "e" then
					rednet.send(WORLD_ID, textutils.serialize({type="interact", player_id=player_id}), PROTO_MMO)
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
					stats.lv     = st.player.lv
					stats.hp     = st.player.hp
					stats.hp_max = st.player.hp_max
					stats.mp     = st.player.mp
					stats.mp_max = st.player.mp_max

					term.setBackgroundColor(colors.black); term.clear()

					blit_rows(st.rows, ox, oy)       -- draw the new frame
					draw_hud_bottom()    

					local server_mode = st.player and st.player.mode
					in_dialogue = (server_mode == "dialogue") or (st.dialogue ~= nil)
					if in_dialogue then
						draw_dialogue_box(st.dialogue, 1) -- '1' if your HUD uses one bottom row
					end
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
			local ok, err = pcall(gameplay_loop, auth.id, handshake, player_name, last_stats)
			if not ok then
				print("Client error: " .. tostring(err))
			else
				drive.ejectDisk()
			end
		end
	end
	print("\n(Press any key to return to login...)"); os.pullEvent("key")
end
