-- KAI, survivor: a hacker. Reconnaissance, disrupting the Maze Master's devices, and escaping by
-- deception; no grapple and no stun. His abilities are carried out in
-- ServerStorage.HeroAbilities.Kai (Encrypt's circuit indicators: ServerStorage.Encrypt) and drawn by
-- StarterPlayerScripts.KaiEffects. Tune the numbers here.

return {
	name = "Kai",
	title = "Hacker",
	role = "Survivor",
	abilities = {
		-- A cone the way you face (fixed when you start it). After castTime it sees through walls
		-- for `duration` seconds: ordinary survivor sight inside it, shared with your team (relics
		-- and wards in it are spotted; monsters in it show, only while they're in it).
		Primary = {
			id = "Scanner", name = "Scanner", cooldown = 15,
			castTime = 1,          -- seconds before the scan sees (you can keep moving)
			cone = 90,             -- degrees, total width
			range = 70,            -- studs
			duration = 3,          -- seconds it sees through walls
		},
		-- An electric pulse round where you cast it (it stays there): after `activation` seconds, for
		-- `duration` seconds every door in `radius` is jammed open (one that was shut closes again
		-- afterwards), every crushing wall can't go off, and the wards it caught see nothing.
		-- Wards placed after the pulse work as normal. Monsters aren't touched.
		Secondary = {
			id = "EMP", name = "EMP", cooldown = 40,
			radius = 50,           -- studs (through walls)
			activation = 0.5,      -- seconds from the cast to the pulse
			duration = 5,          -- seconds devices stay disrupted
		},
		-- For `duration` seconds you're uncatchable and the monster side doesn't see you: only a blue
		-- circuit on the floor of the cell you're in. Leaving a junction, copies of it run off down
		-- the other ways out. Using an ability or interacting (a relic, a ward) ends it early.
		Ultimate = {
			id = "Encrypt", name = "Encrypt", cooldown = 60,
			duration = 5,          -- seconds
			decoys = 3,            -- copies at most at once
			decoyEvery = 1,        -- seconds at least between junctions that make copies
			warnTime = 1,          -- the last seconds: every circuit flickers (all alike)
			pauseChance = 0.3,     -- a copy stops for a moment at a cell this often, as a person does
		},
	},
}
