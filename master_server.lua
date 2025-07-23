-- master_server.lua
-- wget https://raw.githubusercontent.com/JDParker714/CC-MMO/refs/heads/main/master_server.lua master_server.lua

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
	else
		rednet.send(sender, textutils.serialize({ status = "not_found" }))
	end
end