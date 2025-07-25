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

    for slot, item in pairs(items) do
      if not is_coal(item) then
        -- Find free slot in turtle
        for i = 1, 16 do
          if turtle.getItemCount(i) == 0 then
            turtle.select(i)
            chest.pushItems("back", slot, item.count)
            break
          end
        end
      end
    end
  end

  -- Turn around and drop non-coal items
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