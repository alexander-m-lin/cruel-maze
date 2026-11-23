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
Moving away from where you face is slower. After being caught, click a sanctuary on the map to
choose where you come back. M hides the minimap.

**Lobby and roles:** between matches everyone waits in the lobby, which lists who's in. Pick a
preferred role there (Any, Survivor, Monster or Maze Master; you get it if the slot is free) and
anyone presses Start. Roles: 3 survivors, 2 monsters and a Maze Master; empty slots get bots
(survivor bots named "Bot 1"..., AI monsters, and an AI Maze Master that uses the same tools as a
person: it shuts doors ahead of chased survivors, sets off crushing walls as they walk in, keeps
wards watching relics and wherever survivors were last seen).
Developers (anyone in Studio, and the experience's owner in the published game) also get buttons
at the bottom left: "Role" forces their role for the next match, "New match" ends this one and
starts another straight away, and "Doors" opens the doors panel.
- **Monster:** move as usual; left-click is your hero's main ability (Fear Eater: Devour). While
  you can see a survivor you speed up, to +20% after 3 seconds; lose sight of them all for a
  second and it starts again. You see what your
  team sees (other monsters and the Maze Master); survivors are hidden unless you see them.
  Your map shows the relics your side has seen (with your own eyes or a ward's).
- **Maze Master:** no body; pan the camera with WASD, zoom with the mouse wheel. False relics glow
  red for you and the monsters. You see what the monsters see, round your wards, and each
  crushing wall's stretch of corridor. You know where every relic is (they're on your map) but
  can't see round them: wards are how you watch them. Every door and crushing wall is
  outlined (purple = ready, grey = not yet): click one to use it. Each door rests 20 s after you
  change it and each crushing wall 10 s after it slams; the others stay ready. A door opens or shuts; a
  crushing wall (hidden in the maze) slams together, crushing survivors between them.
  Hovering one shows the ability's name, or a clock while it recharges. Two buttons place things:
  wards (1: a floating eye your side sees round, 50 studs in line of sight; up to 4 at a time) and
  false relics (2, two a match: they look like relics, and a survivor who clicks one is revealed
  and slowed). Right-click or Esc cancels placing.

**Heroes:** every survivor plays **Sara, the Cryptraider** and every monster **Fear Eater** for
now (more heroes and a character select are coming). Survivors' abilities aim the way you face.

Sara:
- **Right mouse: Whip** (5 s; 2 s if it hits nothing). Lashes out 39 studs, catching monsters within 5 studs of it and
  teammates within 4. A wall or relic pulls you to it; a teammate is
  pulled to you; a monster is pulled to you and stunned for 1 second.
- **Q: Treasure hunt** (15 s). The nearest relic your team hasn't spotted (real or false) within
  110 studs is spotted, with a pillar of light over it.
- **E: Flourish** (60 s). Spin the whip overhead for 1 second, standing still (a ring on the
  floor shows its reach); half a second in, every monster within 20 studs is stunned for 3.5
  seconds. Caught before then: no stun.
A stunned monster can't move, lunge or catch (stars circle its head). Crushing walls stun
monsters caught between them too. A monster in the middle of a kill can't be stunned or pulled.

Fear Eater (a floating wraith in a tattered black cloak, huge pale arms reaching out of his
sleeves; left click does nothing for him):
- **Left click: Devour** (5 s). No aiming: he goes for the nearest survivor he can see in front of
  him within 12 studs (a feared survivor within 40 studs, in a clear line, anywhere round him, comes
  first), ringed on the floor while Devour is ready (blue; red for a feared one). Nobody to go for:
  nothing happens, no cooldown. He gathers himself for 0.3 seconds, facing them, while their screen
  flashes red and he snarls; then a feared survivor is caught unless they reached a sanctuary or
  got 46 studs away, and anyone else is caught if they're still within 14 studs in a clear line.
  Otherwise he lunges 8 studs and misses (full cooldown). A stun or a whip pull during the windup
  calls it off. Caught: he lunges to them, holds them up facing away, struggling,
  winds his head back, lifts them flat and draws their head into his hood, where they keep
  struggling until it dies away; then he draws them back out and drops the body, which lies there
  for 4 seconds.
  A feared survivor has a red glow and red wisps round their head, for anyone who can see them.
- **Q: Instill Fear** (25 s). He rears up, arms flung wide, and a dark ring sweeps out from him.
  Every survivor outside a sanctuary, wherever they are, feels **dread**: a 5-second countdown to
  reach a sanctuary or get within 10 studs of another survivor (bots count). Anyone who doesn't
  is **feared** for 5 seconds: revealed to the monster side and slowed to 80%.
- **E: Living Nightmare** (60 s). For 7 seconds he goes half see-through, trailing dark mist, and
  passes through the maze's inner walls and doors (not the outer wall, and never into a
  sanctuary), moving 60% faster while heading toward a feared survivor (within 60° of straight at
  them), and Devour recharges in 1 second (casting it cuts Devour's wait to 1 s too). Ending
  inside a wall pushes him out into the middle of that cell. While it's ready (or 2 seconds from
  ready) and while it runs, a wide red triangle round him points straight at each feared
  survivor, wherever they are (floating just above the walls, so walls and fog never hide them).
AI monsters are Fear Eater too: they Devour whoever they're chasing once they're in range. One
AI monster a match (`Config.AI_MONSTERS_CASTING`) also casts Instill Fear whenever it's ready,
and Living Nightmare whenever it's ready and a survivor is feared (then it goes straight through
inner walls after feared survivors, faster). The cast animations are simple stand-ins for now.

**How a match goes (as a survivor):**
- Find and collect **6 of the 9 relics** within **4 minutes**. Standing on a relic shows a prompt (a mouse with its left button lit):
  **left-click** to start collecting, then stay on it for 3 seconds (leaving or getting caught
  resets it; the monster turning up doesn't). Once anyone on your team has seen a relic,
  the area around it stays visible to your team until it's collected.
- An AI **monster** roams the maze, and chases you when it sees or hears you. If it catches you,
  you lose one of your **3 lives**.
- **Wards** (floating purple eyes) let the monster side see 50 studs around them, in line of sight. Once your team spots
  one it stays shown; stand next to one and left-click, then stay close for 2 seconds (a bar
  fills), to destroy it (the monster side sees where). Anything that reveals you (a false relic,
  being feared) also lights up a small ring round you for the monster side. AI monsters come for you,
  even through walls, whenever you're within 120 studs and the monster side can see you
  in any way: another monster, a ward, a crushing wall, a reveal. Relics give the monster side
  no sight of their own: the Maze Master knows where they all are and watches them with wards,
  usually from a little way down a corridor, so look for the eye before you walk in.
- **Sanctuaries** (cyan barriers) are safe: the monster can't enter, and the monster side can't
  see you inside one at all (not through wards or reveals). The start
  sanctuary is 3x3 cells with 3 exits, the others 2x2 with 2-3; walking from just outside one
  exit to just outside another takes at least 6 cells, even with every door open, so nobody can
  hold two. Walk into one to capture it
  for your team, and you can come back there after being caught. Your team's sanctuaries (the start
  sanctuary, and any you capture) are on your map whole.
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
| `ServerStorage/MazeBuilder.luau` | ServerStorage (ModuleScript) | Generates and builds each maze: walls, floors, sanctuaries, relics. Wall and floor looks |
| `ServerStorage/MazeLayout.luau` | ServerStorage (ModuleScript) | Layout rules: carving sanctuaries, picking relic spots and door slots, keeping the maze connected (even with every door shut) |
| `ServerStorage/Doors.luau` | ServerStorage (ModuleScript) | Opening and closing doors mid-match (warning, movement, nudging people out of the way), the door AI, and the Studio dev panel's requests |
| `ServerStorage/Objectives.luau` | ServerStorage (ModuleScript) | Relics (spotting, collecting) and sanctuaries (capturing, monster barriers) |
| `ServerStorage/MonsterAI.luau` | ServerStorage (ModuleScript) | An AI monster: roams, chases, catches. Also builds the monster body |
| `ServerStorage/PlayerMonster.luau` | ServerStorage (ModuleScript) | A monster played by a person: dresses their invisible character in the monster body; the lunge and its catches |
| `ServerStorage/MazeMaster.luau` | ServerStorage (ModuleScript) | The Maze Master's tools: dark mana, cooldowns, doors, wards, false relics, crushing walls |
| `ServerStorage/SurvivorBot.luau` | ServerStorage (ModuleScript) | A survivor bot for empty survivor slots: roams, collects relics it sees, runs to a sanctuary from monsters. Passes for a player to the rest of the game |
| `ServerStorage/BotAnimate.legacy.luau` | ServerStorage (Script, a template) | Roblox's standard character Animate script, as a server copy that bots get, so they animate exactly like players |
| `ServerStorage/SpeedCheck.luau` | ServerStorage (ModuleScript) | Server-side speed check: pulls back characters moving faster than allowed |
| `ServerStorage/MazeMasterAI.luau` | ServerStorage (ModuleScript) | The AI Maze Master: uses the Maze Master's tools, knowing only what the monster side sees |
| `ReplicatedStorage/Heroes.luau` | ReplicatedStorage (ModuleScript) | The list of heroes (loads each one's `HeroData`); how to add one |
| `ReplicatedStorage/HeroData/<Hero>.luau` | ReplicatedStorage › HeroData (ModuleScripts) | One per hero: who they are and their abilities' numbers (Sara, FearEater) |
| `ServerStorage/Abilities.luau` | ServerStorage (ModuleScript) | Hero abilities on the server, for survivors, monster players and AI monsters alike: checks, cooldowns, calling the hero's handlers |
| `ServerStorage/HeroAbilities/<Hero>.luau` | ServerStorage › HeroAbilities (ModuleScripts) | One per hero: what each ability does (Sara's whip etc.; Fear Eater's Devour) |
| `StarterPlayerScripts/HeroVisuals/<Hero>.luau` | StarterPlayerScripts › HeroVisuals (ModuleScripts) | One per hero: how they look on players' computers. FearEater: his floating, the Devour lunge and kill |
| `StarterPlayerScripts/Victims.luau` | StarterPlayerScripts (ModuleScript) | Drawing a monster's victim: hiding, struggling, going limp, the body that drops |
| `ServerStorage/Pull.luau` | ServerStorage (ModuleScript) | Pulling a player, bot or monster along a line (the whip) |
| `StarterPlayerScripts/AbilityControls.local.luau` | StarterPlayer › StarterPlayerScripts | Ability keys (right mouse for survivors, left for monsters; Q, E) and the ability bar; hold-to-aim previews (a hero's `aim[slot]`, none at the moment) |
| `ReplicatedStorage/DevourAim.luau` | ReplicatedStorage (ModuleScript) | Who Fear Eater's Devour targets and whether it lands: the server and the target ring share it |
| `StarterPlayerScripts/HeroEffects.local.luau` | StarterPlayer › StarterPlayerScripts | Sara's effects (the whip, Flourish's spin, Treasure hunt's light; to move into `HeroVisuals/Sara`), and stun stars and pull dust for everyone |
| `ServerStorage/Dev.luau` | ServerStorage (ModuleScript) | Who gets the developer controls (Studio, or the experience's owner) |
| `ServerStorage/WardEyes.luau` | ServerStorage (ModuleScript) | Wards: placing, spotting and destroying the Maze Master's floating eyes |
| `ServerStorage/Crushers.luau` | ServerStorage (ModuleScript) | Crushing walls: warning, slam, crushing survivors between, sliding back |
| `ReplicatedStorage/Config.luau` | ReplicatedStorage (ModuleScript) | Settings shared by the server and players' computers: speeds, vision, match length, relics, lives, sanctuaries |
| `ReplicatedStorage/Sounds.luau` | ReplicatedStorage (ModuleScript) | Every sound effect and the music, with volumes |
| `ReplicatedStorage/Movement.luau` | ReplicatedStorage (ModuleScript) | Movement rules shared by players and bots: speed by facing, frozen when held, slowed by false relics, running backwards |
| `ReplicatedStorage/Characters.luau` | ReplicatedStorage (ModuleScript) | Finds the character behind a UserId, a player's or a survivor bot's (relic beams, the kill) |
| `ReplicatedStorage/Net.luau` | ReplicatedStorage (ModuleScript) | Creates/finds the remote events used to message between server and players |
| `StarterGui/MazeHUD/HUD.local.luau` | StarterGui › MazeHUD | Timer, relics and lives, announcements, relic progress bars |
| `StarterPlayerScripts/Controls.local.luau` | StarterPlayer › StarterPlayerScripts | Facing the mouse, speed by direction, backwards running, facing a relic while collecting it |
| `StarterPlayerScripts/IsometricCamera.local.luau` | StarterPlayer › StarterPlayerScripts | Fixed isometric camera; watches a teammate (a player, or a survivor bot) when you have no character |
| `StarterPlayerScripts/FogOfWar.local.luau` | StarterPlayer › StarterPlayerScripts | Fog of war and line of sight, shared with teammates, plus the vision around spotted relics |
| `StarterPlayerScripts/FogState.luau` | StarterPlayer › StarterPlayerScripts (ModuleScript) | What the fog knows (seen, in view), shared with the minimap |
| `StarterPlayerScripts/Minimap.local.luau` | StarterPlayer › StarterPlayerScripts | Corner map: explored and in-view areas, and dots for you, teammates, spotted relics and a visible monster (M hides it) |
| `StarterPlayerScripts/SpawnPicker.local.luau` | StarterPlayer › StarterPlayerScripts | The map for choosing a sanctuary after being caught |
| `StarterPlayerScripts/RelicEffects.local.luau` | StarterPlayer › StarterPlayerScripts | Reaching for a relic with a beam of light while collecting it |
| `StarterPlayerScripts/MonsterAnimate.local.luau` | StarterPlayer › StarterPlayerScripts | Moves monsters smoothly; a hero monster is posed by its `HeroVisuals` module, the stand-in here (walk, chase, kill) |
| `StarterPlayerScripts/DoorView.local.luau` | StarterPlayer › StarterPlayerScripts | Draws each door as your team last saw it, and its warning rumble (shaking, dust) |
| `StarterPlayerScripts/MonsterControls.local.luau` | StarterPlayer › StarterPlayerScripts | A monster player held still for Devour's windup and carried through its lunge, and the stand-in's left-click lunge |
| `StarterPlayerScripts/MazeMasterUI.local.luau` | StarterPlayer › StarterPlayerScripts | The Maze Master's controls: outlined targets (doors, crushing walls, survivors) to click, the hover name or cooldown clock, and the ward / false relic placement buttons |
| `StarterPlayerScripts/CrusherView.local.luau` | StarterPlayer › StarterPlayerScripts | A crushing wall's warning: its walls shake and dust pours out |
| `StarterPlayerScripts/FalseRelicMarks.local.luau` | StarterPlayer › StarterPlayerScripts | False relics glow red for the monster side (only they're told which are false) |
| `StarterPlayerScripts/FalseRelicAlert.local.luau` | StarterPlayer › StarterPlayerScripts | The red border and "FALSE RELIC" when you click one |
| `StarterPlayerScripts/WardView.local.luau` | StarterPlayer › StarterPlayerScripts | Wards bobbing and peering about, and the monster side's alarm while one is destroyed |
| `StarterPlayerScripts/FearAlert.local.luau` | StarterPlayer › StarterPlayerScripts | Instill Fear on your screen: the dread countdown, then "FEARED" (or "Safe") |
| `StarterPlayerScripts/FearMarks.local.luau` | StarterPlayer › StarterPlayerScripts | Fear Eater's fear made easy to read: a red glow and wisps round feared survivors' heads, his Living Nightmare pointers to each feared survivor, the ring under Devour's target, and the targeted survivor's red flash |
| `StarterPlayerScripts/LobbyUI.local.luau` | StarterPlayer › StarterPlayerScripts | The lobby between matches: who's in, preferred role, Start |
| `StarterPlayerScripts/DevMatch.local.luau` | StarterPlayer › StarterPlayerScripts | Developers only: force your role for the next match, start a new match |
| `StarterPlayerScripts/DevDoors.local.luau` | StarterPlayer › StarterPlayerScripts | Developers only: a panel to work the doors (and G toggles the door under the mouse) |
| `StarterPlayerScripts/MonsterPing.local.luau` | StarterPlayer › StarterPlayerScripts | Sonar ping showing a nearby monster you can't see |
| `StarterPlayerScripts/SoundEffects.local.luau` | StarterPlayer › StarterPlayerScripts | Plays the sound effects and music |

Script Sync names files by script type: `.legacy.luau` = Script, `.local.luau` = LocalScript,
`.luau` = ModuleScript.

Also in the place file (not scripts): Fear Eater's body (`ServerStorage.FearEaterRig`; earlier
drafts in `ServerStorage.FearEaterDrafts`), the stand-in monster's rigged body (`ServerStorage.MonsterRig`), the relic
skull (`ServerStorage.SkullRelic`, Creator Store asset 98498294 by RoyalBoyMc), the
wall and floor materials (`MaterialService`), and a few developer previews (`Workspace.WallPalette`,
`Workspace.FloorPalette`, `SoundService.SoundBoard`).

## Heroes

Every hero, survivor or monster, is three modules named after the hero's id (e.g. `FearEater`):

1. `ReplicatedStorage/HeroData/<Id>.luau`: name, role (`"Survivor"` or `"Monster"`) and the three
   abilities (`Primary` = right mouse, `Secondary` = Q, `Ultimate` = E), each with an `id`, `name`,
   `cooldown` and its own numbers. `soon = true` shows an ability greyed out until it's built. A
   monster also gives its body (`rig`, a model in ServerStorage with a `HumanoidRootPart`, and a
   `GroundOffset` attribute if it floats), `rigScale`, `lunge = false` if it has no left-click
   lunge, and its `kill` timing (at least `RELEASE` and `DONE`, seconds from the catch).
2. `ServerStorage/HeroAbilities/<Id>.luau`: returns `{ [abilityId] = function(ctx, cast) }`. The
   server checks the use and the cooldown, then calls it; return true if it was used. `cast` has
   the user (a player, or nil for an AI monster), the monster (for monsters), their root, the aim
   and the ability's numbers; `ctx` has the match and helpers. See `Abilities.luau`.
3. `StarterPlayerScripts/HeroVisuals/<Id>.luau`: how it looks. A monster's module exports
   `animate = { setup, pose, victim }`, which MonsterAnimate calls for any body whose `Hero`
   attribute names it. Any hero's module can also export `aim = { [slot] = { update, hide } }`:
   that ability's key then shows the preview while held and fires on release.

Then add the id to `Heroes.ORDER`. Until there's a character select, `Config.DEFAULT_SURVIVOR_HERO`
and `Config.DEFAULT_MONSTER_HERO` pick who everyone plays.

Other folders:
- `assets/textures/`: the wall and floor texture images, Fear Eater's textures, and how they were made.
- `tools/textures/`: Python scripts that made them (tileable variations, toning a texture down,
  and `receive.py`, which saves images sent from Studio and serves them for uploading).
- `docs/roadmap.md`: the implementation plan.

## History

- An earlier dodge-ball game was deleted. It's in the first commit (`11d51a5`): its scripts are
  under `src/ServerStorage/DodgeGameArchive/`, and the place file in that commit still contains it.
