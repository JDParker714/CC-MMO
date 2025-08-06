-- sell_shop.lua

-- Open the modem on any side
local modem = peripheral.find("modem", rednet.open)

local disk_drive = peripheral.find("drive")
local input_chest = peripheral.wrap("right")	-- change side as needed
local output_chest = peripheral.wrap("left")  -- change side as needed

if not disk_drive or not input_chest or not output_chest then
	print("Missing peripherals.")
	return
end

local function fetchPriceTable()
	local req = { type = "get_price_table" }
	rednet.broadcast(textutils.serialize(req))
	local _, raw = rednet.receive(3)
	if not raw then
		print("Failed to fetch price table from server.")
		return {}
	end

	local resp = textutils.unserialize(raw)
	if resp.status == "ok" and resp.prices then
		return resp.prices
	end

	print("Invalid response from server.")
	return {}
end

local price_table = fetchPriceTable()

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

	price_table = fetchPriceTable()
	if not next(price_table) then
		print("Unable to fetch pricing from server.")
		print("Please try again later.")
		disk_drive.ejectDisk()
		sleep(3)
		goto continue
	end

	print("Authenticated. Checking items in input chest...")

	local sold_total = 0
	local last_sale_time = os.clock()

	print("Your current balance: G" .. player.balance)

	print("You may now place items in the input chest to sell.")
	local has_notified = false
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
			player.balance = player.balance + sold_total
			print("G" .. sold_total .. " added to your balance.")
			print("New balance: G" .. player.balance)
			has_notified = false
			sold_total = 0
		end

		-- Wait 2s and check for logout or timeout
		if not has_notified then
			print("Press ENTER to log out, or place more items...")
			has_notified = true
		end
		
		local timer = os.startTimer(2)
		while true do
			local event, param = os.pullEventRaw()
			if event == "key" and param == keys.enter then
				print("Logging out...")
				goto logout
			elseif event == "timer" and os.clock() - last_sale_time > 60 then
				print("No activity. Logging out...")
				goto logout
			elseif event == "timer" then
				break -- repeat loop
			end
		end
	end

	::logout::

	disk_drive.ejectDisk()
	sleep(1)

	::continue::
end
