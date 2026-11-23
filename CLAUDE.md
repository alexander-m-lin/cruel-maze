# CLAUDE.md

This project is the start of **Cruel Maze**. The design overview below is the direction the game is heading. Use it to guide decisions. Section 12 lists what is still undecided: ask rather than assume on those.

The implementation plan, with phases, estimates and progress checkboxes, is in [docs/roadmap.md](docs/roadmap.md). Read it before planning new work, and tick a phase off there when it's done.

## Working on this project

**Status (2026-11-21):** Phases 0-3 are done (Phase 3 merged with its full six-human match still to be played). Phase 4 (heroes and abilities) is in progress on the `phase-4` branch: Sara and Kai are built (survivors), with Fear Eater, plus many balance and Maze Master changes from playtesting (see the roadmap's Phase 4 notes). Not merged yet; its "done when" (more heroes, character select) isn't met. The game is published privately as "Cruel Maze 0.1"; once Studio has it open from Roblox, saves go there, so use File > Save to File over `CruelMaze.rbxl` before committing (the user works from the local file). The README has how to play and what every script does.

**Files and Studio**
- The place is `CruelMaze.rbxl` (renamed from `Place2.rbxl`). Scripts are mirrored between Studio and the repo folders by Studio's **Script Sync**: `.legacy.luau` = Script, `.local.luau` = LocalScript, `.luau` = ModuleScript. In Script Sync, each service (ServerScriptService, ServerStorage, ReplicatedStorage, StarterPlayerScripts, StarterGui › MazeHUD) is linked at the **repo root**. Linking a service to its own folder nests a duplicate folder inside it.
- Script Sync mirrors deletions. Deleting a synced file deletes the script in Studio, so check what is linked before removing files.
- Edits to files don't reach Studio during a playtest. Stop the playtest, check the edit landed (search the Studio copy's Source), then start a new one. `ReplicatedStorage/Config.luau` has sometimes stopped syncing; if so, set the Studio script's Source to the file's text and compare byte counts.
- Non-script things live only in the place file: Fear Eater's body (`ServerStorage.FearEaterRig`), the stand-in monster rig (`ServerStorage.MonsterRig`), the relic skull (`ServerStorage.SkullRelic`, Creator Store asset 98498294), the wall and floor materials (`MaterialService`), and dev previews (`Workspace.WallPalette`, `Workspace.FloorPalette`, `SoundService.SoundBoard`). Save the place before committing.
- Tunable numbers are in `ReplicatedStorage/Config.luau` (match rules), `ReplicatedStorage/Sounds.luau` (sounds and music), and the settings at the top of each script.

**Testing through the Studio MCP**
- Playtests open in the lobby. Start a match by firing `ReplicatedStorage.Remotes.Lobby` with `"start"` from the Client (or `"prefer", role` first); the `DevMatch` remote's `"role"` forces a role and `"restart"` jumps straight to a new match.
- **Use the sandbox for most QA.** `DevMatch` remote: `"role", role` then `"sandbox"` starts a sandbox match (ServerStorage/Sandbox: a 6 x 6 maze, only you in it, no end, 99 lives). Then fire `DevMatch` with `"sandboxAction", action[, floorPoint]` (the panel's buttons, see Match's `sandboxAction`): `"bot"`/`"dummy"`/`"fearedDummy"`/`"monster"`/`"ward"`/`"falseRelic"` at a point, or `"fearAll"`, `"freeze"`, `"ready"`, `"lives"`, `"clear"`, `"hero"` (switch to the next survivor hero, e.g. Sara → Kai). The answer comes back on `DevMatch` as `"sandboxResult", ok, message`. Cell (x, z)'s centre is `((x - 0.5) * 20 - 60, FloorY, (z - 0.5) * 20 - 60)`; the layout diagram is at the top of Sandbox.luau. Keep the sandbox on the real game's code: change what goes in (layout, spawns), never how systems behave.
- Test in playtests with `execute_luau` on the Server or Client, measuring with numbers. Screenshots show the 3D view only while the Studio window is visible, and never show BillboardGuis (floating labels). To check one visually, copy it onto a ScreenGui. Close-up visual checks work best in Edit mode with a camera position.
- The server doesn't move monster bodies: a monster's position is its model's `Pivot` attribute, and players' computers move the body (MonsterAnimate). Read `model:GetAttribute("Pivot")` in server tests, not `GetPivot()`.
- Hero effects are too quick to screenshot: set the Workspace attribute `HeroFxSlow` (e.g. 8) on the Client to slow them down in Studio (the server's pulls don't slow, so positions drift).
- Fear Eater's kill, dash and casts can be frozen at a moment on the Client in Studio: Workspace attributes `KillPreviewAt` / `DevourPreviewAt` / `CastPreviewAt` (seconds in). `MatchTest:Invoke("monsterAbility", n, slot, aim)` makes AI monster n use an ability (e.g. "Secondary" for Instill Fear on yourself as a survivor). `MatchTest:Invoke("attr", userId, name, value)` sets an attribute on a survivor, bots included (a bot's real attributes live on its bot object, not its body: setting one on the body doesn't reach the server's checks), e.g. "FearedUntil" to test Devour's feared range. To pose a kill without a real catch, on the Client anchor your own root and set the monster body's `KillVictim` (your UserId) and `KillStart` locally (`MatchTest:Invoke("monsters", false)` on the Server stops the monsters first). `MatchTest:Invoke("monsters", false, "ai")` stops only the AI monsters, so your own monster can still Devour (an inactive monster can't). Screenshots work in play mode; bind a render step after the camera to look closer.
- The server's speed check (`SpeedCheck`) pulls back characters moved from the client. Teleport a player in tests with `ServerStorage.MatchTest:Invoke("teleport", player, cframe)` from the Server.
- Scripted `Humanoid:Move()` gets overridden by the default controls. Use `user_keyboard_input` and `user_mouse_input` for real input.
- The client in playtests often runs at about 15 fps, so time-sensitive measurements are noisy.
- `user_mouse_input` coordinates are below the top bar: aim at `WorldToViewportPoint(...)` minus the GUI inset (58 px here). The real cursor can also drift the mouse between calls, so check `GetMouseLocation` or take the screenshot straight after moving.
- Maze layout tables are `walls[x][z][side]` with sides "N"/"E"/"S"/"W" (MazeLayout.DIRS: `{dx, dz, side, opposite}`), not numbers. Use `MazeLayout.DIRS` in tests that walk the maze, or every wall reads as open.
- Modules required from `execute_luau` are fresh copies, not the running game's. Reach live state through instances: attributes, or Studio-only hooks like `ServerStorage.DoorsTest` (a BindableFunction). On the client, door ghosts carry `Seen`/`RememberedShut` attributes, and the dev panel's `DevDoors` remote can be fired.
- The isometric camera sits 210 studs away, so sounds are heard from the camera's focus (see `SoundEffects`), not the camera.
- Player avatars here use AnimationConstraints and BallSocketConstraints rather than Motor6Ds. A Humanoid forces limbs to be non-colliding.

**Git**
- The public repo is https://github.com/alexander-m-lin/cruel-maze, and `main` is the only branch. Work each phase on a `phase-N` branch and merge it with `--no-ff` when its "done when" is met.
- Commits use the GitHub no-reply email set in the repo config. Keep it, so the user's personal email never goes public. Commit on your own after each meaningful change (on the current phase branch, place saved first); push only when asked.

**Assets:** uploaded textures and their asset IDs are documented in `assets/textures/*/README.md`, with the scripts that made them in `tools/textures/`. New uploads need Roblox moderation before they show for other players.

---

# Cruel Maze — Game Design Overview

## 1. Core Premise

**Cruel Maze** is an asymmetric, hero-based multiplayer maze tag game developed on Roblox, combining elements of Dead by Daylight, hero-based PvP games, and strategic maze manipulation.

The game features **3 survivors versus 2 monsters and 1 Maze Master**, for a total of six players.

Survivors navigate a dangerous, dynamically changing maze while collecting relics and avoiding capture. Monsters hunt survivors, assisted by a Maze Master who can manipulate the environment, deploy traps, and provide strategic support.

The central differentiator is the interaction between players physically navigating the maze and a Maze Master strategically controlling it.

The intended gameplay emphasizes:
- Navigation, exploration, and spatial reasoning.
- Chases, juking, ambushes, and tactical movement.
- Asymmetric characters with unique abilities.
- Team coordination and information sharing.
- Environmental manipulation and counterplay.
- Suspense, unpredictability, and emergent interactions.

## 2. Teams and Roles

### Survivors — 3 Players

Survivors must explore the maze, collect relics, evade monsters, and cooperate to complete their objectives.

Survivors have:
- Unique character identities and abilities.
- Limited information about unexplored areas.
- Movement, defensive, support, or information-gathering abilities.
- A limited number of lives, either individually or shared across the team (TBD).

Their main strategic decision is how to balance exploration, relic collection, evasion, and cooperation.

Splitting up allows faster objective completion but increases vulnerability to coordinated monster attacks.

### Field Monsters — 2 Players

Monsters physically navigate the maze and attempt to capture survivors through tagging.

Each monster has a unique identity, abilities, and playstyle.

Potential specializations include:
- Pursuit and mobility.
- Tracking and information gathering.
- Ambushes and area denial.
- Trapping and disruption.
- Coordination with the Maze Master.

Monsters are not intended to be individually overwhelming. Their effectiveness should depend partly on cooperation with each other and the Maze Master.

With only two field monsters against three survivors, the monster team must make meaningful decisions about where to concentrate pressure.

### Maze Master — 1 Player

The Maze Master is a strategic support/controller role with a top-down interface representing the maze.

Unlike the field monsters, the Maze Master does not physically chase survivors.

Instead, they manipulate the environment and assist allied monsters.

Potential capabilities:
- Open and close passages.
- Rearrange maze sections.
- Trigger environmental traps.
- Create or deny routes.
- Open shortcuts for allied monsters.
- Gather information using sensors or surveillance mechanisms.
- Coordinate ambushes and intercept escaping survivors.

**The Maze Master does not have omniscient vision.**

They may know:
- The overall maze layout.
- Allied monster locations.
- Relic locations and collection states.
- Current maze and trap configurations.

Survivor locations are only revealed through limited information sources, such as:
- Sightings by allied monsters.
- Triggered traps or sensors.
- Relic interactions.
- Character abilities.

Monster sightings could temporarily reveal survivor positions on the Maze Master's map, creating opportunities for coordinated pursuit.

The Maze Master should have meaningful strategic responsibilities even when no survivor is currently visible.

Environmental interventions should have constraints and opportunities for counterplay, rather than allowing unavoidable captures.

## 3. Match Objectives and Victory Conditions

### Survivor Victory

Survivors must collect **6 of 9 relics** scattered throughout the maze before the match timer expires.

These values are adjustable for balancing.

Having more available relics than required is intentional: survivors should have multiple viable paths to victory, preventing the monster team from simply defending a small set of mandatory objectives.

### Monster Victory

The monster team wins if:
- The timer expires before survivors collect enough relics.
- The survivor team runs out of lives.

The exact mechanics for tagging, incapacitation, respawning, and life allocation remain undecided.

### Objective Design

Relic placement should encourage exploration and dynamic movement around the map.

Possible mechanics include:
- Relics distributed across distinct maze regions.
- Some relic locations changing during a match.
- Relics becoming available or relocating based on game events.
- Anti-camping systems preventing monsters from permanently denying progression.

The monster team should be incentivized to actively hunt survivors rather than simply defend objectives.

## 4. Hero and Ability System

Survivors and field monsters each have distinct selectable characters.

Every character has:
- A recognizable visual identity.
- Unique active abilities.
- Potential passive abilities.
- Strengths and weaknesses that influence playstyle.
- Counterplay against opposing characters.

Potential ability categories include:
- Speed boosts and dashes.
- Stealth and temporary concealment.
- Tracking or revealing opponents.
- Deployable traps and area denial.
- Defensive abilities and escapes.
- Team support.
- Environmental interactions.

Abilities should encourage creative movement, positioning, and coordination.

### Blind Character Selection

Character selection is blind between opposing teams.

Survivors do not know which monster characters they face until they encounter them or discover identifying information during gameplay.

This is intended to create suspense and reward players who learn to recognize monster behaviors, visual cues, and abilities.

Character abilities should be identifiable and provide understandable counterplay once encountered.

Blind selection should not create matchups that are effectively unwinnable due to hard counters.

## 5. Maze Design and Manipulation

The maze is a central gameplay system rather than merely an arena.

It should support:
- Branching paths and interconnected corridors.
- Multiple routes between important areas.
- Opportunities for juking, ambushes, and escapes.
- Landmarks that help players build spatial understanding.
- Relics distributed throughout the environment.
- Strategically controllable doors, traps, and maze sections.

Maze Master interventions may change the maze during an active match.

This creates opportunities for:
- Closing an anticipated escape route.
- Opening a shortcut for a monster.
- Redirecting survivors into dangerous regions.
- Creating unexpected connections between corridors.
- Separating or reconnecting areas of the maze.

Maze manipulation must preserve valid routes to necessary objectives and should not create permanently unwinnable states.

Environmental changes should generally be communicated through visual or audio cues, giving attentive players opportunities to react.

The extent of procedural maze generation versus handcrafted modular layouts remains undecided.

## 6. Camera, Movement, and Visibility

The preferred camera is **fixed-angle overhead or isometric**, rather than first-person or close third-person.

The intention is to emphasize tactical navigation, ability usage, and spatial reasoning while avoiding excessive camera rotation.

### PC Controls

Tentative controls:
- WASD — Screen-relative movement.
- Mouse — Character facing and ability aiming.
- Left click — Primary action.
- Q/E — Character abilities.
- F — Interaction.

The camera remains stable independently of character facing.

The Maze Master uses a separate overhead interface with mouse selection and keyboard shortcuts for environmental controls.

### Visibility

Because an overhead camera can reveal more of the environment than a traditional third-person view, the game may use:
- Fog of war.
- Line-of-sight restrictions.
- Limited map knowledge.
- Character-specific vision abilities.
- Temporary reveals.

Players should not automatically receive information about unexplored or concealed areas simply because they are visible from the camera's perspective.

Navigation should require player decisions rather than unrestricted automatic pathfinding.

Controls should ultimately support PC, mobile, and other Roblox-supported devices.

## 7. Matchmaking and AI Bots

The intended experience is six human players, but the game should remain functional with fewer human participants.

Unfilled player slots can be occupied by AI-controlled characters.

Potential behavior:
- Matches can begin with as few as one human player.
- AI survivors explore, collect relics, and evade monsters.
- AI monsters track, pursue, and tag survivors.
- An AI Maze Master manipulates doors and traps using a simplified strategic policy.
- As human players become available, they replace bots between rounds or matches.
- Matchmaking prioritizes concentrating players into existing games.

Bots should support the core gameplay without requiring human-equivalent strategic intelligence.

AI participants should be identifiable as bots rather than deceptively presented as genuine players.

The game should also support friends joining together and coordinating as a party.

## 8. Multiplayer Dynamics

The game is designed around asymmetric cooperation.

### Survivor Coordination

Survivors choose whether to:
- Split up and collect relics more quickly.
- Stay together for protection.
- Distract monsters while teammates complete objectives.
- Share information about sightings and safe routes.
- Use complementary hero abilities.

### Monster Coordination

Monsters choose whether to:
- Pursue separate survivors.
- Cooperate to capture one target.
- Patrol important regions.
- Coordinate with the Maze Master to create ambushes.
- Abandon pursuits to defend threatened objectives.

### Maze Master Coordination

The Maze Master interprets incomplete information and decides where environmental interventions will be most valuable.

Communication tools such as map pings, sightings, and quick signals should allow meaningful teamwork without requiring voice chat.

The ideal gameplay produces moments where players outmaneuver opponents through prediction, positioning, communication, and coordinated ability usage.

## 9. Monetization

The proposed monetization model centers on character access, customization, and selection preferences.

Potential revenue sources:

### Character Skins
- Alternative character appearances.
- Cosmetic visual effects.
- Animations, emotes, and victory celebrations.

### Premium Characters
- Unlockable survivor and monster characters.
- Characters may be purchased with Robux or earned through gameplay.
- Premium characters should provide different playstyles rather than strictly superior power.

### Role and Character Selection Preferences
- Potential paid priority for preferred roles or characters.
- May be implemented through preferences, weighted selection, or other mechanisms.
- Must account for conflicting preferences, especially the single Maze Master slot.

Exact monetization mechanics are not finalized.

## 10. Technical Environment

Platform: Roblox  
Language: Luau  
Editor: Roblox Studio  
AI development assistant: Claude Code  
Integration: Roblox Studio MCP and Script Sync  
Version control: Git

The game should use server-authoritative logic for:
- Match state.
- Role assignment.
- Tag and capture validation.
- Relic collection.
- Maze modifications.
- Ability validation and cooldowns.
- Victory conditions.

Client-side systems handle input, UI, camera, animations, visual effects, and presentation.

## 11. Intended Player Experience

Cruel Maze should feel like a tense, tactical multiplayer contest in which no player has complete control over the situation.

Survivors should experience the uncertainty of exploring a dangerous maze, the excitement of discovering relics, and the satisfaction of outsmarting pursuing monsters.

Monsters should experience the thrill of tracking opponents, predicting their movements, and coordinating ambushes.

The Maze Master should experience the satisfaction of manipulating the battlefield, interpreting incomplete information, and enabling clever plays by allied monsters.

The game's most memorable moments should emerge naturally from interactions between movement, information, abilities, and changing maze geometry.

**The central design principle is that victories and defeats should arise from meaningful player decisions rather than arbitrary, unavoidable outcomes.**

## 12. Unresolved Design Decisions

The following are intentionally left open:

- Match duration and survivor life counts.
- Exact capture and respawn rules.
- Hero roster size and individual abilities.
- Maze size, procedural generation, and layout rules.
- Maze Master resources, cooldowns, and intervention limits.
- Relic relocation and anti-camping mechanics.
- Vision and fog-of-war implementation.
- Bot sophistication and matchmaking behavior.
- Progression and unlock systems.
- Final monetization details.

These are design parameters to be refined, not settled specifications.
