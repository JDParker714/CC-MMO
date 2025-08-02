-- Usage: place in turtle and run with: mine_rectangle <x> <y>

-- Function to dig and move forward
function digForward()
    while turtle.detect() do
        turtle.dig()
        sleep(0.3)
    end
    turtle.forward()
end

-- Function to mine a full line of x blocks
function mineLine(length)
    for i = 1, length - 1 do
        digForward()
    end
end

-- Turn right or left based on direction
function turn(isRight)
    if isRight then turtle.turnRight()
    else turtle.turnLeft()
    end
end

-- Move to next row and prepare direction
function nextRow(isRight)
    turn(isRight)
    digForward()
    turn(isRight)
end

-- Main mining logic
function mineArea(x, y)
    local right = true
    for row = 1, y do
        mineLine(x)
        if row < y then
            nextRow(right)
            right = not right
        end
    end
end

-- Refuel check
function ensureFuel(minFuel)
    local fuel = turtle.getFuelLevel()
    if fuel == "unlimited" or fuel >= minFuel then return true end

    print("Refueling...")
    for i = 1, 16 do
        turtle.select(i)
        if turtle.refuel(0) then
            turtle.refuel()
            if turtle.getFuelLevel() >= minFuel then return true end
        end
    end
    print("Not enough fuel.")
    return false
end

-- Parse args
local tArgs = {...}
if #tArgs < 2 then
    print("Usage: mine_rectangle <x> <y>")
    return
end

local x = tonumber(tArgs[1])
local y = tonumber(tArgs[2])

if not x or not y then
    print("Invalid dimensions.")
    return
end

-- Estimate fuel needed
local estimatedFuel = x * y + y  -- some buffer for turning
if not ensureFuel(estimatedFuel) then return end

mineArea(x, y)
print("Mining complete.")