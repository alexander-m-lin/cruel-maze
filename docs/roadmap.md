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

### [ ] 2. A maze that changes mid-match
The Maze Master depends on this, and several systems assume walls never move.
- Doors, passages that open and close, swappable maze sections
- A check that every needed relic stays reachable, so no change makes the match unwinnable
- Visual and audio warnings when the maze changes

**Must rework:** the fog marks wall tiles once at build time; the monster plans routes from a fixed wall table; line-of-sight checks don't know about doors.
**Done when:** doors can open and close mid-match and fog, routes and sight all stay correct.

### [ ] 3. Human roles and the Maze Master
The feature that makes Cruel Maze different, and the biggest design risk. Get a rough, playable Maze Master in front of people early. Can overlap with Phase 2: a Maze Master who can only work doors is enough to test the role.
- Role assignment: 3 survivors, 2 monsters, 1 Maze Master
- Player-controlled monsters, with the AI monster kept as the bot
- Monster vision rules; sightings feed a shared team picture
- Maze Master: top-down interface, door and trap controls with cooldowns and resources, sensors
- The Maze Master sees survivors only through sightings, traps, sensors and relic events

**Done when:** a 3 v 2 + 1 match runs with humans, and the Maze Master has useful things to do even when no survivor is visible.

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
- Mobile and controller support
- A lighter fog system: the current one creates about 25,000 parts on each player's device, likely too heavy for phones

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
