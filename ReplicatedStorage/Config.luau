-- Settings shared by the server and every player's computer.
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

-- Camera: direction from the player to the camera. (-1, 1, -1) = true isometric (45° around,
-- ~35° down). The fog uses this too, to keep fog between the camera and you see-through.
Config.CAMERA_DIRECTION = Vector3.new(-1, 1, -1).Unit

-- Match flow
Config.MIN_PLAYERS = 1            -- a match starts once this many players are in the server
Config.COUNTDOWN = 3              -- seconds of "Starting in..." before each match
Config.RESULTS_TIME = 5           -- seconds the result is shown before the next match
Config.MONSTER_COUNT = 1          -- AI monsters per match

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
