-- SARA, survivor. Her abilities are carried out in ServerStorage.HeroAbilities.Sara and drawn by
-- StarterPlayerScripts.HeroEffects (still the older single script; it moves into HeroVisuals.Sara
-- next). Tune the numbers here.

return {
	name = "Sara",
	title = "Cryptraider",
	role = "Survivor",
	abilities = {
		-- Lash the whip out the way you face. The first thing it meets: a wall or a relic pulls
		-- you to it; a teammate is pulled to you; a monster is pulled to you and stunned.
		Primary = {
			id = "Whip", name = "Whip", cooldown = 5,
			missCooldown = 2,      -- hits nothing at all (a whiff): ready again sooner
			range = 39,            -- studs
			speed = 140,           -- studs per second the lash travels (out; it comes back faster)
			pullSpeed = 70,        -- studs per second whoever's pulled travels
			stun = 1,              -- seconds a monster is stunned (after the pull)
			monsterHitRadius = 5,  -- how close to the lash (studs, either side) a monster must be to be hit...
			allyHitRadius = 4,     -- ...a teammate...
			relicHitRadius = 2.5,  -- ...or a relic (and nothing counts behind a wall)
		},
		-- Find the nearest relic your team hasn't spotted yet (real or false) within range:
		-- it's spotted, as if you'd seen it.
		Secondary = {
			id = "TreasureHunt", name = "Treasure hunt", cooldown = 15,
			range = 110,           -- studs, straight line
			missCooldown = 3,      -- nothing in range: try again sooner
		},
		-- Spin the whip overhead, standing still (a ring on the floor shows its reach): partway
		-- through, every monster within range is stunned. Caught before then: no stun.
		Ultimate = {
			id = "Flourish", name = "Flourish", cooldown = 60,
			castTime = 1,          -- seconds she stands still, spinning
			stunAt = 0.5,          -- seconds into that when the stun goes out
			range = 20,            -- studs
			stun = 3.5,            -- seconds
		},
	},
}
