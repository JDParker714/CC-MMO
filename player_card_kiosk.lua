-- player_card_kiosk.lua
-- wget https://raw.githubusercontent.com/JDParker714/CC-MMO/refs/heads/main/player_card_kiosk.lua player_card_kiosk.lua

local modem = peripheral.find("modem", rednet.open)
local disk_drive = peripheral.find("drive")

if not disk_drive then
	print("No disk drive connected!")
	return
end

local function createPlayerCard()
	if not fs.exists("disk") then
		print("Please insert a floppy disk...")
		return
	end

	if fs.exists("disk/.player_id") then
		print("Warning: This disk already has a player card.")
		print("Overwriting will erase existing data. Continue? (y/n)")
		local confirm = read()
		if confirm:lower() ~= "y" then
			print("Aborting.")
			return
		end
	end

	write("Enter admin password to create new card: ")
	local admin_password = read("*")

	local verify_request = {
		type = "verify_admin",
		password = admin_password
	}

	rednet.broadcast(textutils.serialize(verify_request))
	local _, response_raw = rednet.receive(3)
	if not response_raw then
		print("Server did not respond.")
		return
	end

	local response = textutils.unserialize(response_raw)
	if response.status ~= "authorized" then
		print("Incorrect admin password.")
		disk_drive.ejectDisk()
		return
	end

	write("Enter username: ")
	local name = read()

	write("Enter password: ")
	local password = read("*")

	local max_retries = 5
	local attempt = 1
	local success = false
	local id = nil

	while attempt <= max_retries do
		id = "id_" .. tostring(math.random(1000000, 9999999))
		-- Send request to server
		local request = {
			type = "create_player",
			id = id,
			name = name,
			password = password
		}

		rednet.broadcast(textutils.serialize(request))
		local _, response_raw = rednet.receive(3)
		if not response_raw then
			print("Server did not respond.")
			return
		end

		local response = textutils.unserialize(response_raw)
		if response.status == "success" then
			success = true
			break
		elseif response.status == "duplicate" then
			print("ID collision (attempt " .. attempt .. "). Retrying...")
			attempt = attempt + 1
		else
			print("Unknown server response.")
			return
		end
	end

	if not success then
		print("Failed to generate a unique ID after " .. max_retries .. " attempts.")
		return
	end

	-- Write ID to floppy and label it
	local f = fs.open("disk/.player_id", "w")
	f.write(id)
	f.close()
	disk_drive.setDiskLabel(name .. "'s Card")
	print("Card created for " .. name .. " (ID: " .. id .. ")")
end

local function readPlayerCard()
	if not fs.exists("disk") then
		print("Please insert a Credit Card...")
		return
	end

	if not fs.exists("disk/.player_id") then
		print("No .player_id found on this Card.")
		return
	end

	local f = fs.open("disk/.player_id", "r")
	local id = f.readAll()
	f.close()

	local request = {
		type = "lookup_player",
		id = id
	}

	rednet.broadcast(textutils.serialize(request))
	local _, raw = rednet.receive(3)
	if not raw then
		print("No response from server.")
		return
	end

	local resp = textutils.unserialize(raw)
	if resp.status == "found" then
		local data = resp.data
		print("Name: " .. data.name)
		print("Balance: G" .. data.balance)
	else
		print("Player not found.")
	end
end

-- 📜 Menu Loop
while true do
	print("\n=== Player Card Kiosk ===")
	print("[1] Create New Player Card")
	print("[2] View Player Card Info")
	print("[3] Exit")
	write("> ")

	local choice = read()

	if choice == "1" then
		createPlayerCard()
	elseif choice == "2" then
		readPlayerCard()
	elseif choice == "3" then
		print("Goodbye.")
		disk_drive.ejectDisk()
	else
		print("Invalid option.")
	end

	print("\nPress any key to return to the menu...")
	os.pullEvent("key")
end
