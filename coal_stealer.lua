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
  local chest = peripheral.wrap("front")
  if not chest then
    print("No chest in front!")
    sleep(sleep_seconds)
  else
    local items = chest.list()
    for chest_slot, item in pairs(items) do
      if not is_coal(item) then
        -- Find a free turtle slot
        for turtle_slot = 1, 16 do
          if turtle.getItemCount(turtle_slot) == 0 then
            turtle.select(turtle_slot)
            chest.pullItems("front", chest_slot, item.count)
            break
          end
        end
      end
    end
  end

  -- Turn and drop non-coal items
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

  sleep(sleep_seconds)
end