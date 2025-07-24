local modem = peripheral.find("modem", rednet.open)
local drive_left = peripheral.wrap("left")
local drive_right = peripheral.wrap("right")

-- Utility
local function getPlayerIdFromDrive(drive)
	if not drive.isDiskPresent() then return nil end
	local mount = drive.getMountPath()
	if not mount then return nil end
	local path = mount .. "/.player_id"
	if not fs.exists(path) then return nil end
	local f = fs.open(path, "r")
	local id = f.readAll()
	f.close()
	return id
end

local function getPlayerData(id)
	rednet.broadcast(textutils.serialize({ type = "lookup_player", id = id }))
	local _, raw = rednet.receive(3)
	if not raw then return nil end
	local resp = textutils.unserialize(raw)
	if resp and resp.status == "found" then
		return resp.data
	end
	return nil
end

local function updateBalance(id, amount)
	rednet.broadcast(textutils.serialize({
		type = "add_balance",
		id = id,
		amount = amount
	}))
end

-- Wait for both cards
local function waitForCards()
	print("Waiting for both player cards...")
	while true do
		local left_id = getPlayerIdFromDrive(drive_left)
		local right_id = getPlayerIdFromDrive(drive_right)
		if left_id and right_id then return left_id, right_id end
		sleep(1)
	end
end

-- Auth prompt
local function getPassword(player)
	write("Enter password for " .. player.name .. ": ")
	local pass = read("*")
	return pass == player.password
end

-- Main transfer loop
while true do
	term.clear()
	term.setCursorPos(1, 1)
	local left_id, right_id = waitForCards()

	local left_data = getPlayerData(left_id)
	local right_data = getPlayerData(right_id)

	if not left_data or not right_data then
		print("Error loading player data.")
		sleep(2)
		goto continue
	end

	print("=== Players Detected ===")
	print("Left:  " .. left_data.name .. " - G" .. left_data.balance)
	print("Right: " .. right_data.name .. " - G" .. right_data.balance)
	print()
	print("[1] " .. left_data.name .. " -> " .. right_data.name)
	print("[2] " .. right_data.name .. "-> " .. left_data.name)
	print("[3] Exit")
	write("> ")
	local choice = read()

	if choice == "3" then
		print("Ejecting cards...")
		drive_left.ejectDisk()
		drive_right.ejectDisk()
		sleep(1)
		goto continue
	elseif choice ~= "1" and choice ~= "2" then
		print("Invalid choice.")
		sleep(1)
		goto continue
	end

	-- Set transfer direction
	local sender_data = (choice == "1") and left_data or right_data
	local receiver_data = (choice == "1") and right_data or left_data
	local sender_id = (choice == "1") and left_id or right_id
	local receiver_id = (choice == "1") and right_id or left_id

	if not getPassword(sender_data) then
		print("Incorrect password.")
		sleep(2)
		goto continue
	end

	write("Enter amount to send: G")
	local amt_str = read()
	local amt = tonumber(amt_str)

	if not amt or amt <= 0 or amt ~= math.floor(amt) then
		print("Invalid amount.")
		sleep(2)
		goto continue
	end

	if amt > sender_data.balance then
		print("Insufficient funds.")
		sleep(2)
		goto continue
	end

	-- Perform transfer
	updateBalance(sender_id, -amt)
	updateBalance(receiver_id, amt)

	print("Transfer complete!")
    print(sender_data.name .. "Sent G" .. amt .. " to " .. receiver_data.name)
	print(sender_data.name .. ": G" .. (sender_data.balance - amt))
	print(receiver_data.name .. ": G" .. (receiver_data.balance + amt))

	sleep(5)

::continue::
end