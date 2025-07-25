-- === CONFIG ===
local sleep_seconds = 60
local coal_names = {
  ["minecraft:coal"] = true,
  ["minecraft:charcoal"] = true
}

-- === FUNCTIONS ===
-- Check if an item is coal (or charcoal)
local function isCoal(item)
  return item and coal_names[item.name] or false
end

-- Grab all items from the chest in front
local function suckAll()
  for i = 1, 16 do
    turtle.select(i)
    turtle.suck()
  end
end

-- Deposit all non-coal items behind
local function depositNonCoal()
  turtle.turnLeft()
  turtle.turnLeft()
  for i = 1, 16 do
    turtle.select(i)
    local item = turtle.getItemDetail()
    if item and not isCoal(item) then
      turtle.drop()
    end
  end
  turtle.turnLeft()
  turtle.turnLeft()
end

-- === MAIN LOOP ===
while true do
  suckAll()
  depositNonCoal()
  sleep(sleep_seconds)
end
