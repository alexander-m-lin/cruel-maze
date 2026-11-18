# Roblox sandbox

A learning sandbox in Roblox Studio. The place file is `Place2.rbxl`.

## What's in it

- **Maze game (active):** a random maze every round, a fixed isometric camera, and fog of war with line of sight (a vision cone, a soft edge, and forgiveness for small unseen pockets). The first player to reach the green beacon wins the round.
- **Dodge game (archived):** in `ServerStorage/DodgeGameArchive`, where it doesn't run. To play it again, move its items back to Workspace, ServerScriptService and StarterGui.

## Layout

- `Place2.rbxl`: the actual place. Open this in Studio. It's a binary file, so git can store versions of it but can't show what changed.
- `src/`: plain-text copies of every script, so git history shows code changes line by line. Folders match where each script lives in Studio.
  - `.server.luau` = Script, `.client.luau` = LocalScript, `.module.luau` = ModuleScript
- `ServerScriptService/MazeGame.legacy.luau`: a copy of the MazeGame script that was already here, likely written by Studio's script sync. It currently matches `src/`, but nothing keeps it updated.

The Studio place is the source of truth. The files in `src/` are exported snapshots, so editing them doesn't change the game.
