-- === CONFIG ===
local sleep_seconds = 60
local coal_names = {
  ["minecraft:coal"] = true,
  ["minecraft:charcoal"] = true
}

-- === FUNCTIONS ===
-- Check if an item is coal (or charcoal)
local function is_coal(item)
  return item and coal_names[item.name] or false
end

local function suck_non_coal()
  local chest = peripheral.wrap("front")
  if not chest then
    print("No chest in front!")
    return
  end

  local items = chest.list()
  for slot, item in pairs(items) do
    if not is_coal(item) then
      -- Select next empty slot in turtle
      local inserted = false
      for i = 1, 16 do
        if turtle.getItemCount(i) == 0 then
          turtle.select(i)
          chest.pushItems(peripheral.getName(turtle), slot, item.count)
          inserted = true
          break
        end
      end
      if not inserted then
        print("Turtle inventory full!")
        break
      end
    end
  end
end

-- Deposit only non-coal items behind
local function deposit_non_coal()
  turtle.turnLeft()
  turtle.turnLeft()
  for i = 1, 16 do
    turtle.select(i)
    local item = turtle.getItemDetail()
    if item and not is_coal(item) then
      turtle.drop()
    end
  end
  turtle.turnLeft()
  turtle.turnLeft()
end

-- === MAIN LOOP ===
while true do
  suck_non_coal()
  deposit_non_coal()
  sleep(sleep_seconds)
end
