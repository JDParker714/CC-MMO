-- buy_shop.lua

local modem = peripheral.find("modem", rednet.open)

local disk_drive = peripheral.find("drive")
local stock_chest = peripheral.wrap("right")    -- shop's stock (items for sale)
local player_chest = peripheral.wrap("left")    -- where purchased items go

if not disk_drive or not stock_chest or not player_chest then
    print("Missing peripherals.")
    return
end

local function fetchPriceTable()
    local req = { type = "get_price_table" }
    rednet.broadcast(textutils.serialize(req))
    local _, raw = rednet.receive(3)
    if not raw then
        print("Failed to fetch price table from server.")
        return {}
    end
    local resp = textutils.unserialize(raw)
    if resp.status == "ok" and resp.prices then
        return resp.prices
    end
    print("Invalid response from server.")
    return {}
end

local function readPlayerId()
    if not fs.exists("disk/.player_id") then
        return nil
    end
    local f = fs.open("disk/.player_id", "r")
    local id = f.readAll()
    f.close()
    return id
end

local function lookupPlayer(id)
    local req = { type = "lookup_player", id = id }
    rednet.broadcast(textutils.serialize(req))
    local _, raw = rednet.receive(3)
    if raw then
        local resp = textutils.unserialize(raw)
        if resp.status == "found" then
            return resp.data
        end
    end
    return nil
end

local function updateBalance(id, amount)
    local req = { type = "add_balance", id = id, amount = amount }
    rednet.broadcast(textutils.serialize(req))
end

local function waitForPlayerDisk()
    while true do
        if fs.exists("disk/.player_id") then
            return true
        end
        sleep(1)
    end
end

local function waitForOwnerCard()
    print("=== Shop Owner Setup ===")
    print("Insert your player card (owner)...")
    while not fs.exists("disk/.player_id") do sleep(0.5) end

    local id = readPlayerId()
    local owner = lookupPlayer(id)

    if not owner then
        print("Invalid card. Ejecting.")
        disk_drive.ejectDisk()
        sleep(2)
        return nil, nil
    end

    write("Enter password: ")
    local pass = read("*")
    if pass ~= owner.password then
        print("Incorrect password.")
        disk_drive.ejectDisk()
        sleep(2)
        return nil, nil
    end

    print("Welcome, " .. owner.name .. "!")

    write("Enter markup percentage (e.g. 20 for +20%): ")
    local markup_str = read()
    local markup_percent = tonumber(markup_str)

    if not markup_percent or markup_percent < 0 then
        print("Invalid markup. Defaulting to 0%.")
        markup_percent = 0
    end

    local markup = 1 + (markup_percent / 100)
    disk_drive.ejectDisk()
    sleep(1)
    return id, markup
end

local owner_id, markup = waitForOwnerCard()
if not owner_id then return end

while true do
    print("\n=== Buy Shop Terminal ===")
    print("Insert your player card to begin...")

    waitForPlayerDisk()
    local id = readPlayerId()
    local player = lookupPlayer(id)

    if not player then
        print("Invalid card. Ejecting.")
        disk_drive.ejectDisk()
        sleep(2)
        goto continue
    end

    print("Welcome, " .. player.name)
    write("Enter password: ")
    local pass = read("*")
    if pass ~= player.password then
        print("Incorrect password.")
        disk_drive.ejectDisk()
        sleep(2)
        goto continue
    end

    local price_table = fetchPriceTable()
    if not next(price_table) then
        print("Unable to fetch pricing from server.")
        print("Please try again later.")
        disk_drive.ejectDisk()
        sleep(3)
        goto continue
    end

    print("Authenticated. Your current balance: G" .. player.balance)
    print("Place items you want to purchase in the stock chest.")

    local has_notified = false
    local last_action_time = os.clock()

    while true do
        local items = stock_chest.list()
        local purchase_total = 0
        local purchase_slots = {}

        for slot, item in pairs(items) do
            local price = price_table[item.name]
            if price then
                local cost = price * item.count
                if (player.balance - purchase_total) >= cost then
                    table.insert(purchase_slots, { slot = slot, cost = cost, name = item.name, count = item.count })
                    purchase_total = purchase_total + cost
                else
                    print("Not enough funds to buy " .. item.count .. "x " .. item.name)
                    print("Hah, fucking brokie.")
                    goto logout
                end
            end
        end

        if purchase_total > 0 then
            updateBalance(player.id, -purchase_total)         -- deduct from buyer
            updateBalance(owner_id, purchase_total)           -- give to shop owner_id
            player.balance = player.balance - purchase_total
            -- Move items
            for _, p in ipairs(purchase_slots) do
                stock_chest.pushItems(peripheral.getName(player_chest), p.slot)
                print("Purchased " .. p.count .. "x " .. p.name .. " for G" .. p.cost)
                sleep(0.5)
            end
            print("Total spent: G" .. purchase_total)
            print("New balance: G" .. player.balance)
            has_notified = false
            last_action_time = os.clock()
        end

        if not has_notified then
            print("Press ENTER to log out, or buy more items...")
            has_notified = true
        end

        local timer = os.startTimer(2)
        while true do
            local event, param = os.pullEventRaw()
            if event == "key" and param == keys.enter then
                print("Logging out...")
                goto logout
            elseif event == "timer" and os.clock() - last_action_time > 60 then
                print("No activity. Logging out...")
                goto logout
            elseif event == "timer" then
                break
            end
        end
    end

    ::logout::
    disk_drive.ejectDisk()
    sleep(1)

    ::continue::
end