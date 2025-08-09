-- mmo_player_client.lua
-- Disk-drive auth (player card), password check via master_server.lua, then MMO client.
-- Renders a viewport centered on the player. Sends WASD to server, heartbeats periodically.
-- Advanced Computer required.

local modem = peripheral.find("modem", rednet.open)

local drive = peripheral.find("drive")
if not drive then error("No disk drive found") end

-- ========== Master Server helpers (matches your master_server.lua) ==========
local function ms_lookup_player(id)
	local req = { type = "lookup_player", id = id }
	rednet.broadcast(textutils.serialize(req))
	local _, raw = rednet.receive(3)
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
	rednet.broadcast(textutils.serialize({ type="handshake", player_id=player_id }))
	local _, raw = rednet.receive(3)
	if not raw then return nil, "No world server response" end
	local resp = textutils.unserialize(raw)
	if not resp or resp.type ~= "handshake_ack" then return nil, "Bad world handshake" end
	return resp
end

-- ========== Heartbeat ==========
local function heartbeat_loop(player_id)
	while true do
		rednet.broadcast(textutils.serialize({ type="heartbeat", player_id=player_id }))
		sleep(3)
	end
end

-- ========== Input/render loop ==========
local function gameplay_loop(player_id, handshake)
	local view_w, view_h = handshake.view_w, handshake.view_h
	local termW, termH = term.getSize()
	local ox = math.floor((termW - view_w)/2) + 1
	local oy = math.floor((termH - view_h)/2) + 1

	term.setBackgroundColor(colors.black)
	term.setCursorBlink(false)
	term.clear()

	blit_rows(handshake.rows, ox, oy)

	local running = true
	local function inputs()
		while running do
			local ev, p1 = os.pullEventRaw()
			if ev == "key" then
				local k = keys.getName(p1)
				if k == "w" or k == "a" or k == "s" or k == "d" then
					rednet.broadcast(textutils.serialize({ type="input", player_id=player_id, key=k }))
					local _, raw = rednet.receive(2)
					if raw then
						local st = textutils.unserialize(raw)
						if st and st.type == "state" then
							term.setBackgroundColor(colors.black); term.clear()
							blit_rows(st.rows, ox, oy)
						end
					end
				elseif k == "q" then
					running = false
				end
			elseif ev == "terminate" then
				-- Ctrl+T: attempt clean logout
				running = false
			end
		end
	end

	local function heartbeat()
		heartbeat_loop(player_id)
	end

	parallel.waitForAny(inputs, heartbeat)

	-- Try to logout cleanly
	rednet.broadcast(textutils.serialize({ type="logout", player_id=player_id }))
end

-- ========== Main ==========
while true do
	local auth = authenticate()
	if auth then
		local handshake, err = ws_handshake(auth.id)
		if not handshake then
			print(err or "World handshake failed.")
			drive.ejectDisk(); sleep(2)
		else
			pcall(gameplay_loop, auth.id, handshake)
			drive.ejectDisk()
		end
	end
	print("\n(Press any key to return to login...)"); os.pullEvent("key")
end
