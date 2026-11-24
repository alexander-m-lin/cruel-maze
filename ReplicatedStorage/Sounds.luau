-- Every sound effect in the game, in one place so they're easy to swap or tune.
-- id: a Roblox audio asset. volume: 0-1+. speed: playback speed (also changes pitch).
-- range: for sounds that come from a place in the world, how far away (studs) they can be heard.
-- startAt: seconds into the recording to start from (skips a slow or silent start).
-- Played by the SoundEffects script on each player's computer.
--
-- Most are from Roblox's licensed libraries (Pro Sound Effects "SFX", APM Music stings); the
-- countdown tick, the scream and the music are free uploads by other creators.
-- To hear them in Studio: SoundService.SoundBoard (a preview copy; rebuild it after changes here).

local Sounds = {
	-- Relics
	RelicHum       = { id = 9125674129,  volume = 0.6, range = 60, looped = true },   -- while someone collects (pitch rises as the bar fills)
	RelicCollected = { id = 9118587701, volume = 1.0 },                              -- everyone hears it
	-- (tried before: 4612374036 sharp ding, 103516326607012 soft bell; 90773963263404 and 96659579913194 untried)
	SanctuaryCaptured   = { id = 9125879007, volume = 1.0, startAt = 0.5 },             -- everyone hears it

	-- The monster
	MonsterRoar    = { id = 9113980319,  volume = 2.0, range = 140 },                 -- when it starts chasing someone
	DevourWarning  = { id = 9113980319,  volume = 0.9, speed = 1.5 },                 -- you're Devour's target (only you hear it; the roar, higher)
	KillGrab       = { id = 9113980512,  volume = 0.8, range = 160, stopAfter = 2.2 }, -- as it lifts its victim
	KillScream     = { id = 87645109019991, volume = 0.8, range = 140 },              -- the victim's scream as they're torn apart...
	KillCrack      = { id = 9113542694,  volume = 0.6, range = 140 },                 -- ...and the crack of bones

	-- Doors (see DoorView)
	-- (startAt skips each recording's quiet opening: measured with PlaybackLoudness)
	DoorRumble     = { id = 9125875498,  volume = 1.0, range = 90, stopAfter = 2.25, startAt = 1.0 },    -- the warning, heard near the door
	DoorFarRumble  = { id = 9125486602,  volume = 0.15, stopAfter = 2.5, startAt = 0.25 },             -- ...and faintly by everyone, anywhere
	DoorGrind      = { id = 9113807062,  volume = 0.9, range = 90, stopAfter = 1.3, startAt = 0.4 },   -- the slab rising or sinking (timed to start with it)

	-- Crushing walls (see CrusherView): they rumble like doors, then slam
	CrusherSlam    = { id = 9125393230,  volume = 1.2, range = 120, stopAfter = 1.5 },   -- big rocks dropping

	-- The Maze Master
	Whisper        = { id = 72101610830828, volume = 0.8 },                           -- dread (Instill Fear; only you hear it)

	-- Heroes
	WhipCrack      = { id = 9113612888, volume = 0.9, range = 90 },                    -- Sara's whip (Pro Sound Effects)
	WhipSpin       = { id = 9120972321, volume = 0.9, range = 90 },                    -- Sara's Flourish
	DragScrape     = { id = 9120934304, volume = 0.8, range = 80, looped = true },     -- anyone being dragged by a whip (Pro Sound Effects: a paddle scraping through icy snow)
	TreasureHunt   = { id = 90618709727045, volume = 0.7 },                            -- a relic found by Treasure hunt (only Sara's team hears it)
	Deflect        = { id = 9119072660, volume = 0.9, range = 90 },                    -- a catch deflected by Sara's Flourish (Pro Sound Effects: shield clang)
	ScanSweep      = { id = 98592637617650, volume = 0.6, range = 60 },                -- Kai's Scanner going out
	EMPCharge      = { id = 9114277757, volume = 0.8, range = 120 },                   -- Kai's EMP charging (Pro Sound Effects: electric zaps)
	EMPPulse       = { id = 9114277402, volume = 1.1, range = 160 },                   -- ...and going off
	EncryptIn      = { id = 9114277338, volume = 0.7, range = 80, speed = 1.4 },       -- Kai dissolving into a circuit, and coming back

	-- The Minotaur (HeroVisuals.Minotaur; all Pro Sound Effects). His telegraphs carry: survivors hear
	-- the snort, the bellow, the crash and the slam even when the fog hides him.
	MinotaurRoar   = { id = 9113636194, volume = 1.4, range = 140 },                   -- starting a chase (instead of MonsterRoar): bull grunts and snorts
	HoofStep       = { id = 9113524237, volume = 0.45, range = 70, speed = 0.6 },      -- each hoof landing as he walks (a hard thump, pitched down)
	HoofGallop     = { id = 9113524237, volume = 0.8, range = 110, speed = 0.75 },     -- ...and as he charges
	ChargeSnort    = { id = 9113634952, volume = 1.4, range = 120 },                   -- the Charge's windup: a wet bull snort
	ChargeBellow   = { id = 9113629087, volume = 1.6, range = 180, stopAfter = 2.2 },  -- ...as he sets off: a bull's bellow
	ChargeCrash    = { id = 9125393230, volume = 1.4, range = 160, stopAfter = 1.5 },  -- ...hitting the wall: big rocks dropping
	Trample        = { id = 9113524237, volume = 1.2, range = 120 },                   -- a survivor run down by it
	CrushLeap      = { id = 9113635074, volume = 1.2, range = 120 },                   -- Crush: a snort as he leaps
	CrushSlam      = { id = 9113525391, volume = 1.6, range = 180, speed = 0.7 },      -- ...landing: a huge body slam, pitched down...
	CrushRubble   = { id = 9118588165, volume = 1.0, range = 140, speed = 0.8 },       -- ...and the floor cracking

	-- Background music: plays all the time, on a loop
	Music          = { id = 138890398994853, volume = 0.1, looped = true },

	-- Match flow
	CountdownTick  = { id = 134410911353980, volume = 0.6 },                          -- each second of the countdown
	Win            = { id = 1846901578,  volume = 0.5 },                              -- your team won
	Lose           = { id = 1842423247,  volume = 0.5 },                              -- your team lost
}

return Sounds
