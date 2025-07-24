local modem = peripheral.find("modem", rednet.open)
local drive = peripheral.find("drive")
local speaker = peripheral.find("speaker")

if not drive then
	print("No disk drive found!")
	return
end

local function playSound(name, volume)
	if speaker then
		speaker.playSound(name, volume or 1)
	end
end

-- Get ID from disk
local function getPlayerId()
	local mount = drive.getMountPath()
	if not mount then return nil end
	local path = mount .. "/.player_id"
	if not fs.exists(path) then return nil end
	local f = fs.open(path, "r")
	local id = f.readAll()
	f.close()
	return id
end

-- Look up player data from server
local function lookupPlayer(id)
	local req = { type = "lookup_player", id = id }
	rednet.broadcast(textutils.serialize(req))
	local _, raw = rednet.receive(3)
	if not raw then return nil end
	local resp = textutils.unserialize(raw)
	if resp and resp.status == "found" then
		return resp.data
	end
	return nil
end

-- Send balance update to server (now with confirmation)
local function updateBalance(id, amount)
	local req = { type = "add_balance", id = id, amount = amount }
	rednet.broadcast(textutils.serialize(req))
	local _, raw = rednet.receive(3)
	if not raw then return false end
	local resp = textutils.unserialize(raw)
	return resp and resp.status == "balance_updated"
end

-- Check admin password via server
local function verifyAdmin()
	write("Enter admin password: ")
	local pw = read("*")
	local req = { type = "verify_admin", password = pw }
	rednet.broadcast(textutils.serialize(req))
	local _, raw = rednet.receive(3)
	if not raw then return false end
	local resp = textutils.unserialize(raw)
	return resp.status == "authorized"
end

--play background music
local function playMusicLoop()
	while true do
		if speaker then
			speaker.playSound("biomeswevegone:music_disc.pixie_club", 1)
		end
		sleep(175) -- approx length of the song in seconds, adjust if needed
	end
end

-- Main loop
local function runKiosk()
    while true do
        term.clear()
        term.setCursorPos(1, 1)
        print("=== Admin Purchase Terminal ===")
        print("Please insert a player card...")

        -- Wait for disk
        while not drive.isDiskPresent() do sleep(0.5) end

        -- Validate card
        local id = getPlayerId()
        if not id then
            print("Invalid card. Ejecting.")
            playSound("block.note_block.bass")
            drive.ejectDisk()
            sleep(2)
            goto continue
        end

        local player = lookupPlayer(id)
        if not player then
            print("Could not find player.")
            playSound("block.note_block.pling")
            drive.ejectDisk()
            sleep(2)
            goto continue
        end

        while true do
            term.clear()
            term.setCursorPos(1, 1)
            print("=== Admin Purchase Menu ===")
            print("Player: " .. player.name)
            print("Balance: G" .. player.balance)
            print("")
            print("[1] Purchase Item")
            print("[2] Eject Card")
            write("> ")
            local choice = read()

            if choice == "2" then
                print("Ejecting card...")
                playSound("block.note_block.bass")
                drive.ejectDisk()
                sleep(1)
                goto continue
            elseif choice ~= "1" then
                print("Invalid choice.")
                playSound("block.note_block.pling")
                sleep(1)
            else
                if not verifyAdmin() then
                    print("Incorrect admin password.")
                    playSound("block.note_block.pling")
                    sleep(2)
                else
                    write("Enter purchase amount to subtract: G")
                    local amt_str = read()
                    local amt = tonumber(amt_str)

                    if not amt or amt <= 0 or amt ~= math.floor(amt) then
                        print("Invalid amount.")
                        playSound("block.note_block.pling")
                        sleep(2)
                    elseif amt > player.balance then
                        print("Insufficient funds.")
                        playSound("block.note_block.pling")
                        sleep(2)
                    else
                        if updateBalance(id, -amt) then
                            print("Purchase complete! G" .. amt .. " removed.")
                            player.balance = player.balance - amt
                            print("New balance: G" .. player.balance)
                            playSound("entity.experience_orb.pickup")
                        else
                            print("Error: Could not contact server.")
                            playSound("block.note_block.pling")
                        end
                        sleep(5)
                    end
                end
            end
        end

        ::continue::
    end
end

parallel.waitForAny(playMusicLoop, runKiosk)