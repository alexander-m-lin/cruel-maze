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

**Lobby and roles:** between matches everyone waits in the lobby, which lists who's in. Pick a
preferred role there (Any, Survivor, Monster or Maze Master; you get it if the slot is free) and
anyone presses Start. Roles: 3 survivors, 2 monsters and a Maze Master; empty slots get bots
(survivor bots named "Bot 1"..., AI monsters, and an AI Maze Master that uses the same tools as a
person: it shuts doors ahead of chased survivors, sets off crushing walls as they walk in, keeps
wards out and haunts whoever the monster side can see).
Developers (anyone in Studio, and the experience's owner in the published game) also get buttons
at the bottom left: "Role" forces their role for the next match, "New match" ends this one and
starts another straight away, and "Doors" opens the doors panel.
- **Monster:** move as usual; left-click to lunge. A survivor you hit is caught. You see what your
  team sees (other monsters and the Maze Master); survivors are hidden unless you see them.
- **Maze Master:** no body; pan the camera with WASD, zoom with the mouse wheel. False relics glow
  red for you and the monsters. You see what the monsters see, all round every relic, and each
  crushing wall's stretch of corridor. Spend dark mana on doors (1), wards (2: a floating eye
  your side sees all round; up to 3 at a time), haunt (3: click a survivor you can see; for 3
  seconds your side sees them, and what they see), false relics (4, two a match: they look like
  relics, and a survivor who clicks one is revealed and slowed) and crushing walls (5: hidden in
  the maze, they slam together and crush survivors between them).

**Heroes:** every survivor plays **Sara, the Cryptraider** for now (more heroes and a character
select are coming). Abilities aim the way you face:
- **Right mouse: Whip** (5 s). Lashes out 39 studs, catching monsters within 5 studs of it and
  teammates within 4. A wall or relic pulls you to it; a teammate is
  pulled to you; a monster is pulled to you and stunned for 1 second.
- **Q: Treasure hunt** (15 s). The nearest relic your team hasn't spotted (real or false) within
  110 studs is spotted, with a pillar of light over it.
- **E: Flourish** (60 s). Spin the whip overhead for 1 second, standing still (a ring on the
  floor shows its reach); half a second in, every monster within 20 studs is stunned for 3.5
  seconds. Caught before then: no stun.
A stunned monster can't move, lunge or catch (stars circle its head). Crushing walls stun
monsters caught between them too. A monster in the middle of a kill can't be stunned or pulled.

**How a match goes (as a survivor):**
- Find and collect **6 of the 9 relics** within **4 minutes**. Standing on a relic shows a prompt (a mouse with its left button lit):
  **left-click** to start collecting, then stay on it for 3 seconds (leaving or getting caught
  resets it; the monster turning up doesn't). Once anyone on your team has seen a relic,
  the area around it stays visible to your team until it's collected.
- An AI **monster** roams the maze, and chases you when it sees or hears you. If it catches you,
  you lose one of your **3 lives**.
- **Wards** (floating purple eyes) let the monster side see around them. Once your team spots
  one it stays shown; stand next to one and left-click, then stay close for 3 seconds (a bar
  fills), to destroy it (the monster side sees where). Anything that reveals you (a false relic,
  a haunt) also lights up a small ring round you for the monster side. AI monsters come for you,
  even through walls, whenever you're within 120 studs and the monster side can see you
  in any way: another monster, a ward, a crushing wall, a relic's ring, a reveal. The monster
  side has vision rings round relics too: the Maze Master round every relic, monsters round
  false relics and the real ones they've spotted. A purple glow round your screen and a whisper mean
  the Maze Master has **haunted** you: for a few seconds they see you, and what you see.
- **Spawn rooms** (cyan barriers) are safe: the monster can't enter. Walk into one to capture it
  for your team, and you can come back there after being caught. Your team's rooms (the start
  room, and any you capture) are on your map whole.
- **Doors** (wall panels between two darker posts) open and close during the match. A door shakes,
  rumbles and kicks up dust for 2 seconds before it moves. Your map shows each door as you last saw it. With
  every door shut, everything is still reachable: doors only send you the long way round.
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
| `ServerStorage/MazeLayout.luau` | ServerStorage (ModuleScript) | Layout rules: carving spawn rooms, picking relic spots and door slots, keeping the maze connected (even with every door shut) |
| `ServerStorage/Doors.luau` | ServerStorage (ModuleScript) | Opening and closing doors mid-match (warning, movement, nudging people out of the way), the door AI, and the Studio dev panel's requests |
| `ServerStorage/Objectives.luau` | ServerStorage (ModuleScript) | Relics (spotting, collecting) and spawn rooms (capturing, monster barriers) |
| `ServerStorage/MonsterAI.luau` | ServerStorage (ModuleScript) | An AI monster: roams, chases, catches. Also builds the monster body |
| `ServerStorage/PlayerMonster.luau` | ServerStorage (ModuleScript) | A monster played by a person: dresses their invisible character in the monster body; the lunge and its catches |
| `ServerStorage/MazeMaster.luau` | ServerStorage (ModuleScript) | The Maze Master's tools: dark mana, cooldowns, doors, wards, haunt, false relics, crushing walls |
| `ServerStorage/SurvivorBot.luau` | ServerStorage (ModuleScript) | A survivor bot for empty survivor slots: roams, collects relics it sees, runs to a spawn room from monsters. Passes for a player to the rest of the game |
| `ServerStorage/BotAnimate.legacy.luau` | ServerStorage (Script, a template) | Roblox's standard character Animate script, as a server copy that bots get, so they animate exactly like players |
| `ServerStorage/SpeedCheck.luau` | ServerStorage (ModuleScript) | Server-side speed check: pulls back characters moving faster than allowed |
| `ServerStorage/MazeMasterAI.luau` | ServerStorage (ModuleScript) | The AI Maze Master: uses the Maze Master's tools, knowing only what the monster side sees |
| `ReplicatedStorage/Heroes.luau` | ReplicatedStorage (ModuleScript) | The heroes and their abilities' numbers (Sara) |
| `ServerStorage/Abilities.luau` | ServerStorage (ModuleScript) | Hero abilities on the server: checks, cooldowns, what each one does |
| `ServerStorage/Pull.luau` | ServerStorage (ModuleScript) | Pulling a player, bot or monster along a line (the whip) |
| `StarterPlayerScripts/AbilityControls.local.luau` | StarterPlayer › StarterPlayerScripts | Ability keys (right mouse, Q, E) and the ability bar |
| `StarterPlayerScripts/HeroEffects.local.luau` | StarterPlayer › StarterPlayerScripts | The whip, Flourish's spin, Treasure hunt's light, stun stars |
| `ServerStorage/Dev.luau` | ServerStorage (ModuleScript) | Who gets the developer controls (Studio, or the experience's owner) |
| `ServerStorage/WardEyes.luau` | ServerStorage (ModuleScript) | Wards: placing, spotting and destroying the Maze Master's floating eyes |
| `ServerStorage/Crushers.luau` | ServerStorage (ModuleScript) | Crushing walls: warning, slam, crushing survivors between, sliding back |
| `ReplicatedStorage/Config.luau` | ReplicatedStorage (ModuleScript) | Settings shared by the server and players' computers: speeds, vision, match length, relics, lives, spawn rooms |
| `ReplicatedStorage/Sounds.luau` | ReplicatedStorage (ModuleScript) | Every sound effect and the music, with volumes |
| `ReplicatedStorage/Movement.luau` | ReplicatedStorage (ModuleScript) | Movement rules shared by players and bots: speed by facing, frozen when held, slowed by false relics, running backwards |
| `ReplicatedStorage/Characters.luau` | ReplicatedStorage (ModuleScript) | Finds the character behind a UserId, a player's or a survivor bot's (relic beams, the kill) |
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
| `StarterPlayerScripts/DoorView.local.luau` | StarterPlayer › StarterPlayerScripts | Draws each door as your team last saw it, and its warning rumble (shaking, dust) |
| `StarterPlayerScripts/MonsterControls.local.luau` | StarterPlayer › StarterPlayerScripts | A monster player's lunge (left click, or a button on touch screens) |
| `StarterPlayerScripts/MazeMasterUI.local.luau` | StarterPlayer › StarterPlayerScripts | The Maze Master's dark mana bar, tool buttons and clicking on doors, cells, survivors and crushing walls |
| `StarterPlayerScripts/CrusherView.local.luau` | StarterPlayer › StarterPlayerScripts | A crushing wall's warning: its walls shake and dust pours out |
| `StarterPlayerScripts/FalseRelicMarks.local.luau` | StarterPlayer › StarterPlayerScripts | False relics glow red for the monster side (only they're told which are false) |
| `StarterPlayerScripts/FalseRelicAlert.local.luau` | StarterPlayer › StarterPlayerScripts | The red border and "FALSE RELIC" when you click one |
| `StarterPlayerScripts/WardView.local.luau` | StarterPlayer › StarterPlayerScripts | Wards bobbing and peering about, and the monster side's alarm while one is destroyed |
| `StarterPlayerScripts/HauntAlert.local.luau` | StarterPlayer › StarterPlayerScripts | The purple screen edge and whisper when you're haunted |
| `StarterPlayerScripts/LobbyUI.local.luau` | StarterPlayer › StarterPlayerScripts | The lobby between matches: who's in, preferred role, Start |
| `StarterPlayerScripts/DevMatch.local.luau` | StarterPlayer › StarterPlayerScripts | Developers only: force your role for the next match, start a new match |
| `StarterPlayerScripts/DevDoors.local.luau` | StarterPlayer › StarterPlayerScripts | Developers only: a panel to work the doors (and G toggles the door under the mouse) |
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
