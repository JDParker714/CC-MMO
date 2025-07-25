-- === CONFIG ===
local sleep_seconds = 60
local coal_names = {
  ["minecraft:coal"] = true,
  ["minecraft:charcoal"] = true
}

-- === HELPERS ===
local function is_coal(item)
  return item and coal_names[item.name] or false
end

-- === MAIN LOOP ===
while true do
  -- Step 1: Grab all non-coal items from the chest in front
  for slot = 1, 16 do
    turtle.select(slot)
    turtle.suck()
    local item = turtle.getItemDetail()
    if is_coal(item) then
      -- Put coal back into chest if accidentally sucked
      turtle.drop()
    end
  end

  -- Step 2: Turn around and deposit non-coal items
  turtle.turnLeft()
  turtle.turnLeft()
  for slot = 1, 16 do
    turtle.select(slot)
    local item = turtle.getItemDetail()
    if item and not is_coal(item) then
      turtle.drop()
    end
  end

  -- Step 3: Face forward again and wait
  turtle.turnLeft()
  turtle.turnLeft()
  sleep(sleep_seconds)
end