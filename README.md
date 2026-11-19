# Cruel Maze

An early prototype of **Cruel Maze**, an asymmetric maze game for Roblox: survivors explore a
fog-covered maze hunting relics while a monster hunts them. The full design is in `CLAUDE.md`,
and the plan in `docs/roadmap.md`.

## Play it

1. Install [Roblox Studio](https://create.roblox.com/) and sign in (a free Roblox account is needed).
2. Open `CruelMaze.rbxl` from this repo in Studio.
3. Press **Play** (F5). A match starts after a 3-second countdown.

Playing from the file is single player. Playing together needs the place published to Roblox
(or Studio's Team Create).

**Controls (PC):** WASD to move. Your character faces the mouse, and you see in a cone that way.
Moving away from where you face is slower. After being caught, click a spawn room on the map to
choose where you come back. M hides the minimap.

**How a match goes:**
- Find and collect **6 of the 9 relics** within **4 minutes**. Standing on a relic shows a prompt (a mouse with its left button lit):
  **left-click** to start collecting, then stay on it for 3 seconds (leaving or getting caught
  resets it; the monster turning up doesn't). Once anyone on your team has seen a relic,
  the area around it stays visible to your team until it's collected.
- An AI **monster** roams the maze, and chases you when it sees or hears you. If it catches you,
  you lose one of your **3 lives**.
- **Spawn rooms** (cyan barriers) are safe: the monster can't enter. Walk into one to capture it
  for your team, and you can come back there after being caught.
- The monster wins if time runs out or every survivor is out of lives.

## Layout

- `CruelMaze.rbxl`: the actual place. Open this in Studio. It's a binary file, so git can store
  versions of it but can't show what changed. Commit it whenever you change parts, GUIs,
  lighting and so on.
- Script files, kept in step with Studio automatically by **Script Sync**. Editing them in
  either place updates the other:

| File | Where it lives in Studio | What it does |
|---|---|---|
| `ServerScriptService/Main.legacy.luau` | ServerScriptService | Starts the game (runs `Match`) |
| `ServerStorage/Match.luau` | ServerStorage (ModuleScript) | Runs matches one after another: Waiting → Countdown → Playing → Results. Lives, being caught, respawning, the end of a match |
| `ServerStorage/MazeBuilder.luau` | ServerStorage (ModuleScript) | Generates and builds each maze: walls, floors, spawn rooms, relics. Wall and floor looks |
| `ServerStorage/MazeLayout.luau` | ServerStorage (ModuleScript) | Layout rules: carving spawn rooms, picking relic spots, keeping the maze connected |
| `ServerStorage/Objectives.luau` | ServerStorage (ModuleScript) | Relics (spotting, collecting) and spawn rooms (capturing, monster barriers) |
| `ServerStorage/MonsterAI.luau` | ServerStorage (ModuleScript) | An AI monster: roams, chases, catches |
| `ReplicatedStorage/Config.luau` | ReplicatedStorage (ModuleScript) | Settings shared by the server and players' computers: speeds, vision, match length, relics, lives, spawn rooms |
| `ReplicatedStorage/Sounds.luau` | ReplicatedStorage (ModuleScript) | Every sound effect and the music, with volumes |
| `ReplicatedStorage/Net.luau` | ReplicatedStorage (ModuleScript) | Creates/finds the remote events used to message between server and players |
| `StarterGui/MazeHUD/HUD.local.luau` | StarterGui › MazeHUD | Timer, relics and lives, announcements, relic progress bars |
| `StarterPlayerScripts/Controls.local.luau` | StarterPlayer › StarterPlayerScripts | Facing the mouse, speed by direction, backwards running, facing a relic while collecting it |
| `StarterPlayerScripts/IsometricCamera.local.luau` | StarterPlayer › StarterPlayerScripts | Fixed isometric camera; watches a teammate when you have no character |
| `StarterPlayerScripts/FogOfWar.local.luau` | StarterPlayer › StarterPlayerScripts | Fog of war and line of sight, shared with teammates, plus the vision around spotted relics |
| `StarterPlayerScripts/FogState.luau` | StarterPlayer › StarterPlayerScripts (ModuleScript) | What the fog knows (seen, in view), shared with the minimap |
| `StarterPlayerScripts/Minimap.local.luau` | StarterPlayer › StarterPlayerScripts | Corner map: explored and in-view areas, and dots for you, teammates, spotted relics and a visible monster (M hides it) |
| `StarterPlayerScripts/SpawnPicker.local.luau` | StarterPlayer › StarterPlayerScripts | The map for choosing a spawn room after being caught |
| `StarterPlayerScripts/RelicEffects.local.luau` | StarterPlayer › StarterPlayerScripts | Reaching for a relic with a beam of light while collecting it |
| `StarterPlayerScripts/MonsterAnimate.local.luau` | StarterPlayer › StarterPlayerScripts | Moves monsters smoothly and animates them in code: the walk, the chase, the kill |
| `StarterPlayerScripts/MonsterPing.local.luau` | StarterPlayer › StarterPlayerScripts | Sonar ping showing a nearby monster you can't see |
| `StarterPlayerScripts/SoundEffects.local.luau` | StarterPlayer › StarterPlayerScripts | Plays the sound effects and music |

Script Sync names files by script type: `.legacy.luau` = Script, `.local.luau` = LocalScript,
`.luau` = ModuleScript.

Also in the place file (not scripts): the monster's rigged body (`ServerStorage.MonsterRig`), the relic
skull (`ServerStorage.SkullRelic`, Creator Store asset 98498294 by RoyalBoyMc), the
wall and floor materials (`MaterialService`), and a few developer previews (`Workspace.WallPalette`,
`Workspace.FloorPalette`, `SoundService.SoundBoard`).

Other folders:
- `assets/textures/`: the wall and floor texture images and how they were made.
- `tools/textures/`: Python scripts that made them (tileable variations, toning a texture down).
- `docs/roadmap.md`: the implementation plan.

## History

- An earlier dodge-ball game was deleted. It's in the first commit (`11d51a5`): its scripts are
  under `src/ServerStorage/DodgeGameArchive/`, and the place file in that commit still contains it.
