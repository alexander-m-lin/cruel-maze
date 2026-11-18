# Roblox sandbox

A learning sandbox in Roblox Studio. The place file is `Place2.rbxl`.

## The game

A maze game: a random maze every round, a fixed isometric camera, and fog of war with line of sight (a vision cone, a soft edge, and forgiveness for small unseen pockets). The first player to reach the green beacon wins the round. A monster roams the maze and chases players it sees or hears, and a red sonar ping shows its position every 3 seconds when it's nearby but out of view.

## Layout

- `Place2.rbxl`: the actual place. Open this in Studio. It's a binary file, so git can store versions of it but can't show what changed. Commit it whenever you change parts, GUIs, lighting and so on.
- Script files, kept in step with Studio automatically by **Script Sync**. Editing them in either place updates the other:

| File | Where it lives in Studio | What it does |
|---|---|---|
| `ServerScriptService/MazeGame.legacy.luau` | ServerScriptService | Runs rounds, times runs, wins/best stats |
| `ServerStorage/MazeBuilder.luau` | ServerStorage (ModuleScript) | Generates and builds the maze |
| `StarterGui/MazeHUD/HUD.local.luau` | StarterGui › MazeHUD | Run timer and announcements |
| `StarterPlayerScripts/IsometricCamera.local.luau` | StarterPlayer › StarterPlayerScripts | Fixed isometric camera |
| `StarterPlayerScripts/FogOfWar.local.luau` | StarterPlayer › StarterPlayerScripts | Fog of war and line of sight; hides anything tagged `HiddenByFog` unless it's in view |
| `ServerScriptService/Monster.legacy.luau` | ServerScriptService | The monster: roams, chases, catches |
| `StarterPlayerScripts/MonsterPing.local.luau` | StarterPlayer › StarterPlayerScripts | Sonar ping showing a nearby monster you can't see |

Script Sync names files by script type: `.legacy.luau` = Script, `.local.luau` = LocalScript, `.luau` = ModuleScript.

## History

- An earlier dodge-ball game was deleted. It's in the first commit (`11d51a5`): its scripts are under `src/ServerStorage/DodgeGameArchive/`, and the place file in that commit still contains it.
