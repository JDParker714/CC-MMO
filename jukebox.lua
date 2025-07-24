local speaker = peripheral.find("speaker")

local function playSound(name, volume)
	if speaker then
		local success = speaker.playSound(name, volume or 1)
        print(name)
        print(success)
    else
        print("No Speaker Found")
	end
end

--play background music
while true do
    if speaker then
        speaker.playSound("biomeswevegone:music_disc.pixie_club", 1)
    end
    sleep(175) -- approx length of the song in seconds, adjust if needed
end