-- THE MINOTAUR, monster: a massive horned juggernaut in bronze armour. His attacks are devastating
-- but telegraphed, and they commit him: he exploits the maze's long corridors and predictable
-- survivors. His abilities are carried out in ServerStorage.HeroAbilities.Minotaur; his body is
-- ServerStorage.MinotaurRig, moved and animated by StarterPlayerScripts.HeroVisuals.Minotaur.
--
-- Tear Asunder (left click, auto-targeted, like Fear Eater's Devour) is his ordinary catch.
-- Devastating Charge catches everyone in its path; Crush stuns everyone where he lands, which is
-- meant to set up a Charge.

return {
	name = "Minotaur",
	title = "Juggernaut",
	role = "Monster",
	rig = "MinotaurRig",       -- ServerStorage model
	rigScale = 1.25,           -- (the rig is concept B at its generated size; he's meant to loom)
	lunge = false,             -- no stand-in lunge: Tear Asunder is the catch
	speed = 0.7,               -- walks at this fraction of a monster's speed (Config.MONSTER_SPEED; AI
	                           -- monsters' too): slow and heavy, so his Charge and Crush are how he closes in

	-- TEAR ASUNDER's kill, in seconds from the catch: he grabs them, lifts them overhead and tears
	-- them in two. The server holds the victim (and him) this long; HeroVisuals.Minotaur draws it.
	kill = {
		GRAB = 0.25,     -- hands close on them
		LIFT = 0.7,      -- ...lifted overhead, struggling...
		RIP = 1.6,       -- ...torn in two (the pieces are each computer's own from here)
		RELEASE = 1.6,   -- (the server removes the body just after this)
		DONE = 2.4,      -- he moves again
	},
	-- Caught by the CHARGE: trampled and flung aside as he runs on (he doesn't stop for it)
	trample = {
		RELEASE = 0.1,
		DONE = 1.5,      -- (when the victim chooses where to respawn, as after any kill)
	},
	CORPSE_TIME = 4,           -- seconds a trampled body lies there before it fades

	abilities = {
		-- AUTO-TARGETED (left click), like Devour without the fear: the nearest survivor he can see
		-- in front of him within `range`. He gathers himself for `windup` (the target is warned),
		-- then lunges: caught if they're still within catchRange in a clear line, otherwise a miss
		-- (and the full cooldown). Nobody to target: nothing happens, no cooldown. A stun or pull in
		-- the windup calls it off.
		Primary = {
			id = "TearAsunder", name = "Tear Asunder", cooldown = 5,
			autoTarget = true,      -- (AutoCatch carries it out; FearMarks rings who it'd go for)
			windup = 0.3,
			range = 10,             -- studs: who he can target
			catchRange = 12,        -- studs: still this close (clear line) when the windup ends = caught
			dashSpeed = 70,         -- studs per second he lunges
			missDistance = 8,       -- studs he lunges after a miss
		},
		-- He lowers his horns for `windup` seconds (a lane on the floor shows where), then charges
		-- straight along it at `speed` until a wall or a shut door stops him: he can't steer or stop.
		-- Every survivor the charge touches (within halfWidth of his path) is caught, and he runs on.
		-- Hitting the wall stuns him for `recovery`. The cooldown starts when he hits it.
		Secondary = {
			id = "Charge", name = "Devastating Charge", cooldown = 10,
			windup = 1,             -- seconds, held still, the lane showing
			speed = 120,            -- studs per second
			halfWidth = 7,          -- studs either side of his path (a corridor is 18 wide)
			reach = 3,              -- studs ahead of him that already count as touched
			bodyRadius = 4,         -- he stops this far short of the wall (his body's front)
			maxDistance = 400,      -- studs (a safety limit: the maze is smaller)
			recovery = 0.6,         -- seconds reeling after the impact
		},
		-- He leaps to the spot you aim at (up to `range` away, locked when used), over walls if need
		-- be, landing `windup` seconds later. For the last `telegraph` seconds a ring shows where,
		-- to survivors near it even through the fog. Survivors within `radius` of the landing (in a
		-- clear line) are stunned for `stun` seconds. He has to land somewhere he could walk,
		-- outside sanctuaries (an aim inside a wall or sanctuary is pulled back toward him).
		Ultimate = {
			id = "Crush", name = "Crush", cooldown = 60,
			targeted = true,        -- (AbilityControls sends the point under the mouse)
			range = 100,            -- studs
			windup = 1.5,           -- seconds from use to impact...
			crouch = 0.3,           -- ...the first of them crouched, then airborne
			height = 16,            -- studs his arc rises (walls are 7)
			telegraph = 0.7,        -- seconds before impact the landing ring shows
			threatRange = 40,       -- survivors this close to the landing see the ring through the fog
			radius = 14,            -- studs
			stun = 2.5,             -- seconds
			recovery = 0.3,         -- seconds before he can move after landing
			bodyRadius = 3,         -- he can't land closer than this to a wall
		},
	},
}
