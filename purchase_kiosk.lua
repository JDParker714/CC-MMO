local modem = peripheral.find("modem", rednet.open)
local drive = peripheral.find("drive")

if not drive then
	print("No disk drive found!")
	return
end

-- Get ID from disk
local function getPlayerId()
	local mount = drive.getMountPath()
	if not mount then return nil end
	local path = mount .. "/.player_id"
	if not fs.exists(path) then return nil end
	local f = fs.open(path, "r")
	local id = f.readAll()
	f.close()
	return id
end

-- Look up player data from server
local function lookupPlayer(id)
	local req = { type = "lookup_player", id = id }
	rednet.broadcast(textutils.serialize(req))
	local _, raw = rednet.receive(3)
	if not raw then return nil end
	local resp = textutils.unserialize(raw)
	if resp and resp.status == "found" then
		return resp.data
	end
	return nil
end

-- Send balance update to server
local function updateBalance(id, amount)
	local req = { type = "add_balance", id = id, amount = amount }
	rednet.broadcast(textutils.serialize(req))
end

-- Check admin password via server
local function verifyAdmin()
	write("Enter admin password: ")
	local pw = read("*")
	local req = { type = "verify_admin", password = pw }
	rednet.broadcast(textutils.serialize(req))
	local _, raw = rednet.receive(3)
	if not raw then return false end
	local resp = textutils.unserialize(raw)
	return resp.status == "authorized"
end

-- Main loop
while true do
	term.clear()
	term.setCursorPos(1, 1)
	print("=== Admin Purchase Terminal ===")
	print("[1] Purchase")
	print("[2] Exit")
	write("> ")
	local choice = read()

	if choice == "2" then
		print("Ejecting card...")
		drive.ejectDisk()
		sleep(1)
		break
	elseif choice ~= "1" then
		print("Invalid choice.")
		sleep(1)
		goto continue
	end

	print("Please insert a player card...")
	while not drive.isDiskPresent() do sleep(0.5) end

	local id = getPlayerId()
	if not id then
		print("Invalid card. Ejecting.")
		drive.ejectDisk()
		sleep(2)
		goto continue
	end

	local player = lookupPlayer(id)
	if not player then
		print("Could not find player.")
		drive.ejectDisk()
		sleep(2)
		goto continue
	end

	print("Player: " .. player.name)
	print("Balance: G" .. player.balance)

	if not verifyAdmin() then
		print("Incorrect admin password.")
		sleep(2)
		goto continue
	end

	write("Enter purchase amount to subtract: G")
	local amt_str = read()
	local amt = tonumber(amt_str)

	if not amt or amt <= 0 or amt ~= math.floor(amt) then
		print("Invalid amount.")
		sleep(2)
		goto continue
	end

	if amt > player.balance then
		print("Insufficient funds.")
		sleep(2)
		goto continue
	end

	updateBalance(id, -amt)
	print("Purchase complete! G" .. amt .. " removed.")
	print("New balance: G" .. (player.balance - amt))
	sleep(2)

::continue::
end