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
  local diff = (dir - facing) % 4
  if diff == 0 then
    return -- Already facing correct direction
  elseif diff == 1 then
    turtle.turnRight()
    facing = (facing + 1) % 4
  elseif diff == 2 then
    turtle.turnRight()
    facing = (facing + 1) % 4
    turtle.turnRight()
    facing = (facing + 1) % 4
  elseif diff == 3 then
    turtle.turnLeft()
    facing = (facing - 1) % 4
    if facing < 0 then facing = facing + 4 end
  end
end

function forward()
  while not turtle.forward() do
    turtle.dig()
    sleep(0.2)
  end
end

function back()
  turtle.back()
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

function goTo(xTarget, yTarget, zTarget)
  print("Moving to (" .. xTarget .. ", " .. yTarget .. ", " .. zTarget .. ")...")
  local x, y, z = getPosition()

  -- Move in X direction
  if xTarget > x then face(1) else face(3) end
  while x ~= xTarget do
    digSafe()
    forward()
    x = (xTarget > x) and (x + 1) or (x - 1)
  end

  -- Move in Z direction
  if zTarget > z then face(2) else face(0) end
  while z ~= zTarget do
    digSafe()
    forward()
    z = (zTarget > z) and (z + 1) or (z - 1)
  end

  -- Go to correct Y first (to avoid breaking chest on return)
  while y > yTarget do down(); y = y - 1 end
  while y < yTarget do up(); y = y + 1 end
end

function goFromHome(xTarget, yTarget, zTarget)
  print("Moving to (" .. xTarget .. ", " .. yTarget .. ", " .. zTarget .. ")...")
  local x, y, z = getPosition()

  -- Go to correct Y first (to avoid breaking chest on return)
  while y > yTarget do down(); y = y - 1 end
  while y < yTarget do up(); y = y + 1 end

  -- Move in X direction
  if xTarget > x then face(1) else face(3) end
  while x ~= xTarget do
    digSafe()
    forward()
    x = (xTarget > x) and (x + 1) or (x - 1)
  end

  -- Move in Z direction
  if zTarget > z then face(2) else face(0) end
  while z ~= zTarget do
    digSafe()
    forward()
    z = (zTarget > z) and (z + 1) or (z - 1)
  end
end

function isOre(blockName)
  local ore_keywords = {"ore", "raw", "ancient_debris"}
  for _, keyword in ipairs(ore_keywords) do
    if blockName:find(keyword) then
      return true
    end
  end
  return false
end

function digVeins(depth)
  if depth <= 0 then return end

  local x0, y0, z0 = getPosition()
  local f0 = facing

  -- Define direction handlers
  local function tryDig(inspectFunc, digFunc, moveFunc, backFunc, d)
    local success, data = inspectFunc()
    if success and isOre(data.name) then
      digFunc()
      moveFunc()
      digVeins(d - 1)
      backFunc()
    end
  end

  -- Forward
  tryDig(turtle.inspect, turtle.dig, forward, back, depth)

  -- Up
  tryDig(turtle.inspectUp, turtle.digUp, up, down, depth)

  -- Down
  tryDig(turtle.inspectDown, turtle.digDown, down, up, depth)

  -- Left
  face((f0 + 3) % 4)
  tryDig(turtle.inspect, turtle.dig, forward, back, depth)
  face(f0)

  -- Right
  face((f0 + 1) % 4)
  tryDig(turtle.inspect, turtle.dig, forward, back, depth)
  face(f0)
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

  if x > home_x then face(3) while x > home_x do forward() x = x - 1 end
  elseif x < home_x then face(1) while x < home_x do forward() x = x + 1 end end

  if z > home_z then face(0) while z > home_z do forward() z = z - 1 end
  elseif z < home_z then face(2) while z < home_z do forward() z = z + 1 end end

  while y < home_y do up() y = y + 1 end
  while y > home_y do down() y = y - 1 end
  print("Arrived at home.")
end

function goToOffset(xOffset, zOffset, yTarget)
  local xTarget = home_x + xOffset
  local zTarget = home_z + zOffset
  goTo(xTarget, yTarget, zTarget)
end

function mineTunnel(xOffset, zOffset, yLevel, forward)
  local absX = home_x + xOffset
  local absZ = home_z + zOffset
  print("=== Mining tunnel at (" .. absX .. ", " .. absZ .. ", Y=" .. yLevel .. ") ===")
  if hasMined(absX, yLevel, absZ) then
    print("Already mined. Skipping...")
    return
  end

  print("Navigating to tunnel start...")
  goFromHome(absX, yLevel, absZ)

  -- Tunnel direction based on X to alternate rows
  if forward then face(0) else face(2) end

  for i = 1, tunnel_length do
    digSafe()
    forward()
    digVeins(5)
    print("Progress: " .. i .. "/" .. tunnel_length)

    if isInventoryFull() then
      print("[Inventory full] Returning to drop off...")
      saveMined(absX, yLevel, absZ)
      returnHome()
      dropOff()
      refuelIfNeeded()
      return
    end
    refuelIfNeeded()
  end

  saveMined(absX, yLevel, absZ)
  
end

function mineGridLayer(y)
  print("Mining Y Level: " .. y)
  for row = 0, math.floor((radius * 2) / spacing) do
    local xOffset = -radius + row * spacing
    local forward = (row % 2 == 0)

    local zOffset = forward and -radius or radius

    mineTunnel(xOffset, zOffset, y, forward)
  end
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
face(facing)

loadMinedDB()
refuelIfNeeded()

for y = max_y, min_y, -3 do
  mineGridLayer(y)
end

print("Mining complete.")
returnHome()
dropOff()
