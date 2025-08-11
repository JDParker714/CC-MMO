-- map editor
shell.run("delete","mmo_map_editor.lua")
shell.run(
  "wget",
  "https://raw.githubusercontent.com/JDParker714/CC-MMO/refs/heads/main/mmo_map_editor.lua"
)

-- entities
shell.run("delete","mmo_entities.lua")
shell.run(
  "wget",
  "https://raw.githubusercontent.com/JDParker714/CC-MMO/refs/heads/main/mmo_entities.lua"
)

-- world atlas
shell.run("delete","mmo_world_atlas.lua")
shell.run(
  "wget",
  "https://raw.githubusercontent.com/JDParker714/CC-MMO/refs/heads/main/mmo_world_atlas.lua"
)

-- world server
shell.run("delete","mmo_world_server.lua")
shell.run(
  "wget",
  "https://raw.githubusercontent.com/JDParker714/CC-MMO/refs/heads/main/mmo_world_server.lua"
)