-- SURVIVOR BOTS' ABILITIES: when a bot uses its hero's abilities. Only the choosing is here; using one
-- goes through Abilities.use, the very path a player's key press takes (the same checks, cooldowns
-- and handlers in HeroAbilities), so a bot's abilities are exactly a player's.
--
--   BotAbilities.has(heroId)               -- is there a brain for this hero?
--   BotAbilities.think(bot, heroId, sense) -- every frame (SurvivorBot:Step), for a bot that casts
--                                             (Match: Config.AI_SURVIVORS_CASTING of them). Escapes are
--                                             checked every frame; the rest THINK_EVERY seconds.
--     sense = { root, eye (its eye point), monsters, wards (WardEyes or nil), now }
--
-- KAI:
--   ENCRYPT - it's about to be caught, and isn't in a sanctuary: a Devour is winding up at it (the
--             warning a player gets on screen, "DevourTargetAt"), or a monster with no wall between
--             is within ENCRYPT_DANGER studs (FEARED_DANGER while it's feared: Devour reaches feared
--             survivors from much further)
--   EMP     - it sees a working ward close enough for the pulse to catch (within the EMP's radius,
--             less EMP_MARGIN, with no wall between)
--   SCANNER - whenever it's ready: aimed at the nearby cells it hasn't seen yet (the way that covers
--             the most of them, nearer ones counting more); if it's seen all round, at the cells it
--             can't see right now. "Seen" is the bot's own record: every cell centre within
--             Config.VIEW_RANGE it has had a clear line to.
-- Never while encrypted (any other ability would end it).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Config)
local Heroes = require(ReplicatedStorage.Heroes)
local Protection = require(ReplicatedStorage.Protection)
local Abilities = require(ServerStorage.Abilities)

local ENCRYPT_DANGER = 15   -- studs: a monster this close (and in sight) is about to catch it
local FEARED_DANGER = 40    -- studs: ...or this close while it's feared
local THINK_EVERY = 0.2     -- seconds between choices of the other abilities
local EMP_MARGIN = 5        -- studs: a ward must be this far inside the EMP's radius
local LOOK_EVERY = 0.5      -- seconds between updates of which cells it sees
local SCAN_HEADINGS = 16    -- directions it weighs a scan in

local BotAbilities = {}

local function flat(v) return Vector3.new(v.X, 0, v.Z) end

-- a clear line between two points at eye height (walls only)
local function clear(bot, from, to)
	local a = Vector3.new(from.X, bot.maze.floorY + 3, from.Z)
	local b = Vector3.new(to.X, bot.maze.floorY + 3, to.Z)
	return workspace:Raycast(a, b - a, bot.rays) == nil
end

-- Which cells it sees now (bot.inView), and every one it has ever seen (bot.seenCells)
local function look(bot, sense)
	if sense.now < (bot.lookAt or 0) then return end
	bot.lookAt = sense.now + LOOK_EVERY
	bot.seenCells = bot.seenCells or {}
	bot.inView = {}
	local maze = bot.maze
	for x = 1, maze.n do
		for z = 1, maze.n do
			local c = bot:centerOf(x, z)
			if flat(c - sense.eye).Magnitude <= Config.VIEW_RANGE and clear(bot, sense.eye, c) then
				bot.inView[x * 1000 + z] = true
				bot.seenCells[x * 1000 + z] = true
			end
		end
	end
end

-- The way to aim a scan: covers the most cells `wanted(x, z)`, nearer ones counting more; nil if none
local function bestHeading(bot, sense, def, wanted)
	local maze = bot.maze
	local cos = math.cos(math.rad(def.cone / 2))
	local best, bestScore = nil, 0
	for i = 1, SCAN_HEADINGS do
		local a = (i - 1) / SCAN_HEADINGS * math.pi * 2
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local score = 0
		for x = 1, maze.n do
			for z = 1, maze.n do
				if not wanted(x, z) or bot.objectives:IsBlocked(x, z) then continue end
				local offset = flat(bot:centerOf(x, z) - sense.root.Position)
				local d = offset.Magnitude
				if d <= def.range and d > 1 and offset.Unit:Dot(dir) >= cos then
					score += 1 - d / (def.range * 1.5)     -- (nearer counts more)
				end
			end
		end
		if score > bestScore then best, bestScore = dir, score end
	end
	return best
end

local brains = {}

function brains.Kai(bot, sense)
	local hero = Heroes.get("Kai")
	local root, now = sense.root, sense.now
	if Protection.encrypted(bot) then return end
	local safe = bot.objectives:IsSafe(root.Position)

	-- ENCRYPT: about to be caught (every frame)
	if not safe and Abilities.ready(bot, "Ultimate") then
		local serverNow = workspace:GetServerTimeNow()
		local targeted = serverNow - (bot:GetAttribute("DevourTargetAt") or -math.huge) <= (bot:GetAttribute("DevourWindup") or 0)
		local feared = (bot:GetAttribute("FearedUntil") or 0) > serverNow
		local danger = feared and FEARED_DANGER or ENCRYPT_DANGER
		local close = false
		for _, monster in sense.monsters do
			if monster.pos and flat(monster.pos - root.Position).Magnitude <= danger and clear(bot, sense.eye, monster.pos) then
				close = true
				break
			end
		end
		if (targeted or close) and Abilities.use(bot, "Ultimate", flat(root.CFrame.LookVector)) then return end
	end

	if now < (bot.abilityThinkAt or 0) then return end
	bot.abilityThinkAt = now + THINK_EVERY
	look(bot, sense)

	-- EMP: a working ward in sight, within the pulse
	local emp = hero.abilities.Secondary
	if sense.wards and Abilities.ready(bot, "Secondary") then
		for _, ward in sense.wards.list do
			local d = flat(ward.center - root.Position).Magnitude
			if sense.wards:Working(ward) and d <= emp.radius - EMP_MARGIN and d <= Config.VIEW_RANGE
				and clear(bot, sense.eye, ward.center) then
				if Abilities.use(bot, "Secondary", flat(root.CFrame.LookVector)) then return end
			end
		end
	end

	-- SCANNER: on cooldown, at cells it hasn't seen, or else at ones it can't see now
	local scan = hero.abilities.Primary
	if Abilities.ready(bot, "Primary") then
		local seen, inView = bot.seenCells or {}, bot.inView or {}
		local dir = bestHeading(bot, sense, scan, function(x, z) return not seen[x * 1000 + z] end)
			or bestHeading(bot, sense, scan, function(x, z) return not inView[x * 1000 + z] end)
		if dir then Abilities.use(bot, "Primary", dir) end
	end
end

function BotAbilities.has(heroId)
	return brains[heroId] ~= nil
end

function BotAbilities.think(bot, heroId, sense)
	local brain = brains[heroId]
	if brain then brain(bot, sense) end
end

return BotAbilities
