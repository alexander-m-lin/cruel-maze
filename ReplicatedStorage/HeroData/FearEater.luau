-- FEAR EATER, monster: a floating wraith in a tattered black cloak, with huge pale arms reaching out
-- of its sleeves. His abilities are carried out in ServerStorage.HeroAbilities.FearEater; his body
-- is ServerStorage.FearEaterRig, moved and animated by StarterPlayerScripts.HeroVisuals.FearEater.
--
-- Devour is his only way to catch someone (left click does nothing for him). "Feared" survivors
-- (the "FearedUntil" attribute, from Instill Fear) can be devoured from much further away.

return {
	name = "Fear Eater",
	title = "Wraith",
	role = "Monster",
	rig = "FearEaterRig",      -- ServerStorage model
	rigScale = 1,
	lunge = false,             -- no left-click lunge: Devour is the catch

	-- DEVOUR's kill, in seconds from the catch. The server holds the victim (and the monster) for
	-- this long; HeroVisuals.FearEater draws it from the same times.
	kill = {
		GRAB = 0.25,     -- hands close on them, lifted off their feet, facing away from him
		WIND = 1.0,      -- he winds his head back, lifting them higher
		ENGULF = 1.45,   -- ...and brings their head up into his hood, where they keep struggling...
		FADE = 2.5,      -- ...until it starts to die away...
		STILL = 3.0,     -- ...and they're still
		OUT = 3.1,       -- he draws them back out of the hood (taking 0.4 s)...
		RELEASE = 3.6,   -- ...and lets go: the body drops to the floor
		DONE = 4.0,      -- he moves again
	},
	CORPSE_TIME = 4,           -- seconds the body lies there before it fades

	abilities = {
		-- Lunge forward the way you face; the first survivor in reach is caught and devoured.
		-- Aimed at a feared survivor (within fearedCone of where you face, in a clear line), the
		-- dash reaches much further and heads straight for them.
		Primary = {
			id = "Devour", name = "Devour", cooldown = 5,
			windup = 0.15,          -- seconds he gathers himself first (can't move)
			range = 14,             -- studs the dash carries him
			dashTime = 0.3,         -- seconds it takes
			fearedRange = 35,       -- at a feared survivor: this far...
			fearedSpeed = 75,       -- ...at this many studs per second
			fearedCone = 40,        -- degrees (total width) around where you face that counts as aimed at them
			reach = 7,              -- a survivor this close to his reach point is caught (studs)...
			reachForward = 2,       -- ...which is this far in front of his middle (so: 9 ahead, 7 to the sides, 5 behind)
		},
		-- Every survivor in the maze, wherever they are, is filled with DREAD: within dreadTime they
		-- must reach a sanctuary or get within nearAlly studs of another survivor (bots count).
		-- Those who don't are FEARED for fearTime: revealed to the monster side and slowed - and
		-- Devour and Living Nightmare reach them more easily. (Already in a sanctuary: untouched.)
		Secondary = {
			id = "InstillFear", name = "Instill Fear", cooldown = 25,
			dreadTime = 5,          -- seconds survivors have to reach a sanctuary or a teammate
			nearAlly = 10,          -- studs that count as near another survivor
			fearTime = 5,           -- seconds the fear lasts (revealed and slowed)
			fearSlow = 0.8,         -- feared survivors move at this fraction of their speed
			castTime = 0.6,         -- seconds he stands still, arms spread, casting it
		},
		-- For `duration` seconds he passes through the maze's inner walls and doors (not the outer
		-- wall, nor into sanctuaries), and moves much faster toward feared survivors. Ending inside
		-- a wall, he's pushed out into the middle of the cell he's in.
		Ultimate = {
			id = "LivingNightmare", name = "Living Nightmare", cooldown = 60,
			duration = 7,           -- seconds he passes through inner walls and doors
			speedBoost = 0.6,       -- +60% speed while moving toward a feared survivor
		},
	},
}
