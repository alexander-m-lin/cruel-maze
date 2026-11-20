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
- Phase 1: about 6.5 hours (13:54 → 20:16 on 2026-11-18, 29 commits). The core rules (relics, spawn rooms, lives, timer) took about 35 minutes. The rest went on reworking rules after playtesting (relic barriers → vision rings, click-to-collect) and on polish that wasn't in the plan: textures, sounds and music, the kill animation, the minimap, skull relics. Building the planned features is quick; iterating on feel and adding polish is where the time goes.

## Where the prototype stands (2026-11-18, after Phase 1)

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
**Deferred:** server-side checks on movement speed (clients apply the facing slowdown; check it in Phase 3) and touch/gamepad aiming (Phase 6).

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

### [ ] 3. Human roles and the Maze Master
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

**Build order:** roles and the role picker → human monsters (body, lunge, spawn-room barrier) → team vision for monsters and the Maze Master (enemies hidden by fog) → the Maze Master's camera and interface with dark mana and doors → false relics → crushing walls → 3 v 2 + 1 tests.

### [ ] 4. Heroes and abilities
- Ability system with server-checked cooldowns and use (Q, E, left click, F)
- A first roster: 2–3 survivors and 2 monsters with clearly different counterplay
- Character select where each team can't see the other's picks
- Recognizable cues so survivors can tell which monster they're facing

**Done when:** every pick has a role in a match and no matchup is effectively unwinnable.

### [ ] 5. Bots and matchmaking
Lets a match start with one human player and fill up as people arrive.
- AI survivors that explore, collect relics and evade
- A simple AI Maze Master working doors and traps
- Bots fill empty slots, are labelled as bots, and give way to humans between matches
- Lobby, parties, and grouping players into existing servers

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
