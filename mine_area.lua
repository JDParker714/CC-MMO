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

-- Mine one horizontal layer (X by Y)
function mineLayer(x, y)
    local right = true
    for row = 1, y do
        mineLine(x)
        if row < y then
            nextRow(right)
            right = not right
        end
    end
end

-- Mine multiple layers down
function mineCube(x, y, z)
    local facingRight = true

    for depth = 1, z do
        mineLayer(x, y)

        -- Return to starting X/Y position of layer
        if (y % 2 == 1) then
            -- We're at end of last row, facing same direction
            turtle.turnLeft()
            turtle.turnLeft()
            for i = 1, x - 1 do turtle.forward() end
        end

        if (y > 1) then
            -- Move back through rows
            for i = 1, y - 1 do
                turtle.forward()
            end
        end

        -- Face original direction
        turtle.turnLeft()
        turtle.turnLeft()

        -- Go down
        if depth < z then
            if turtle.detectDown() then turtle.digDown() end
            turtle.down()
        end
    end

    -- Return to surface
    for up = 1, z - 1 do
        turtle.up()
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
    print("Usage: mine_rectangle <x> <y> <z>")
    return
end

local x = tonumber(tArgs[1])
local y = tonumber(tArgs[2])
local z = tonumber(tArgs[3]) or 1

if not x or not y or x < 1 or y < 1 or z < 1 then
    print("Invalid dimensions.")
    return
end

local estimatedFuel = x * y * z + y * z + z  -- conservative estimate
if not ensureFuel(estimatedFuel) then return end

mineCube(x, y, z)
print("Mining complete.")