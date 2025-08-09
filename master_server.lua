-- master_server.lua
-- wget https://raw.githubusercontent.com/JDParker714/CC-MMO/refs/heads/main/master_server.lua master_server.lua

local ADMIN_PASSWORD = "#admin714"

local item_prices = {
	-- Vanilla crops
	["minecraft:wheat"] = 1,
	["minecraft:potato"] = 1,
	["minecraft:carrot"] = 1,
	["minecraft:beetroot"] = 1,
	["minecraft:sugar_cane"] = 1,
	["minecraft:pumpkin"] = 3,
	["minecraft:melon_slice"] = 1,
	["minecraft:nether_wart"] = 1,
	["minecraft:cocoa_beans"] = 1,
	["minecraft:red_mushroom"] = 2,
	["minecraft:brown_mushroom"] = 2,
	["minecraft:glow_berries"] = 2,

	-- Cactus
	["minecraft:cactus"] = 2,

	-- Eggs
	["minecraft:egg"] = 2,

	-- Raw meats
	["minecraft:beef"] = 10,
	["minecraft:chicken"] = 10,
	["minecraft:porkchop"] = 10,
	["minecraft:mutton"] = 10,
	["minecraft:rabbit"] = 10,

	-- Aquaculture
	["aquaculture:fish_fillet_raw"] = 5,

	-- Farmer's Delight / Rustic Delight / Expanded Delight crops
	["farmersdelight:cabbage"] = 1,
	["farmersdelight:tomato"] = 1,
	["farmersdelight:onion"] = 1,
	["farmersdelight:rice"] = 1,
	["rusticdelight:bell_pepper_red"] = 1,
	["rusticdelight:bell_pepper_green"] = 1,
	["rusticdelight:bell_pepper_yellow"] = 1,
	["rusticdelight:coffee_beans"] = 1,
	["expandeddelight:asparagus"] = 1,
	["expandeddelight:sweet_potato"] = 1,
	["expandeddelight:chili_pepper"] = 1,
	["expandeddelight:peanut"] = 1,

	-- Minecolonies exclusive crops (example entries)
	["minecolonies:eggplant"] = 5,
	["minecolonies:garlic"] = 5,
	["minecolonies:onion"] = 5,  -- if they override vanilla
	["minecolonies:tomato"] = 5,
	["minecolonies:peanut"] = 5,
	["minecolonies:nether_pepper"] = 5,
	["minecolonies:peas"] = 5,
	["minecolonies:mint"] = 8,
	["minecolonies:corn"] = 5,

	["minersdelight:cave_carrot"] = 1,

	-- Fruit
	["fruitsdelight:pear"] = 1,
	["fruitsdelight:lychee"] = 1,
	["fruitsdelight:mango"] = 2,
	["fruitsdelight:persimmon"] = 1,
	["fruitsdelight:peach"] = 1,
	["fruitsdelight:orange"] = 1,
	["fruitsdelight:kiwi"] = 1,
	["fruitsdelight:lemon"] = 1,
	["fruitsdelight:pineapple"] = 2,

	-- Common ores
	["minecraft:coal"] = 10,
	["minecraft:redstone"] = 10,
	["minecraft:lapis_lazuli"] = 10,
	["minecraft:iron_ingot"] = 25,
	["minecraft:copper_ingot"] = 10,

	-- Valuable ores
	["minecraft:gold_ingot"] = 30,
	["minecraft:diamond"] = 60,
	["minecraft:netherite_ingot"] = 400
}

local data_file = "players.db"
local modem = peripheral.find("modem", rednet.open)

local PROTO_MS = "master"
rednet.host(PROTO_MS, "master")

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
	local sender, msg = rednet.receive(PROTO_MS)
	local data = textutils.unserialize(msg)

	if data and data.type == "create_player" then
		if player_db[data.id] then
			rednet.send(sender, textutils.serialize({ status = "duplicate" }), PROTO_MS)
		else
			player_db[data.id] = {
				name = data.name,
				password = data.password,
				balance = 100
			}
			save_db()
			rednet.send(sender, textutils.serialize({ status = "success" }), PROTO_MS)
			print("New player created: " .. data.name .. " (" .. data.id .. ")")
		end
	elseif data and data.type == "lookup_player" and player_db[data.id] then
		rednet.send(sender, textutils.serialize({
			status = "found",
			data = player_db[data.id]
		}), PROTO_MS)
	elseif data and data.type == "add_balance" and player_db[data.id] then
		player_db[data.id].balance = player_db[data.id].balance + data.amount
		save_db()
		rednet.send(sender, textutils.serialize({ status = "balance_updated" }), PROTO_MS)
		print("Updated balance for " .. player_db[data.id].name .. ": +" .. data.amount)
	elseif data and data.type == "verify_admin" then
		if data.password == ADMIN_PASSWORD then
			rednet.send(sender, textutils.serialize({ status = "authorized" }), PROTO_MS)
		else
			rednet.send(sender, textutils.serialize({ status = "unauthorized" }), PROTO_MS)
		end
	elseif data and data.type == "get_price_table" then
		rednet.send(sender, textutils.serialize({
			status = "ok",
			prices = item_prices
		}), PROTO_MS)
	else
		rednet.send(sender, textutils.serialize({ status = "not_found" }), PROTO_MS)
	end
end