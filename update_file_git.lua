local files = {
    { name = "master_server.lua", url = "https://raw.githubusercontent.com/JDParker714/CC-MMO/refs/heads/main/master_server.lua" },
    { name = "player_card_kiosk.lua", url = "https://raw.githubusercontent.com/JDParker714/CC-MMO/refs/heads/main/player_card_kiosk.lua" },
    { name = "sell_shop.lua", url = "https://raw.githubusercontent.com/JDParker714/CC-MMO/refs/heads/main/sell_shop.lua" }
}

for _, file in ipairs(files) do
    if fs.exists(file.name) then
        print("Deleting old " .. file.name)
        fs.delete(file.name)
    end

    print("Downloading " .. file.name .. "...")
    shell.run("wget", file.url, file.name)
end

print("Update complete.")