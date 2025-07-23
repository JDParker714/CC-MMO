-- sell_shop.lua

local modem = peripheral.find("modem", rednet.open)
local disk_drive = peripheral.find("drive")
local input_chest = peripheral.wrap("left")	-- change side as needed
local output_chest = peripheral.wrap("back")  -- change side as needed

if not disk_drive or not modem or not input_chest or not output_chest then
	print("Missing peripherals.")
	return
end

local price_table = {
	["minecraft:carrot"] = 1
}

local function readPlayerId()
	if not fs.exists("disk/.player_id") then
		return nil
	end
	local f = fs.open("disk/.player_id", "r")
	local id = f.readAll()
	f.close()
	return id
end

local function lookupPlayer(id)
	local req = { type = "lookup_player", id = id }
	rednet.broadcast(textutils.serialize(req))
	local _, raw = rednet.receive(3)
	if raw then
		local resp = textutils.unserialize(raw)
		if resp.status == "found" then
			return resp.data
		end
	end
	return nil
end

local function updateBalance(id, amount)
	local req = {
		type = "add_balance",
		id = id,
		amount = amount
	}
	rednet.broadcast(textutils.serialize(req))
end

local function waitForPlayerDisk()
	while true do
		if fs.exists("disk/.player_id") then
			return true
		end
		sleep(1)
	end
end

-- Main loop
while true do
	print("\n=== Sell Shop Terminal ===")
	print("Insert your player card to begin...")

	waitForPlayerDisk()
	local id = readPlayerId()
	local player = lookupPlayer(id)

	if not player then
		print("Invalid card. Ejecting.")
		disk_drive.ejectDisk()
		sleep(2)
		goto continue
	end

	print("Welcome, " .. player.name)
	write("Enter password: ")
	local pass = read("*")
	if pass ~= player.password then
		print("Incorrect password.")
		disk_drive.ejectDisk()
		sleep(2)
		goto continue
	end

	print("Authenticated. Checking items in input chest...")

	local sold_total = 0
	local last_sale_time = os.clock()

	while true do
		local items = input_chest.list()
		local sold_something = false

		for slot, item in pairs(items) do
			local price = price_table[item.name]
			if price then
				input_chest.pushItems(peripheral.getName(output_chest), slot)
				sold_total = sold_total + price * item.count
				sold_something = true
				print("Sold " .. item.count .. "x " .. item.name .. " for G" .. (price * item.count))
				last_sale_time = os.clock()
				sleep(0.5)
			end
		end

		if sold_total > 0 then
			updateBalance(id, sold_total)
			print("G" .. sold_total .. " added to your balance.")
			sold_total = 0
		end

		print("Press ENTER to log out, or wait to sell more.")
		local timeout = 60 - (os.clock() - last_sale_time)
		local event, key = os.pullEvent("char")
		if key == "\n" or timeout <= 0 then
			print("Logging out...")
			break
		end
	end

	disk_drive.ejectDisk()

	::continue::
end
