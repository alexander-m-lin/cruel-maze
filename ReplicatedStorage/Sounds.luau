-- Every sound effect in the game, in one place so they're easy to swap or tune.
-- id: a Roblox audio asset. volume: 0-1+. speed: playback speed (also changes pitch).
-- range: for sounds that come from a place in the world, how far away (studs) they can be heard.
-- Played by the SoundEffects script on each player's computer.
--
-- Most are from Roblox's licensed libraries (Pro Sound Effects "SFX", APM Music stings); the
-- relic, spawn-room and tick sounds are free uploads by other creators.

local Sounds = {
	-- Relics
	RelicHum       = { id = 9125674129,  volume = 0.6, range = 60, looped = true },   -- while someone collects (pitch rises as the bar fills)
	-- everyone hears it. A soft bell, slowed a touch to make it warmer. Alternatives to try:
	-- 90773963263404 ("completedtask"), 96659579913194 ("PathComplete"); the old sharp one was 4612374036
	RelicCollected = { id = 103516326607012, volume = 0.35, speed = 0.92 },
	RoomCaptured   = { id = 132574644259001, volume = 0.5 },                          -- everyone hears it

	-- The monster
	MonsterRoar    = { id = 9113980319,  volume = 0.9, range = 140 },                 -- when it starts chasing someone
	KillGrab       = { id = 9113980512,  volume = 1.0, range = 160, stopAfter = 2.2 }, -- as it lifts its victim
	KillRip        = { id = 9113734494,  volume = 1.0, range = 140, stopAfter = 1.6 }, -- tearing them apart...
	KillCrack      = { id = 9113542694,  volume = 0.9, range = 140 },                 -- ...and the crack of bones

	-- Match flow
	CountdownTick  = { id = 134410911353980, volume = 0.6 },                          -- each second of the countdown
	Win            = { id = 1846901578,  volume = 0.5 },                              -- your team won
	Lose           = { id = 1842423247,  volume = 0.5 },                              -- your team lost
}

return Sounds
