# Cruel Maze Roadmap

How to get from the current maze prototype to the game described in [CLAUDE.md](../CLAUDE.md).
Shareable page version: https://claude.ai/artifact/24EfH6ojjcwjumoSHATgF7 (private; share from its Share menu).

Tick a phase's box when its "Done when" is met. Update this file as plans change.

## Duration estimates

Best guesses, in **full-time weeks for one developer working with Claude Code**. Working part-time stretches the calendar time accordingly (about double at 20 hours a week). The ranges are wide on purpose: the biggest unknowns are how many playtest-and-revise rounds each phase needs and how much art and animation the characters need.

| Phase | Estimate |
|---|---|
| 0. Foundation and refactor | 1 week |
| 1. Core loop | 2–3 weeks |
| 2. A maze that changes mid-match | 2–4 weeks |
| 3. Human roles and the Maze Master | 4–6 weeks |
| 4. Heroes and abilities | 4–8 weeks |
| 5. Bots and matchmaking | 4–6 weeks |
| 6. Content, platforms and performance | 4–8 weeks, then ongoing |
| 7. Progression and monetization | 2–4 weeks |
| **Total** | **about 23–40 weeks (6–10 months full-time)** |

A playable 3 v 2 + 1 match with humans (end of Phase 3) is about 9–14 weeks away.

## Where the prototype stands (2026-11-18)

Working: generated mazes with lots of junctions and loops; fixed isometric camera; fog of war with line of sight; AI monster with route planning, sight and hearing, ramping chase speed; rigged monster with code-driven animation; smooth monster movement on every screen.

Not started: teams and roles, relics and match rules, a maze that changes mid-match, characters and abilities, bots for other roles, matchmaking, saved progress and purchases.

## Phases

### [ ] 0. Foundation and refactor (1 week)
Today the game is one round loop with a single global monster and a maze that never changes. Restructure first, without adding features.
- Match state machine: lobby → role assignment → match → results
- Shared modules in ReplicatedStorage (needs a new Script Sync folder) and server-authoritative RemoteEvents
- WASD movement relative to the screen, with the character facing the mouse
- Studio's multi-client local test servers set up for multiplayer testing

**Done when:** the current game runs on the new structure and plays the same.

### [ ] 1. Core loop: survivors against a bot monster (2–3 weeks)
The first build that plays like Cruel Maze. It answers the biggest question cheaply: is collecting relics while being hunted fun?
- 9 relics replace the beacon; survivors need 6
- Match timer, lives, capture and respawn rules, win and loss screens
- HUD for relics collected, time left and lives
- Several survivors against the existing AI monster, then two of them

**Reuses:** maze generator, fog, monster AI and body.
**Done when:** a full match can be won or lost, and playtests say whether the loop is fun.

### [ ] 2. A maze that changes mid-match (2–4 weeks)
The Maze Master depends on this, and several systems assume walls never move.
- Doors, passages that open and close, swappable maze sections
- A check that every needed relic stays reachable, so no change makes the match unwinnable
- Visual and audio warnings when the maze changes

**Must rework:** the fog marks wall tiles once at build time; the monster plans routes from a fixed wall table; line-of-sight checks don't know about doors.
**Done when:** doors can open and close mid-match and fog, routes and sight all stay correct.

### [ ] 3. Human roles and the Maze Master (4–6 weeks)
The feature that makes Cruel Maze different, and the biggest design risk. Get a rough, playable Maze Master in front of people early. Can overlap with Phase 2: a Maze Master who can only work doors is enough to test the role.
- Role assignment: 3 survivors, 2 monsters, 1 Maze Master
- Player-controlled monsters, with the AI monster kept as the bot
- Monster vision rules; sightings feed a shared team picture
- Maze Master: top-down interface, door and trap controls with cooldowns and resources, sensors
- The Maze Master sees survivors only through sightings, traps, sensors and relic events

**Done when:** a 3 v 2 + 1 match runs with humans, and the Maze Master has useful things to do even when no survivor is visible.

### [ ] 4. Heroes and abilities (4–8 weeks)
Roughly 1–2 weeks for the ability system and character select, then about a week per character including art and animation.
- Ability system with server-checked cooldowns and use (Q, E, left click, F)
- A first roster: 2–3 survivors and 2 monsters with clearly different counterplay
- Character select where each team can't see the other's picks
- Recognizable cues so survivors can tell which monster they're facing

**Done when:** every pick has a role in a match and no matchup is effectively unwinnable.

### [ ] 5. Bots and matchmaking (4–6 weeks)
Lets a match start with one human player and fill up as people arrive.
- AI survivors that explore, collect relics and evade
- A simple AI Maze Master working doors and traps
- Bots fill empty slots, are labelled as bots, and give way to humans between matches
- Lobby, parties, and grouping players into existing servers

**Done when:** a solo player gets a full match, and friends can queue together.

### [ ] 6. Content, platforms and performance (4–8 weeks, then ongoing)
- Art and audio passes; landmarks that help players navigate
- Mobile and controller support
- A lighter fog system: the current one creates about 25,000 parts on each player's device, likely too heavy for phones

### [ ] 7. Progression and monetization (2–4 weeks)
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
