-- === SMART STRIP MINER v1 ===
-- Grid mining with ore detection, auto-refuel, and memory

-- == CONFIG ==
local spacing = 3  -- spacing between tunnels (3 = skip 2 blocks)
local tunnel_length = 20 -- distance forward for each tunnel
local FUEL_BUFFER = 20   -- safety margin
local REFUEL_ITEM = "minecraft:coal"

-- == STATE ==
local mined_db = {}
local min_y, max_y, radius
local home_x, home_y, home_z = 0, 0, 0
local facing = 0 -- 0=north - Y-, 1=east - X+, 2=south - Y+, 3=west - X-
local home_facing = 0

-- == UTILS ==
function promptNumber(prompt)
  print(prompt)
  local input = read()
  return tonumber(input)
end

function saveMined(x, y, z)
  local key = string.format("%d,%d,%d", x, y, z)
  mined_db[key] = true
  local file = fs.open("mined_coords.db", "a")
  file.writeLine(key)
  file.close()
end

function hasMined(x, y, z)
  return mined_db[string.format("%d,%d,%d", x, y, z)]
end

function loadMinedDB()
  if not fs.exists("mined_coords.db") then return end
  local file = fs.open("mined_coords.db", "r")
  for line in file.readLine do
    mined_db[line] = true
  end
  file.close()
end

function getPosition()
  local x, y, z = gps.locate(2)
  return x, y, z
end

function face(dir)
  while facing ~= dir do
    turtle.turnRight()
    facing = (facing + 1) % 4
  end
end

function forward()
  while not turtle.forward() do
    turtle.dig()
    sleep(0.2)
  end
end

function up()
  while not turtle.up() do
    turtle.digUp()
    sleep(0.2)
  end
end

function down()
  while not turtle.down() do
    turtle.digDown()
    sleep(0.2)
  end
end

function digSafe()
  local success, data = turtle.inspect()
  if success and data.name:find("chest") then return end
  turtle.dig()
end

function digSafeDown()
  local success, data = turtle.inspectDown()
  if success and data.name:find("chest") then return end
  turtle.digDown()
end

function digVeins()
  local directions = {
    {turtle.inspect, turtle.dig},
    {turtle.inspectUp, turtle.digUp},
    {turtle.inspectDown, turtle.digDown},
  }

  for _, dir in ipairs(directions) do
    local inspect, dig = unpack(dir)
    local success, data = inspect()
    if success and data.name:find("ore") then
      dig()
    end
  end
end

function isInventoryFull()
  for i = 1, 16 do
    if turtle.getItemCount(i) == 0 then return false end
  end
  return true
end

function refuelIfNeeded()
  local x, y, z = getPosition()
  local distance = math.abs(x - home_x) + math.abs(y - home_y) + math.abs(z - home_z)
  if turtle.getFuelLevel() < distance + FUEL_BUFFER then
    print("[Fuel low] Attempting to refuel...")
    for i = 1, 16 do
      turtle.select(i)
      local item = turtle.getItemDetail()
      if item and item.name == REFUEL_ITEM then
        turtle.refuel()
        if turtle.getFuelLevel() >= distance + FUEL_BUFFER then
          print("Refueled successfully.")
          return
        end
      end
    end
    print("Fuel too low. Returning home to refuel.")
    returnHome()
    dropOff()
    refuelChest()
  end
end

function dropOff()
  face(home_facing) -- face chest
  for i = 1, 16 do
    turtle.select(i)
    local item = turtle.getItemDetail()
    if item and item.name ~= REFUEL_ITEM then
      turtle.drop()
    end
  end
end

function refuelChest()
  face(home_facing)
  for i = 1, 16 do
    turtle.select(i)
    local item = turtle.getItemDetail()
    if not item then
      turtle.suck()
      item = turtle.getItemDetail()
      if item and item.name == REFUEL_ITEM then
        turtle.refuel()
      end
    end
  end
end

function returnHome()
  print("Returning home to (" .. home_x .. ", " .. home_y .. ", " .. home_z .. ")...")
  local x, y, z = getPosition()
  while y < home_y do up() y = y + 1 end
  while y > home_y do down() y = y - 1 end

  if x > home_x then face(3) while x > home_x do forward() x = x - 1 end
  elseif x < home_x then face(1) while x < home_x do forward() x = x + 1 end end

  if z > home_z then face(0) while z > home_z do forward() z = z - 1 end
  elseif z < home_z then face(2) while z < home_z do forward() z = z + 1 end end
  print("Arrived at home.")
end

function goToOffset(xOffset, zOffset, yTarget)
  -- From home position
  local x, y, z = getPosition()
  
  -- Go to Y level first
  while y > yTarget do digSafeDown(); down(); y = y - 1 end
  while y < yTarget do up(); y = y + 1 end

  -- Move in X direction
  if xOffset > 0 then face(1) else face(3) end
  for i = 1, math.abs(xOffset) do
    digSafe()
    forward()
  end

  -- Move in Z direction
  if zOffset > 0 then face(2) else face(0) end
  for i = 1, math.abs(zOffset) do
    digSafe()
    forward()
  end
end

function mineTunnel(xOffset, zOffset, yLevel)
  print("=== Mining tunnel at (" .. xOffset .. ", " .. zOffset .. ", Y=" .. yLevel .. ") ===")
  if hasMined(xOffset, yLevel, zOffset) then
    print("Already mined. Skipping...")
    return
  end

  print("Navigating to tunnel start...")
  goToOffset(xOffset, zOffset, yLevel)

  -- Tunnel direction based on Z to alternate rows
  if zOffset % 2 == 0 then face(1) else face(3) end

  for i = 1, tunnel_length do
    digSafe()
    forward()
    digVeins()
    print("Progress: " .. i .. "/" .. tunnel_length)

    if isInventoryFull() then
      print("[Inventory full] Returning to drop off...")
      saveMined(xOffset, yLevel, zOffset)
      returnHome()
      dropOff()
      refuelIfNeeded()
      return
    end
    refuelIfNeeded()
  end

  saveMined(xOffset, yLevel, zOffset)
  
end

-- == MAIN ==
print("Smart Miner Booting Up...")
min_y = promptNumber("Enter min Y level:")
max_y = promptNumber("Enter max Y level:")
radius = promptNumber("Enter radius from start:")

home_x, home_y, home_z = getPosition()
print("Home set to:", home_x, home_y, home_z)
print("Which way is the chest? Enter direction (0=north, 1=east, 2=south, 3=west):")
facing = tonumber(read())
home_facing = facing

loadMinedDB()
refuelIfNeeded()

for y = max_y, min_y, -3 do
  for dx = -radius, radius, spacing do
    for dz = -radius, radius, spacing do
      mineTunnel(dx, dz, y)
    end
  end
end

print("Mining complete.")
returnHome()
dropOff()
