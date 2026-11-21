# Cruel Maze Roadmap

How to get from the current maze prototype to the game described in [CLAUDE.md](../CLAUDE.md).
Shareable page version: https://claude.ai/artifact/24EfH6ojjcwjumoSHATgF7 (private; share from its Share menu).

Tick a phase's box when its "Done when" is met. Update this file as plans change.

## Duration estimates

Estimated 2026-11-18, after Phase 1. Hours of active work together, including playtesting in
Studio; not counting waiting (asset approval, finding testers). Phase 0 and 1 showed that building
the planned features is fast and the time goes into playtest-driven changes and polish, so the
ranges are wide: the low end assumes the first design mostly works, the high end allows Phase 1's
level of polish.

| Phase | Estimate | What drives it |
|---|---|---|
| 2. Maze that changes mid-match | 3-6 h | Mostly technical: fog, monster routing and line of sight all assume fixed walls |
| 3. Human roles and the Maze Master | 10-20 h | Biggest design risk; finding what's fun for the Maze Master takes several rounds; needs 3+ real players to test |
| 4. Heroes and abilities | 10-20 h | The ability system is quick; designing and balancing 4-5 distinct characters is open-ended |
| 5. Bots and matchmaking | 8-15 h | Bot survivors and Maze Master are harder than the monster AI; matchmaking needs the game published to test |
| 6. Content, platforms, performance | 10-25 h | Elastic: a fog rewrite for phones, mobile and controller controls, as much art and audio as wanted |
| 7. Progression and monetization | 6-12 h | Well-trodden ground; some setup on the Creator Dashboard; purchases need testing |

Total: roughly 50-100 hours to the full design; about 25-45 hours to a playable 3v2+1 game with
heroes (through Phase 4).

Actual so far:
- Phase 0: about 30 minutes of building (branch 12:53 → last commit 13:19 on 2026-11-18), plus two 2-player test sessions and design decisions. The 1-week guess was far too high: with Claude Code, writing code is fast, and the time goes into testing, feel and decisions. Phase 1 (more design decisions) will be a better benchmark before estimating the rest.
- Phase 3: 2026-11-19 15:20 → 2026-11-20 (12 commits on `phase-3`, over two days with breaks). As predicted, most of it went on playtest-driven additions rather than the planned build: survivor bots pulled forward, wards and haunt for the Maze Master's vision, a lobby, the speed check, and bugs found on the published server (streaming, draw distance, the minimap's EditableImage setting).
- Phase 1: about 6.5 hours (13:54 → 20:16 on 2026-11-18, 29 commits). The core rules (relics, spawn rooms, lives, timer) took about 35 minutes. The rest went on reworking rules after playtesting (relic barriers → vision rings, click-to-collect) and on polish that wasn't in the plan: textures, sounds and music, the kill animation, the minimap, skull relics. Building the planned features is quick; iterating on feel and adding polish is where the time goes.

## Where the prototype stands (2026-11-20, after Phase 3)

Working: 3 survivors vs 2 monsters and a Maze Master, any slot filled by a bot (survivor bots, AI monsters, a door AI for the Maze Master). Human monsters lunge to catch; the monster side shares vision; the Maze Master pans the whole map and spends dark mana on doors, wards, haunt, false relics and crushing walls. Doors and crushing walls built into each generated maze. A lobby between matches, a server-side speed check, and a private published test build.

Not started: characters and abilities, matchmaking beyond the one-server lobby, saved progress and purchases, mobile controls.

### Earlier (2026-11-18, after Phase 1)

Working: a full match against AI monsters. Survivors collect 6 of 9 relics within 4 minutes with 3 lives each, capture spawn rooms and choose where to respawn; two AI monsters roam (spreading out), chase and kill. Also: generated mazes with junctions and loops; fixed isometric camera; mouse facing with direction-based speed; fog of war shared between teammates, with vision rings around spotted relics; a minimap; textured temple walls and floor; sound effects and music.

Not started: monster and Maze Master roles, a maze that changes mid-match, characters and abilities, bots for other roles, matchmaking, saved progress and purchases.

## Phases

### [x] 0. Foundation and refactor (done 2026-11-18)
Today the game is one round loop with a single global monster and a maze that never changes. Restructure first, without adding features.
- Match state machine: lobby → role assignment → match → results
- Shared modules in ReplicatedStorage (needs a new Script Sync folder) and server-authoritative RemoteEvents
- WASD movement relative to the screen, with the character facing the mouse
- Studio's multi-client local test servers set up for multiplayer testing

**Done when:** the current game runs on the new structure and plays the same.

**Outcome:** `Match`, `MonsterAI`, `Config`, `Net`, `Controls` (see README). Added along the way from playtesting: slower movement away from your facing (100° full-speed cone, 80% sides, 45% backwards), separate spawn spots, and fog of war shared between teammates. Each round now opens with a 3-second frozen countdown.
**Deferred:** server-side checks on movement speed (clients apply the facing slowdown; check it in Phase 3; done in Phase 3, `SpeedCheck`) and touch/gamepad aiming (Phase 6).

### [x] 1. Core loop: survivors against a bot monster (done 2026-11-18)
The first build that plays like Cruel Maze. It answers the biggest question cheaply: is collecting relics while being hunted fun?
- 9 relics replace the beacon; survivors need 6
- Match timer, lives, capture and respawn rules, win and loss screens
- HUD for relics collected, time left and lives
- Several survivors against the existing AI monster, then two of them

**Reuses:** maze generator, fog, monster AI and body.
**Done when:** a full match can be won or lost, and playtests say whether the loop is fun.

**Outcome:** a match is won by collecting 6 of 9 relics within 4 minutes, and lost when time runs out or every survivor is out of lives (3 each). All three endings tested, plus a 2-player session ("gameplay feels good"). New modules: `MazeLayout`, `Objectives`, `SpawnPicker`, `Minimap`, `FogState`, `RelicEffects`, `SoundEffects`, `Sounds` (see README).
- Relics sit in junction cells at least 4 cells apart, with at most 1 in the start room's quarter. The first plan had barriers keeping monsters out of relic rooms; playtesting replaced them: once spotted, a relic keeps the area around it visible to the team, so camping it is visible. Collecting is a left-click (with a prompt), then 3 seconds standing on it; leaving or being caught resets it, the monster turning up doesn't.
- Spawn rooms: the start room plus 2 more, each in its own quarter of the maze; monsters can't enter; walking in captures one for the team; after being caught you pick a captured room on a map.
- Two AI monsters that spread out while roaming. A caught survivor is lifted, struggles, and is torn apart; respawning waits for that to finish.
- Polish beyond the plan: jungle-temple wall panels with matching texture variations, a toned-down flagstone floor, skull relics, sound effects and music, a minimap, backwards running, the relic-collecting beam.

**Deferred:** a proper results screen (a message and a sting for now); floor texture variations; mobile controls (Phase 6).

### [x] 2. A maze that changes mid-match (done 2026-11-19)
The Maze Master depends on this, and several systems assume walls never move.
- Doors, passages that open and close, swappable maze sections
- A check that every needed relic stays reachable, so no change makes the match unwinnable
- Visual and audio warnings when the maze changes

**Must rework:** the fog marks wall tiles once at build time; the monster plans routes from a fixed wall table; line-of-sight checks don't know about doors.
**Done when:** doors can open and close mid-match and fog, routes and sight all stay correct.

**Decisions (2026-11-19):**
- Doors only; swappable sections wait until doors prove fun.
- Doors may close in any combination: the maze is generated so every cell, relic and spawn room stays reachable with *every* door closed (monsters too, outside spawn rooms). Doors redirect and pseudo-trap; they never block relics or truly trap anyone. Some doors sit in open corridors (start open), some replace walls (start closed, shortcuts when opened).
- Until the human Maze Master (Phase 3): a simple AI changes doors on a timer (Config.DOOR_AI_*; 3 doors every 5–10 s while testing, per-door cooldown), plus a dev panel to toggle any door.
- Doors look like walls; the tell is their two posts, a little darker than the walls (`MazeBuilder.DOOR_LOOK = "subtle"`; `"dev"` makes them rusty metal).
- Warning: ~2 s of rumbling (the slab shakes harder and harder and dust rises; a sunk door peeks out of the floor to rattle) with a rumble heard nearby, plus a faint maze-wide sound, then ~1 s to move. A player standing in a closing door is nudged out to the nearer side.
- Monsters obey doors and re-plan when one changes. Players can't work doors yet.
- Fog and minimap memory show a door as last seen until it's seen again.

**Outcome:** doors only (`Doors`, `DoorView`, `DevDoors`; placement in `MazeLayout.placeDoors`). About 9 corridor and 4 shortcut doors per maze. Tested: 200 generated mazes stay connected with every door shut; 69 door changes in 90 s with no monster ever passing a shut door; sight blocked only by shut doors; a closing door pushes a player out; fog, minimap and relic rings remember doors as last seen, including through a teammate's eyes (2-player test).
- The door look became the "subtle" one: wall texture, slightly darker posts. The warning became a rumble (the slab shakes, dust rises, a door down in the floor peeks out) instead of a glow.
- The AI pace (3 doors every 5–10 s) is a testing value; the human Maze Master replaces the AI in Phase 3.

**Deferred:** swappable maze sections; a monster standing in a closing door is handled like a player but wasn't seen in testing.

### [x] 3. Human roles and the Maze Master (done 2026-11-20)
The feature that makes Cruel Maze different, and the biggest design risk. Get a rough, playable Maze Master in front of people early. Can overlap with Phase 2: a Maze Master who can only work doors is enough to test the role.
- Role assignment: 3 survivors, 2 monsters, 1 Maze Master
- Player-controlled monsters, with the AI monster kept as the bot
- Monster vision rules; sightings feed a shared team picture
- Maze Master: top-down interface, door and trap controls with cooldowns and resources, sensors
- The Maze Master sees survivors only through sightings, traps, sensors and relic events

**Done when:** a 3 v 2 + 1 match runs with humans, and the Maze Master has useful things to do even when no survivor is visible.

**Build for mobile from here on** (the plan is under Phase 6):
- Facing comes from an *aim direction* that each device supplies (mouse, touch, gamepad), not straight from the mouse. Abilities aim along it too.
- Every action has a button that can be tapped, not only a key. No hover-only interactions, including in the Maze Master's interface.

**Decisions (2026-11-19):**
- **Roles:** random for now; bots fill empty slots (AI monsters; the door AI stands in for a missing Maze Master). A Studio-only role picker for testing with 1–2 people. Preferences and priority come later (Phase 7).
- **Human monsters catch by lunging:** left-click lunges a short way; a hit catches. Short wind-up, cooldown after a miss, so survivors can dodge. Base speed about equal to survivors (the facing rule applies). The AI keeps its chase speed-up as the bot. Monsters can't enter spawn rooms.
- **Vision:** monsters have the same fog and cone as survivors, shared within the monster team. The Maze Master shares the monster team's vision. Apart from that, the Maze Master knows the whole layout, the live state of doors and traps, and every relic (location and whether collected). Monsters see a relic once their team has seen it. No sighting markers for now: see whether the overhead view gives enough information.
- **The Maze Master's view:** the same isometric camera, free to pan, no character in the maze. The layout shows as explored everywhere; the monster team's sight shows bright; survivors appear only where the team sees them.
- **Dark mana:** the Maze Master's energy, plus a cooldown per tool. Starting numbers: pool 100, +5/s; door 10 (1 s cooldown, plus the 20 s per-door cooldown), false relic 30 (5 s), crushing wall 50 (30 s).
- **Tools** (a baseplate for later design work):
  - *Doors:* the Phase 2 doors, worked by the Maze Master instead of the AI.
  - *False relics:* placed on an empty junction cell (not next to a real relic or spawn room). Indistinguishable from a real relic except that its red eyes go out for a split second every ~5 s, so careful players can spot one. A survivor near one (~15 studs, in line of sight) is revealed to the monster team; one who clicks it is revealed for 5 s and slowed to ~40% for 3 s, sees a red screen border and "FALSE RELIC", and the false relic is used up. At most 2 per match in total.
  - *Crushing walls:* built into the generated maze like doors (pairs of walls along straight corridor cells, looking like normal walls). The Maze Master triggers one: ~2 s rumble (like doors), a ~0.3 s slam, then ~1 s to slide back. Survivors caught between lose a life; monsters are unaffected. Letting the Maze Master place them can be explored later.

**Added from testing (2026-11-19):** basic survivor bots pulled forward from Phase 5, so matches have survivors to hunt with few people (roam, collect relics in sight, flee to a spawn room on seeing a monster); Maze Master mouse-wheel zoom; a placement marker for false relics; false relics glow red for the monster side; the Maze Master has a vision ring round every relic from the start (as survivors do once they've spotted one).

**Maze Master vision (2026-11-20):** testing found the Maze Master starved of information, so two more tools (still a baseplate, not a full kit) and fixed sight:
- *Wards* (15 mana, 4 s): a floating eye placed in an open cell (not a spawn room or relic cell); the monster side sees all round it (22 studs, walls block). Up to 3 at a time, the oldest fading. Survivors see one like anything else and, once spotted, it stays shown to them. A survivor destroys one by standing within 8 studs and holding for 1.5 s (the relic beam); the monster side sees a pulsing ring where it is meanwhile.
- *Haunt* (20 mana, 15 s): on a survivor the monster side can see right now (checked on the server against every sight source). For 3 s they're revealed and their vision cone counts as monster-side sight. They get a faint purple screen edge and a whisper.
- *Crushing walls* give the monster side permanent sight of their cell plus 6 studs past it each way.
- Fixed along the way: with streaming on, the Maze Master (no character) received no survivor bodies at all. The server now gives them a streaming focus in the middle of the maze.

**Also added before merging (2026-11-20):** a bare-bones lobby between matches (who's in, a preferred role each, a Start button; matches return to it), developer controls for the experience's owner in the published game, and a server-side speed check (`SpeedCheck`: an allowance refilling at base speed +15%, banking 1.5 s for lag; overspenders are pulled back). The Maze Master's zoom-out is capped at 1.6x: further, low graphics settings stopped drawing far walls. The game is published privately as "Cruel Maze 0.1" for testing.

**After merging (2026-11-20, before Phase 4):** dark mana switched off for now (`Config.DARK_MANA_ENABLED`; tools have cooldowns only, the code stays). Wards' cap raised to 4. An AI Maze Master (`MazeMasterAI`, pulled forward from Phase 5) replaces the random door AI when nobody plays the role: it uses the same tools object as a person and only knows what the monster side sees. It shuts open doors 2-5 cells ahead of chased survivors (otherwise shifts doors near sightings), sets off crushing walls when a seen survivor will be between them as they slam, haunts on cooldown (preferring a survivor no monster is near), keeps wards out at unwatched junctions near sightings or on the way to relics (moving one at most every 8 s once all 4 are out), and places both false relics at the start, at least 6 cells from any spawn room.

**Outcome:** done when "a 3 v 2 + 1 match runs with humans and the Maze Master has useful things to do even when no survivor is visible". Tested with every role played by a person in Studio's multi-client test and in the published game, with bots filling the other slots; a full six-human match is still to come (no testers online yet) and should be the first thing played in Phase 4's testing. "Sensors" became wards, haunt and crushing-wall sight. Carried forward: the flying-bots note below, and Phase 5's lobby work now starts from the bare-bones lobby.

**Open (2026-11-19):** once, as a survivor, the user saw both survivor bots fly up off-screen at the same moment (a monster was nearby; not the kill animation). Not reproduced. SurvivorBot now puts a bot back if it goes more than 20 studs above or 5 below the floor, warns in the output, and sets a `Rescued` attribute. Watch for that warning in tests.

**Build order:** roles and the role picker → human monsters (body, lunge, spawn-room barrier) → team vision for monsters and the Maze Master (enemies hidden by fog) → the Maze Master's camera and interface with dark mana and doors → false relics → crushing walls → 3 v 2 + 1 tests.

### [ ] 4. Heroes and abilities

**Decisions so far (2026-11-20):**
- Survivor kits: a primary ability on the right mouse button, a secondary on Q, an ultimate on E. Left click stays each role's own action (collecting relics; a monster's lunge).
- First hero: **Sara, the Cryptraider** (an explorer with a whip). Whip (5 s, 39 studs; tuned up from 30): the first wall or relic pulls her to it, a teammate is pulled to her, a monster is pulled to her and stunned for 1 s. Monsters are hit within 5 studs of the lash and teammates within 4 (not through walls). Treasure hunt (15 s): the nearest relic her team hasn't spotted, real or false, within 110 studs, is spotted. Flourish (60 s): 1 s standing still spinning the whip; 0.5 s in, monsters within 20 studs are stunned for 3.5 s (tuned from an instant 14-stud 1 s stun, then a stun at the end of the 1 s cast, which felt too punishing).
- Character models come later: the abilities, the whip and the animations first (Sara is the default avatar).
- STUN is a shared mechanic (can't move, lunge or catch); crushing walls stun monsters caught between them. PULL is shared too (players, bots and monsters).
- Until there's a character select, every survivor plays Sara (`Config.DEFAULT_SURVIVOR_HERO`). Bots don't use abilities yet.

**Tuning from testing (2026-11-20):** crushing walls' cooldown 30 s -> 10 s; a crushed survivor's view stays on the shut walls for 1.5 s (`Config.CRUSHED_LINGER`) before the spawn picker, and they no longer die the default Roblox way (no "oof"); monsters mid-kill can't be stunned or pulled.

**Notes from testing, before heroes (2026-11-20):** haunt (AI) prefers survivors near a monster; destroying a ward takes 3 s with a progress bar like a relic's, and the AI won't put a ward back where one was just destroyed for 10 s; anything that reveals a survivor also gives the monster side a small ring of sight round them (`Config.REVEAL_VISION_RADIUS`), and AI monsters go for revealed survivors within sight range, walls or not. The match's per-frame systems now run separately, so an error in one can't stop the others.

**Phase 4 notes (2026-11-20):** AI monsters treat any survivor their side can see (another monster's cone, a ward, a crushing wall, a relic ring, a haunt, a reveal: Match's `monsterSideSees`) as seen within `Config.REVEALED_CHASE_RANGE` (120 studs, straight line; their own sight is 60), walls or not. Monster players now also get vision rings round false relics and round real relics their side has spotted (the Maze Master still has every relic's). The human monster's lunge reach is 9 studs (was 5) while the monster is a stand-in, and it no longer catches through walls. A whip that hits nothing is ready again in 2 s (5 s otherwise). With no character, survivors now watch a bot teammate if no person is left. Wards see 50 studs in line of sight (was 22), to help the monster side while the game feels survivor-sided. Spawn rooms renamed **sanctuaries** (in code and in game). Survivors inside one are invisible to the monster side (server sight checks, haunt, fog, minimap, reveal rings). The start sanctuary is 3x3 with 3 exits (others 2x2 with 2-3), and exits are spread out by walking distance: from the cell just outside one exit to the cell just outside another is at least 6 steps through the maze (`Config.SANCTUARY_EXIT_SPACING`), not through any sanctuary, even with every door open (shortcut doors that would undercut it aren't placed). Exits are picked by trying every set; a maze whose start can't fit 3 is regenerated (up to 10 tries; about 7 in 10 mazes fit first time). Aim: sanctuaries can't be camped even with vision on them. Checked on 200 generated mazes: every cell reachable, exit gaps never under 6 with all doors open, about 12.5 doors per maze (of 14 wanted).

**Maze Master made easier (2026-11-21):** doors, crushing walls and survivors in sight are always outlined (purple ready, grey not) and used by clicking them; hovering shows the ability's name in a box, or a radial clock while it recharges (a door's own 20 s rest counts). Only wards and false relics keep buttons (keys 1-2), as placement modes (right-click / Esc cancels). Haunt now also slows its target to 70% (`Config.HAUNT_SLOW`). Placement previews use the sanctuaries' real bounds (the 3x3 start). Then: doors and crushing walls have no shared cooldown, only each one's own rest (doors 20 s, crushing walls 10 s, `Config.MAZE_MASTER_CRUSHER_COOLDOWN`); false relics have no cooldown (2 a match); crushing walls are outlined on their slabs; a survivor being killed is no longer outlined (the outline grew round the scattering pieces). Survivor bots leaving a sanctuary pick an exit with noise (favouring ones away from the monster they fled, not the one they last used) and wait 4-8 s instead of exactly 4, so they don't loop out into the same monster. Ward destroy time 3 → 2 s (the user's tweak).
- Ability system with server-checked cooldowns and use (Q, E, left click, F)
- A first roster: 2–3 survivors and 2 monsters with clearly different counterplay
- Character select where each team can't see the other's picks
- Recognizable cues so survivors can tell which monster they're facing

**Done when:** every pick has a role in a match and no matchup is effectively unwinnable.

### [ ] 5. Bots and matchmaking
Lets a match start with one human player and fill up as people arrive.
- AI survivors that explore, collect relics and evade
- A simple AI Maze Master working doors and traps (done early: `MazeMasterAI`, 2026-11-20)
- Bots fill empty slots, are labelled as bots, and give way to humans between matches
- Lobby, parties, and grouping players into existing servers. A bare-bones lobby already exists (Phase 3). Likely shape (discussed 2026-11-20): a lobby place where players gather, party up and queue, and a match place started as a reserved server, with players teleported back afterwards; plus a separate private test experience so test builds never reach the public game.

**Done when:** a solo player gets a full match, and friends can queue together.

### [ ] 6. Content, platforms and performance
- Art and audio passes; landmarks that help players navigate
- Mobile and controller support (see the plan below)
- A lighter fog system: the current one creates about 25,000 parts on each player's device, likely too heavy for phones
  - Done early (2026-11-19): line of sight casts a fan of rays (about 106 per view) instead of one ray per tile (about 1,150), and the pocket fill only searches next to newly revealed tiles. In Studio: rays per second about 18,000 → 1,600, a fog update about 4–5 ms → 1.1–1.6 ms, with ~0.1% of tiles differing. Still to do: the parts themselves (see-through sheets), and a test on a real phone.

**Why mobile matters (2026-11-19):** most Roblox players are on phones and tablets, and a 6-player match needs a big pool of players. Survivors and monsters (5 of 6 slots) must play well on touch; the Maze Master can be PC-first at launch but still needs tappable controls. Controller is a small share: keep it workable, don't design around it. Performance (the fog) and screen space (minimap, HUD, touch targets) matter as much as the controls.

**Planned touch controls** (after Wild Rift and Brawl Stars, where the ability buttons are the aim sticks, so the right thumb never sits on a stick doing nothing):
- Left thumb: a floating movement stick. With the right thumb idle, you face the way you move (full speed).
- Right thumb: the primary action button doubles as the look stick. Tap it for the action (e.g. collect a relic); drag it to look that way while held. Looking away from where you move costs speed as on PC (the facing speed rule stays: it stops "turret" vision and gives chases texture).
- Ability buttons in an arc around it: tap to quick-cast (auto-aimed), drag to aim and release to cast, drag to a cancel zone to cancel. While aiming, you face the aim.
- Open: after you let go, does facing stay where you looked (like PC) or snap back to your movement direction?

### [ ] 7. Progression and monetization
- Saved player profiles, unlocks and premium characters
- Skins, game passes and Robux products
- Role or character priority that handles the single Maze Master slot fairly

**Done when:** players keep progress between sessions and can buy cosmetics and characters.

## Where the open design questions get answered

| Phase | Open questions it forces (from CLAUDE.md section 12) |
|---|---|
| 1 | Match length, survivor lives, capture and respawn rules, maze size |
| 2 | Procedural versus handcrafted layouts; relic relocation and anti-camping |
| 3 | Maze Master resources, cooldowns and intervention limits; how vision is shared |
| 4 | Roster size and individual abilities |
| 5 | How capable bots need to be; matchmaking behaviour |
| 7 | Progression, unlocks and final monetization details |

## Notes on order
- Phase 1 comes before the maze rework on purpose: if the chase-and-collect loop isn't fun, nothing built on top of it will save it.
- Keep what works. The AI monster becomes the monster bot, and the fog and line-of-sight code carries over. Only the assumptions that walls never change need replacing.
