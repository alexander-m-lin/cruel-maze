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
Config.MONSTER_COUNT = 1          -- AI monsters per match

-- Relics: survivors win by collecting RELICS_NEEDED of the RELIC_TOTAL in the maze
Config.RELIC_TOTAL = 9
Config.RELICS_NEEDED = 6
Config.RELIC_SPACING = 4          -- minimum distance between relics, in maze cells (shrinks a little if they can't fit)
Config.RELIC_COLLECT_TIME = 3     -- seconds a survivor must stay in a relic's cell to collect it (leaving or being caught resets it)
Config.RELIC_VISION_RADIUS = 30   -- once a survivor has seen a relic, your team keeps seeing this many studs around it until it's collected

-- Lives and respawning
Config.LIVES = 3                  -- per survivor; caught with none left = out for the rest of the match
Config.RESPAWN_CHOICE_TIME = 6    -- seconds to pick a spawn room after being caught (then your last room is used)

-- Spawn rooms: 2x2-cell rooms with 2-3 exits that monsters can never enter. Your team starts with
-- the start room; walking into another one captures it, and you can respawn in any captured room.
Config.SPAWN_ROOMS = 4            -- including the start room
Config.SPAWN_ROOM_SPACING = 5     -- minimum distance between rooms, in cells

-- Match states, in the order they run. The server publishes the current one (see Match).
Config.States = {
	Waiting = "Waiting",          -- not enough players yet
	Countdown = "Countdown",      -- new maze built, players at the start, monsters not hunting yet
	Playing = "Playing",
	Results = "Results",
}

-- Roles. Phase 0 makes everyone a survivor; monsters and the Maze Master come later.
Config.Roles = {
	Survivor = "Survivor",
	Monster = "Monster",
	MazeMaster = "MazeMaster",
}

return Config
