# Roblox sandbox

A learning sandbox in Roblox Studio. The place file is `Place2.rbxl`.

## The game

The start of **Cruel Maze** (design in `CLAUDE.md`, plan in `docs/roadmap.md`). Right now it's a maze game: a short countdown, then a random maze every round, a fixed isometric camera, and fog of war with line of sight (a vision cone, a soft edge, and forgiveness for small unseen pockets). The first player to reach the green beacon wins the round. A monster roams the maze and chases players it sees or hears, and a red sonar ping shows its position every 3 seconds when it's nearby but out of view.

## Layout

- `Place2.rbxl`: the actual place. Open this in Studio. It's a binary file, so git can store versions of it but can't show what changed. Commit it whenever you change parts, GUIs, lighting and so on.
- Script files, kept in step with Studio automatically by **Script Sync**. Editing them in either place updates the other:

| File | Where it lives in Studio | What it does |
|---|---|---|
| `ServerScriptService/Main.legacy.luau` | ServerScriptService | Starts the game (runs `Match`) |
| `ServerStorage/Match.luau` | ServerStorage (ModuleScript) | Runs matches one after another: Waiting → Countdown → Playing → Results. Roles, wins/best stats |
| `ServerStorage/MazeBuilder.luau` | ServerStorage (ModuleScript) | Generates and builds each maze |
| `ServerStorage/MonsterAI.luau` | ServerStorage (ModuleScript) | An AI monster: roams, chases, catches. A match creates as many as it needs |
| `ReplicatedStorage/Config.luau` | ReplicatedStorage (ModuleScript) | Settings shared by the server and players' computers (speeds, camera angle, match timings, states, roles) |
| `ReplicatedStorage/Net.luau` | ReplicatedStorage (ModuleScript) | Creates/finds the remote events used to message between server and players |
| `StarterGui/MazeHUD/HUD.local.luau` | StarterGui › MazeHUD | Countdown, run timer and announcements |
| `StarterPlayerScripts/Controls.local.luau` | StarterPlayer › StarterPlayerScripts | Character faces the mouse (WASD is already screen-relative) |
| `StarterPlayerScripts/IsometricCamera.local.luau` | StarterPlayer › StarterPlayerScripts | Fixed isometric camera |
| `StarterPlayerScripts/FogOfWar.local.luau` | StarterPlayer › StarterPlayerScripts | Fog of war and line of sight; hides anything tagged `HiddenByFog` unless it's in view |
| `StarterPlayerScripts/MonsterPing.local.luau` | StarterPlayer › StarterPlayerScripts | Sonar ping showing a nearby monster you can't see |
| `StarterPlayerScripts/MonsterAnimate.local.luau` | StarterPlayer › StarterPlayerScripts | Moves monsters smoothly and animates their limbs in code (a limping walk cycle synced to speed) |

The monster's body is the rigged model `ServerStorage.MonsterRig` (AI-generated, auto-rigged as R15). It lives in the place file, not in a script. If it's missing, the monster falls back to a floating orb.

Script Sync names files by script type: `.legacy.luau` = Script, `.local.luau` = LocalScript, `.luau` = ModuleScript.

## History

- An earlier dodge-ball game was deleted. It's in the first commit (`11d51a5`): its scripts are under `src/ServerStorage/DodgeGameArchive/`, and the place file in that commit still contains it.
