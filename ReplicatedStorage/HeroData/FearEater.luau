-- FEAR EATER, monster: a floating wraith in a tattered black cloak, with huge pale arms reaching out
-- of its sleeves. His abilities are carried out in ServerStorage.HeroAbilities.FearEater; his body
-- is ServerStorage.FearEaterRig, moved and animated by StarterPlayerScripts.HeroVisuals.FearEater.
--
-- Devour (left click, auto-targeted) is his only way to catch someone. "Feared" survivors (the
-- "FearedUntil" attribute, from Instill Fear) are devoured from much further away, without fail.

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
		-- AUTO-TARGETED (left click): no aiming. He picks the nearest survivor he can see in front
		-- of him within `range` (a FEARED survivor anywhere within fearedRange, in a clear line,
		-- comes first), gathers himself for `windup` seconds (the target is warned), then:
		--   feared: always caught (unless they reached a sanctuary)
		--   others: caught if still within catchRange in a clear line; otherwise he lunges and misses
		-- Nobody to target: nothing happens and it costs no cooldown. A stun or pull during the
		-- windup calls it off (a teammate can save them).
		Primary = {
			id = "Devour", name = "Devour", cooldown = 5,
			windup = 0.3,           -- seconds he gathers himself (can't move); the target sees it coming
			range = 12,             -- studs: who he can target (seen, in front of him)
			catchRange = 14,        -- studs: still this close (clear line) when the windup ends = caught
			fearedRange = 40,       -- studs: a feared survivor this far away (clear line) can be targeted...
			fearedCatchRange = 46,  -- ...and is caught unless they've got this far (or into a sanctuary)
			dashSpeed = 70,         -- studs per second he lunges at them
			missDistance = 8,       -- studs he lunges after a miss
			nightmareCooldown = 1,  -- seconds to recharge during Living Nightmare (casting it also cuts what's left to this)
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
		-- wall, nor into sanctuaries), moves much faster toward feared survivors, and Devour
		-- recharges in its nightmareCooldown. Ending inside a wall, he's pushed out into the middle
		-- of the cell he's in.
		Ultimate = {
			id = "LivingNightmare", name = "Living Nightmare", cooldown = 60,
			duration = 7,           -- seconds he passes through inner walls and doors
			speedBoost = 0.6,       -- +60% speed while moving toward a feared survivor
		},
	},
}
