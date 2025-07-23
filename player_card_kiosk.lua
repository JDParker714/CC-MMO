-- player_card_kiosk.lua

local modem = peripheral.find("modem", rednet.open)
local disk_drive = peripheral.find("drive")

if not disk_drive then
  print("No disk drive connected!")
  return
end

local function waitForDisk()
  while not fs.exists("disk") do
    print("Please insert a floppy disk...")
    sleep(1)
  end
end

local function createPlayerCard()
  waitForDisk()

  write("Enter username: ")
  local name = read()

  write("Enter password: ")
  local password = read("*")

  local id = "id_" .. tostring(math.random(1000000, 9999999))

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
    print("❌ Server did not respond.")
    return
  end

  local response = textutils.unserialize(response_raw)
  if response.status == "duplicate" then
    print("⚠️ ID already exists. Try again.")
  elseif response.status == "success" then
    -- Write ID to floppy and label it
    local f = fs.open("disk/.player_id", "w")
    f.write(id)
    f.close()
    disk_drive.setDiskLabel(name .. "'s disk")
    print("✅ Card created for " .. name .. " (ID: " .. id .. ")")
  else
    print("❌ Unknown error.")
  end
end

local function readPlayerCard()
  waitForDisk()

  if not fs.exists("disk/.player_id") then
    print("No .player_id found on disk.")
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
    break
  else
    print("Invalid option.")
  end

  print("\nPress any key to return to the menu...")
  os.pullEvent("key")
end
