-- Settings shared by the server and every player's computer. Tune the game here.
-- Anything both sides need to agree on lives here, so it's only written down once.

local Config = {}

-- Players
Config.PLAYER_SPEED = 24          -- walk speed in studs per second (Roblox's default is 16)

-- Moving in a different direction from the way you face (aiming with the mouse) slows you down.
-- Measured as the angle between your movement and your facing:
Config.FACING_FULL_CONE  = 100    -- this wide a cone in front of you (±50°): full speed
Config.FACING_SIDE_CONE  = 40     -- then this many degrees on each side (50°–90°): slightly slower...
Config.FACING_SIDE_SPEED = 0.8    -- ...at this fraction of full speed
Config.FACING_BACK_SPEED = 0.45   -- the rest (backwards, 90°–180°): this fraction of full speed
Config.FACING_BLEND      = 6      -- degrees over which each change blends in, so speed doesn't snap

-- What a survivor can see (the fog uses this; the server uses it to decide when a relic is spotted)
Config.VIEW_RANGE = 80            -- studs
Config.VIEW_CONE  = 110           -- total width of the vision cone, in degrees
Config.VIEW_NEAR  = 12            -- you always see this close, even behind you

-- Camera: direction from the player to the camera. (-1, 1, -1) = true isometric (45° around,
-- ~35° down). The fog uses this too, to keep fog between the camera and you see-through.
Config.CAMERA_DIRECTION = Vector3.new(-1, 1, -1).Unit

-- Match flow
Config.MIN_PLAYERS = 1            -- a match starts once this many players are in the server
Config.COUNTDOWN = 3              -- seconds of "Starting in..." before each match
Config.MATCH_TIME = 240           -- seconds survivors have to collect their relics (4 minutes)
Config.RESULTS_TIME = 6           -- seconds the result is shown before the next match
Config.MONSTER_COUNT = 2          -- monsters per match: players in the Monster role, the rest AI (they spread out when roaming)

-- Relics: survivors win by collecting RELICS_NEEDED of the RELIC_TOTAL in the maze
Config.RELIC_TOTAL = 9
Config.RELICS_NEEDED = 6
Config.RELIC_SPACING = 4          -- minimum distance between relics, in maze cells (shrinks a little if they can't fit)
Config.RELICS_NEAR_START = 1      -- at most this many relics in the start sanctuary's quarter of the maze
Config.RELIC_COLLECT_TIME = 3     -- seconds a survivor must stay in a relic's cell to collect it (leaving or being caught resets it)
Config.RELIC_VISION_RADIUS = 30   -- once a survivor has seen a relic, your team keeps seeing this many studs around it until it's collected

-- Lives and respawning
Config.LIVES = 3                  -- per survivor; caught with none left = out for the rest of the match
Config.RESPAWN_CHOICE_TIME = 6    -- seconds to pick a sanctuary after being caught (then your last sanctuary is used)

-- Sanctuaries: safe blocks of cells with 2-3 exits that monsters can never enter, and where the
-- monster side can't see survivors at all (not by sight, wards, relic rings or reveals). Your team
-- starts with the start sanctuary; walking into another one captures it, and you can respawn in any
-- captured sanctuary. Each is in its own quarter of the maze (up to 4).
Config.SANCTUARIES = 3              -- including the start sanctuary
Config.SANCTUARY_SPACING = 5        -- minimum distance between sanctuaries, in cells
Config.SANCTUARY_SIZE = 2           -- cells across (2x2)
Config.START_SANCTUARY_SIZE = 3     -- the start sanctuary: 3x3
Config.SANCTUARY_EXIT_SPACING = 6   -- walking the maze from the cell just outside one exit to the cell
                                    -- just outside another takes at least this many steps (cells), even
                                    -- with every door open, so one camper can't cover two exits

-- Doors: passages that open and close during a match (see MazeLayout.placeDoors and Doors).
-- The maze is laid out so that everything stays reachable even with every door shut.
Config.DOOR_CORRIDORS = 9         -- doors in existing passages (start open; closing one forces a detour)
Config.DOOR_SHORTCUTS = 5         -- doors in place of walls (start closed; opening one is a shortcut)
Config.DOOR_SPACING = 3           -- at least this many cells between doors
Config.DOOR_MIN_DETOUR = 6        -- a door must change the walk between its two sides by at least this many cells
Config.DOOR_WARNING = 2           -- seconds a door rumbles (shaking, dust, sound) before it moves
Config.DOOR_MOVE_TIME = 1         -- seconds it takes to rise or sink
Config.DOOR_COOLDOWN = 20         -- the AI leaves a door alone this long after it changes
Config.DOOR_AI_COUNT = 3          -- until the Maze Master is a person, an AI changes this many doors at once...
Config.DOOR_AI_MIN = 5            -- ...every DOOR_AI_MIN..MAX seconds
Config.DOOR_AI_MAX = 10

-- THE MAZE MASTER: tools, each with its own cooldown, and (when DARK_MANA_ENABLED) a cost in DARK
-- MANA, which refills over time. With nobody playing the Maze Master, an AI uses the same tools
-- (MazeMasterAI); with MAZE_MASTER_AI off, the old random door AI (DOOR_AI_*) runs instead.
Config.DARK_MANA_ENABLED = false  -- off for now: cooldowns only (the mana code stays, switch it back on here)
Config.MAZE_MASTER_AI = true
Config.DARK_MANA_MAX = 100
Config.DARK_MANA_REGEN = 5        -- per second
Config.MAZE_MASTER_TOOLS = {      -- cost in dark mana, cooldown in seconds
	Door       = { cost = 10, cooldown = 1 },    -- open or shut a door (plus DOOR_COOLDOWN on that door)
	Ward       = { cost = 15, cooldown = 4 },    -- place a ward (a floating eye that watches around it)
	Haunt      = { cost = 20, cooldown = 15 },   -- haunt a survivor the monster side can see
	FalseRelic = { cost = 30, cooldown = 5 },    -- place a false relic
	Crusher    = { cost = 50, cooldown = 10 },   -- set off a crushing wall
}
Config.MAZE_MASTER_DOOR_COOLDOWN = 20   -- a door the Maze Master changed can't be changed again for this long

-- False relics: look like relics (but their eyes go out for a moment now and then). A survivor
-- near one is revealed to the monster side; one who clicks it is revealed and slowed.
Config.FALSE_RELICS_PER_MATCH = 2       -- the Maze Master can place this many in a whole match
Config.FALSE_RELIC_REVEAL_RANGE = 15    -- studs (with a clear line of sight)
Config.FALSE_RELIC_REVEAL_TIME = 5      -- seconds a survivor who clicks one stays revealed...
Config.FALSE_RELIC_SLOW = 0.4           -- ...moving at this fraction of their speed...
Config.FALSE_RELIC_SLOW_TIME = 3        -- ...for this long
Config.FALSE_RELIC_BLINK_EVERY = 5      -- seconds (roughly) between the eyes going out...
Config.FALSE_RELIC_BLINK_TIME = 0.15    -- ...for this long

-- Wards: floating eyes the Maze Master places in open cells. The monster side sees all around one
-- (walls block it). Survivors see one like anything else, and once one of them has spotted it, it
-- stays shown to them. A survivor can destroy one by standing next to it and holding, like
-- collecting a relic (the monster side is told where).
Config.WARDS_MAX = 4                    -- at a time: placing another fades the oldest
Config.WARD_VISION_RADIUS = 50          -- studs, line of sight (walls block; about 2.5 cells down a corridor; was 22). A survivor sees 80 in a cone, 12 all round
Config.WARD_HEIGHT = 4.5                -- studs above the floor the eye floats
Config.WARD_REACH = 8                   -- a survivor this close (studs, flat) can destroy it...
Config.WARD_DESTROY_TIME = 3            -- ...by staying close this long (a bar shows how far along)

-- Revealed survivors (a false relic, a haunt...): the monster side sees them wherever they are,
-- with a small ring of sight round them (smaller than a relic's), and AI monsters go for them
-- if they're within their usual sight range, walls or not.
Config.REVEAL_VISION_RADIUS = 10
-- AI monsters go after a survivor their side can see (revealed, or seen by a ward, another
-- monster, a relic ring...) within this many studs, straight line, walls or not (6 cells)
Config.REVEALED_CHASE_RANGE = 120

-- Haunt: on a survivor the monster side can see right now. For a few seconds they're revealed to
-- the monster side wherever they go, and their vision cone counts as the monster side's sight too.
-- The haunted survivor feels it (a faint purple screen edge and a whisper).
Config.HAUNT_TIME = 5
Config.HAUNT_SLOW = 0.7              -- a haunted survivor moves at this fraction of their speed while it lasts

-- Crushing walls: pairs of walls along straight corridor cells, built into the maze, that the Maze
-- Master sets off. They rumble, slam together (killing survivors between), then slide back.
Config.CRUSHERS = 6                     -- how many per maze
Config.CRUSHER_SPACING = 3              -- at least this many cells apart (and from doors)
Config.CRUSHER_WARNING = 1              -- seconds of rumbling
Config.CRUSHER_SLAM_TIME = 0.3
Config.CRUSHER_HOLD_TIME = 0.4          -- seconds they stay shut
Config.CRUSHER_RETURN_TIME = 1
Config.CRUSHED_LINGER = 1.5             -- seconds a crushed survivor's view stays on the shut walls before they choose where to respawn
Config.CRUSHER_STUN = 1                 -- seconds a monster caught between them is stunned
Config.CRUSHER_VISION = 6               -- the monster side always sees a crushing wall's cell and this many studs past it each way

-- Match states, in the order they run. The server publishes the current one (see Match).
Config.States = {
	Waiting = "Waiting",          -- not enough players yet
	Countdown = "Countdown",      -- new maze built, players at the start, monsters not hunting yet
	Playing = "Playing",
	Results = "Results",
}

-- Roles: 3 survivors, 2 monsters and 1 Maze Master. Players get roles at random; empty monster
-- slots get AI monsters, and with no Maze Master an AI works the doors. There's always at least one
-- survivor (survivors have no bots yet). In Studio the dev panel can pick your role.
Config.Roles = {
	Survivor = "Survivor",
	Monster = "Monster",
	MazeMaster = "MazeMaster",
}
Config.ROLE_SLOTS = { Survivor = 3, Monster = 2, MazeMaster = 1 }

-- The lobby: between matches everyone waits here, picks a preferred role (honoured where a slot is
-- free; the rest are random) and anyone presses Start. Matches need MIN_PLAYERS people.
-- Developer controls (role override, New match, the doors panel) show in Studio, and in the
-- published game for the experience's owner plus these UserIds:
Config.DEV_USER_IDS = {}
Config.SURVIVOR_BOTS = true       -- fill empty survivor slots with bots (SurvivorBot)

-- Heroes (ReplicatedStorage.Heroes has their abilities). Until there's a character select, every
-- survivor plays this one. A STUNNED monster can't move, lunge or catch (abilities and crushing
-- walls stun).
Config.DEFAULT_SURVIVOR_HERO = "Sara"

-- Monsters played by people
Config.MONSTER_SPEED = 24         -- walk speed (the facing rule applies, as for survivors)
Config.LUNGE_WINDUP = 0.15        -- seconds crouched before the lunge (you can't move)
Config.LUNGE_DISTANCE = 12        -- studs the lunge carries you
Config.LUNGE_TIME = 0.25          -- seconds the lunge takes
Config.LUNGE_REACH = 9            -- a survivor this close to you during the lunge is caught (studs;
                                  -- generous for testing while the monster is a stand-in; was 5)
Config.LUNGE_COOLDOWN = 1.2       -- seconds before you can lunge again after a miss

return Config
