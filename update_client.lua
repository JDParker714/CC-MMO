-- client
shell.run("delete","mmo_player_client.lua")
shell.run(
  "wget",
  "https://raw.githubusercontent.com/JDParker714/CC-MMO/refs/heads/main/mmo_player_client.lua"
)

shell.run("mmo_player_client.lua")