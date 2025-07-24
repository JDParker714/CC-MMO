-- master_server.lua
-- wget https://raw.githubusercontent.com/JDParker714/CC-MMO/refs/heads/main/master_server.lua master_server.lua

local ADMIN_PASSWORD = "#admin714"

local item_prices = {
	["minecraft:carrot"] = 1,
	["minecraft:gunpowder"] = 5
}

local data_file = "players.db"
local modem = peripheral.find("modem", rednet.open)

-- Load player database
local player_db = {}
if fs.exists(data_file) then
	local f = fs.open(data_file, "r")
	player_db = textutils.unserialize(f.readAll())
	f.close()
end

-- Save function
local function save_db()
	local f = fs.open(data_file, "w")
	f.write(textutils.serialize(player_db))
	f.close()
end

print("Player registration server running...")

while true do
	local sender, msg = rednet.receive()
	local data = textutils.unserialize(msg)

	if data and data.type == "create_player" then
		if player_db[data.id] then
			rednet.send(sender, textutils.serialize({ status = "duplicate" }))
		else
			player_db[data.id] = {
				name = data.name,
				password = data.password,
				balance = 100
			}
			save_db()
			rednet.send(sender, textutils.serialize({ status = "success" }))
			print("New player created: " .. data.name .. " (" .. data.id .. ")")
		end
	elseif data and data.type == "lookup_player" and player_db[data.id] then
		rednet.send(sender, textutils.serialize({
			status = "found",
			data = player_db[data.id]
		}))
	elseif data and data.type == "add_balance" and player_db[data.id] then
		player_db[data.id].balance = player_db[data.id].balance + data.amount
		save_db()
		rednet.send(sender, textutils.serialize({ status = "balance_updated" }))
		print("Updated balance for " .. player_db[data.id].name .. ": +" .. data.amount)
	elseif data and data.type == "verify_admin" then
		if data.password == ADMIN_PASSWORD then
			rednet.send(sender, textutils.serialize({ status = "authorized" }))
		else
			rednet.send(sender, textutils.serialize({ status = "unauthorized" }))
		end
	elseif data and data.type == "get_price_table" then
		rednet.send(sender, textutils.serialize({
			status = "ok",
			prices = item_prices
		}))
	else
		rednet.send(sender, textutils.serialize({ status = "not_found" }))
	end
end