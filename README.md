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
wards watching relics and wherever survivors were last seen). One survivor bot a match also uses
its hero's abilities, if it's a hero bots know how to play (Kai so far: scans unseen areas, EMPs wards
it sees, encrypts when about to be caught).
Developers (anyone in Studio, and the experience's owner in the published game) also get buttons
at the bottom left: "Role" forces their role for the next match, "New match" ends this one and
starts another straight away, and "Doors" opens the doors panel. "Sandbox" starts the **sandbox**
instead: a 9 x 9 test maze (an open square with a wall jutting in, a door in it, a crushing wall in
a short corridor, one relic, one false relic and one sanctuary, wrapped round the top corner by
winding hallways like the real maze's), with only the players in it, no
timer, no end and 99 lives. A panel down the left places things where you click the floor (a
roaming bot, a dummy bot held in place, a feared dummy, an AI monster, a ward, a false relic) and
does things at once (fear every survivor, freeze or unfreeze AI monsters, make your abilities
ready, Auto-ready (a toggle: every ability you use recharges in 1 second), give your lives back,
clear the bots and AI monsters). At its top a tracker shows where you
are (studs and maze cell) and how fast you're moving, next to the walk speed you're allowed right
now. "New match" goes back to a normal match.
Everything in the sandbox is the real game's code; only the maze and who's in it differ.
- **Monster:** move as usual; left-click is your hero's main ability (Fear Eater: Devour; the Minotaur: Tear Asunder). While
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

**Heroes:** survivors play **Sara, the Cryptraider** or **Kai, the Hacker**; monsters play **Fear
Eater, the Wraith** or **the Minotaur, the Juggernaut**. Pick yours in the lobby ("Your survivor",
"Your monster"): heroes are all different within a team in a match (if two of you want the same
one, one gets it at random; AI monsters take whoever's left), repeating only while there are fewer
heroes than players on that team. In the sandbox the panel's "Hero" switches yours. Survivors' abilities aim the way you face.

Sara:
- **Right mouse: Whip** (5 s; 2 s if it hits nothing). Lashes out 39 studs, catching monsters within
  5 studs of it (teammates aren't hit: it passes them). A wall or relic pulls you to it; a monster
  is pulled to you and stunned for 1 second.
- **Q: Treasure hunt** (15 s). The nearest relic your team hasn't spotted (real or false) within
  110 studs is spotted, with a pillar of light over it.
- **E: Flourish** (60 s). Spin the whip overhead for 1 second, standing still (a ring on the
  floor shows its reach). While you spin, any monster's catch on you is deflected (sparks and a
  clang; it doesn't stun them); when the spin ends, every monster within 20 studs is stunned for
  3.5 seconds. Only you are protected, and not from crushing walls. Whip a monster in, then
  Flourish, and it's stunned on top of you.

Kai (no grapple, no stun: information, the Maze Master's devices, and escaping by deception):
- **Right mouse: Scanner** (15 s). A 90-degree cone the way you face, 70 studs, fixed when you
  start it (shown on the floor to your team). After 1 second it sees through walls for 3 seconds,
  shared with your team: relics and wards in it are spotted, and monsters, doors and crushing
  walls in it show (monsters only while they're in it). False relics look as they always do.
- **Q: EMP** (40 s). An electric pulse round where you cast it: half a second later, for 5
  seconds, every door within 50 studs is jammed open (a shut one opens, the Maze Master can't
  close it, and it closes again afterwards), crushing walls there can't go off (one that's
  rumbling stops), and the wards it caught see nothing. A ward placed afterwards works. Everyone
  sees the bright blue circle (its edge floats above the walls), so it gives away where you cast it.
- **E: Encrypt** (60 s). For 5 seconds you can't be caught and the monster side can't see you, not
  even if you're revealed: they see only a small square of flickering blue tiles in the middle of
  the cell you're in, which slides to the next cell as you cross into it, leaving a thin line of
  tiles behind it that soon fades. Leaving a junction, copies of it run off down the
  other ways out (up to 3), wandering like you would but keeping off the way you really went; nothing tells them apart, and every one
  flickers in the last second. Monsters can follow any of them (their chase speed keeps building),
  and you're catchable again the moment it ends. Using an ability, collecting a relic or
  destroying a ward ends it early. Crushing walls still get you.
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
  A survivor under dread has a red ring at their feet that wears away clockwise from its
  bottom as the countdown runs, gone once they're safe or feared.
- **E: Living Nightmare** (60 s). For 7 seconds he goes half see-through, trailing dark mist, and
  passes through the maze's inner walls and doors (not the outer wall, and never into a
  sanctuary), moving 60% faster while heading toward a feared survivor (within 60° of straight at
  them), and Devour recharges in 1 second (casting it cuts Devour's wait to 1 s too). Ending
  inside a wall pushes him out into the middle of that cell. While it's ready (or 2 seconds from
  ready) and while it runs, a wide red triangle round him points straight at each feared
  survivor, wherever they are (floating just above the walls, so walls and fog never hide them).
The Minotaur (a massive horned juggernaut in bronze armour, a head taller than Fear Eater; his
attacks are devastating but telegraphed, and commit him). He walks at 70% of a monster's speed (a
slow, heavy stomp; the chase boost still applies), so the Charge and Crush are how he closes in:
- **Left click: Tear Asunder** (5 s). Like Devour without the fear: the nearest survivor he can see
  in front of him within 10 studs (ringed while it's ready), a 0.3-second windup (rearing back,
  arms spread; their screen flashes red), then a lunge that catches them if they're still within
  12 studs in a clear line. Nobody to go for: no cooldown. Caught: he lifts them overhead between
  his fists and tears them in two.
- **Q: Devastating Charge** (10 s from when it ends). For 1 second he lowers his horns and paws the
  floor while a red lane shows his path, straight ahead to the first wall or shut door (anyone
  who can see him sees it; his side always). Then he charges along it at 120 studs a second and
  can't steer or stop. Every survivor within 7 studs of his path (most of a corridor) is caught
  and flung aside as he runs on, several in one charge if they're lined up; nobody past where he
  stops. A door counts as shut from the moment its slab starts to rise: if he hasn't reached its
  middle by then he stops a body's width short of it, otherwise he carries on through. A shut door
  that finishes opening before he gets there lets him through. A stun calls it off. At the wall he
  reels for 0.6 seconds.
- **E: Crush** (60 s). Hold E to see his 100-stud range and where he'd land (under the mouse);
  let go and he crouches, leaps in a high arc (over walls if need be) and lands 1.5 seconds
  later. For the last 0.7 seconds a red ring shows where, drawn above the fog and the walls, to
  his side and to survivors within 40 studs of it. Survivors within 14 studs of the landing, in a
  clear line, are stunned for 2.5 seconds (stars circle their heads) - time for a Charge. He has
  to land somewhere he could stand: an aim inside a wall or a sanctuary is pulled back toward him.
AI monsters use their hero's left click on whoever they're chasing once they're in range (the
AI Minotaur doesn't Charge or Crush yet). One AI Fear Eater a match (`Config.AI_MONSTERS_CASTING`)
also casts Instill Fear whenever it's ready,
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
| `ServerStorage/BotAbilities.luau` | ServerStorage (ModuleScript) | When a survivor bot uses its hero's abilities (Kai so far: Scanner at nearby unseen cells, EMP at wards it sees, Encrypt when about to be caught); carried out through `Abilities.use`, exactly as a player's |
| `ServerStorage/BotAnimate.legacy.luau` | ServerStorage (Script, a template) | Roblox's standard character Animate script, as a server copy that bots get, so they animate exactly like players |
| `ServerStorage/SpeedCheck.luau` | ServerStorage (ModuleScript) | Server-side speed check: pulls back characters moving faster than allowed |
| `ServerStorage/MazeMasterAI.luau` | ServerStorage (ModuleScript) | The AI Maze Master: uses the Maze Master's tools, knowing only what the monster side sees |
| `ReplicatedStorage/Heroes.luau` | ReplicatedStorage (ModuleScript) | The list of heroes (loads each one's `HeroData`); how to add one |
| `ReplicatedStorage/HeroData/<Hero>.luau` | ReplicatedStorage › HeroData (ModuleScripts) | One per hero: who they are and their abilities' numbers (Sara, Kai, FearEater, Minotaur) |
| `ReplicatedStorage/Protection.luau` | ReplicatedStorage (ModuleScript) | Who can't be caught right now: Flourish (deflecting) and Encrypt (encrypted) |
| `ServerStorage/Abilities.luau` | ServerStorage (ModuleScript) | Hero abilities on the server, for survivors, monster players and AI monsters alike: checks, cooldowns, calling the hero's handlers |
| `ServerStorage/HeroAbilities/<Hero>.luau` | ServerStorage › HeroAbilities (ModuleScripts) | One per hero: what each ability does (Sara's whip etc.; Kai's Scanner and EMP; Fear Eater's Devour; the Minotaur's Charge and Crush) |
| `ServerStorage/AutoCatch.luau` | ServerStorage (ModuleScript) | An auto-targeted catch (Devour, Tear Asunder): pick the target, the windup, the lunge, the catch |
| `ServerStorage/Encrypt.luau` | ServerStorage (ModuleScript) | Kai's Encrypt: his circuit indicator and its decoys, cell to cell |
| `StarterPlayerScripts/HeroVisuals/<Hero>.luau` | StarterPlayerScripts › HeroVisuals (ModuleScripts) | One per hero: how they look on players' computers. FearEater: his floating, the Devour lunge and kill. Minotaur: his stomp, Tear Asunder and its kill, the Charge (lane, gallop, impact, trampled survivors) and Crush (leap, ring, shockwave), Crush's aiming preview |
| `StarterPlayerScripts/Victims.luau` | StarterPlayerScripts (ModuleScript) | Drawing a monster's victim: hiding, struggling, going limp, the body that drops, a body torn in two |
| `ServerStorage/Pull.luau` | ServerStorage (ModuleScript) | Pulling a player, bot or monster along a line (the whip) |
| `StarterPlayerScripts/AbilityControls.local.luau` | StarterPlayer › StarterPlayerScripts | Ability keys (right mouse for survivors, left for monsters; Q, E) and the ability bar; hold-to-aim previews (a hero's `aim[slot]`: the Minotaur's Crush); a `targeted` ability also sends the floor point under the mouse |
| `ReplicatedStorage/DevourAim.luau` | ReplicatedStorage (ModuleScript) | Who an auto-targeted catch (Devour, Tear Asunder) targets and whether it lands: the server and the target ring share it |
| `StarterPlayerScripts/HeroEffects.local.luau` | StarterPlayer › StarterPlayerScripts | Sara's effects (the whip, Flourish's spin, deflect sparks, Treasure hunt's light; to move into `HeroVisuals/Sara`), and stun stars (monsters, and survivors Crush stunned) and pull dust for everyone |
| `StarterPlayerScripts/KaiEffects.local.luau` | StarterPlayer › StarterPlayerScripts | Kai's effects: Scanner's cone, EMP's circle and sparking devices, Encrypt's circuit indicators and his see-through look to his team |
| `ServerStorage/Dev.luau` | ServerStorage (ModuleScript) | Who gets the developer controls (Studio, or the experience's owner) |
| `ServerStorage/Sandbox.luau` | ServerStorage (ModuleScript) | The dev sandbox's hand-made test maze (fed to `MazeBuilder.build`) and settings; Match runs the sandbox match and its panel's actions |
| `ServerStorage/Fear.luau` | ServerStorage (ModuleScript) | Marking a survivor feared (Instill Fear, and the sandbox's feared spawns) |
| `StarterPlayerScripts/SandboxPanel.local.luau` | StarterPlayer › StarterPlayerScripts | Developers only, in the sandbox: the panel for placing bots, monsters, wards and false relics, and the quick actions |
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
| `StarterPlayerScripts/MonsterControls.local.luau` | StarterPlayer › StarterPlayerScripts | A monster player held still for Devour's (or Tear Asunder's) windup and carried through its lunge, carried along the Minotaur's Charge and through Crush's leap, and the stand-in's left-click lunge |
| `StarterPlayerScripts/MazeMasterUI.local.luau` | StarterPlayer › StarterPlayerScripts | The Maze Master's controls: outlined targets (doors, crushing walls, survivors) to click, the hover name or cooldown clock, and the ward / false relic placement buttons |
| `StarterPlayerScripts/CrusherView.local.luau` | StarterPlayer › StarterPlayerScripts | A crushing wall's warning: its walls shake and dust pours out |
| `StarterPlayerScripts/FalseRelicMarks.local.luau` | StarterPlayer › StarterPlayerScripts | False relics glow red for the monster side (only they're told which are false) |
| `StarterPlayerScripts/FalseRelicAlert.local.luau` | StarterPlayer › StarterPlayerScripts | The red border and "FALSE RELIC" when you click one |
| `StarterPlayerScripts/WardView.local.luau` | StarterPlayer › StarterPlayerScripts | Wards bobbing and peering about, and the monster side's alarm while one is destroyed |
| `StarterPlayerScripts/FearAlert.local.luau` | StarterPlayer › StarterPlayerScripts | Instill Fear on your screen: the dread countdown, then "FEARED" (or "Safe") |
| `StarterPlayerScripts/FearMarks.local.luau` | StarterPlayer › StarterPlayerScripts | Fear Eater's fear made easy to read: the dread ring at survivors' feet, a red glow and wisps round feared survivors' heads, his Living Nightmare pointers to each feared survivor, the ring under Devour's target, and the targeted survivor's red flash |
| `StarterPlayerScripts/LobbyUI.local.luau` | StarterPlayer › StarterPlayerScripts | The lobby between matches: who's in, preferred role, survivor and monster hero, Start |
| `StarterPlayerScripts/DevMatch.local.luau` | StarterPlayer › StarterPlayerScripts | Developers only: force your role for the next match, start a new match |
| `StarterPlayerScripts/DevDoors.local.luau` | StarterPlayer › StarterPlayerScripts | Developers only: a panel to work the doors (and G toggles the door under the mouse) |
| `StarterPlayerScripts/MonsterPing.local.luau` | StarterPlayer › StarterPlayerScripts | Sonar ping showing a nearby monster you can't see |
| `StarterPlayerScripts/SoundEffects.local.luau` | StarterPlayer › StarterPlayerScripts | Plays the sound effects and music |

Script Sync names files by script type: `.legacy.luau` = Script, `.local.luau` = LocalScript,
`.luau` = ModuleScript.

Also in the place file (not scripts): Fear Eater's body (`ServerStorage.FearEaterRig`; earlier
drafts in `ServerStorage.FearEaterDrafts`), the Minotaur's body (`ServerStorage.MinotaurRig`; the
generated concepts it was picked from in `ServerStorage.ModelConcepts`, which the sandbox panel's
"Concepts" shows walking), the stand-in monster's rigged body (`ServerStorage.MonsterRig`), the relic
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

Then add the id to `Heroes.ORDER`. Heroes come from the lobby picks and Match's
`pickSurvivorHero` / `pickMonsterHero` (all different within a team while the roster allows).
A monster's `Primary` with `autoTarget = true` is carried out by `AutoCatch` (call it from the
handler) and is what AI monsters catch with.
(Sara's and Kai's visuals are LocalScripts for now, `HeroEffects` and `KaiEffects`, rather than
`HeroVisuals` modules: a survivor needs a `HeroVisuals` module only for a hold-to-aim preview.)

**Protection from catches** (`ReplicatedStorage/Protection.luau`): every monster catch (Devour,
Tear Asunder, the Charge, the stand-in's lunge and touch) asks `Abilities.refusesCatch` first. Flourish deflects
("DeflectUntil"); Encrypt can't be caught and hides you ("EncryptedUntil": left out of who monsters
hunt, Devour's targets, fear marks and pointers, and the monster side's fog).

Other folders:
- `assets/textures/`: the wall and floor texture images, Fear Eater's textures, and how they were made.
- `tools/textures/`: Python scripts that made them (tileable variations, toning a texture down,
  and `receive.py`, which saves images sent from Studio and serves them for uploading).
- `docs/roadmap.md`: the implementation plan.

## History

- An earlier dodge-ball game was deleted. It's in the first commit (`11d51a5`): its scripts are
  under `src/ServerStorage/DodgeGameArchive/`, and the place file in that commit still contains it.
