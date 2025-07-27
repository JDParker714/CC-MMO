local speaker = peripheral.find("speaker")
if not speaker then
    print("No speaker found! Make sure it's next to the computer.")
    return
end

local dfpwm = require("cc.audio.dfpwm")
local decoder = dfpwm.make_decoder()

local filename = "Island_In_The_Sun.dfpwm"
if not fs.exists(filename) then
    print("File not found: " .. filename)
    return
end

local file = fs.open(filename, "rb")
while true do
    local chunk = file.read(16 * 1024)
    if not chunk then break end

    local decoded = decoder(chunk)
    while not speaker.playAudio(decoded) do
        os.pullEvent("speaker_audio_empty")
    end
end
file.close()

print("Playback complete.")