-- THE AI MAZE MASTER: works the Maze Master's tools when no person has the role. It uses the same
-- tools object a person does (MazeMaster: same cooldowns, same rules, dark mana if that's on), and
-- it only knows what the monster side knows: survivors count as seen only when the monster side
-- can see them (Match's monsterSideSees, the same check Haunt uses), and it remembers where each
-- was last seen.
--
--   local ai = MazeMasterAI.new(tools, { maze, doors, crushers, wards, objectives, monsters,
--                                        survivors = fn, sees = fn(position, survivor) })
--   ai:Start()      -- the match is on: false relics go down straight away
--   ai:Step(dt)     -- every frame (it thinks every THINK_EVERY seconds)
--
-- What it does, most urgent first:
--   CRUSHING WALLS - sets one off when a seen survivor will be between its walls as they slam
--                    (where they'll be after the warning, from how they're moving).
--   HAUNT          - on a seen survivor, preferring the one nearest a monster (so the hunter
--                    can follow them), whenever it's ready.
--   DOORS          - when a seen survivor is being chased, shuts open doors a few cells ahead of
--                    them (on their side, away from the monster), cutting off the escape.
--                    Otherwise, now and then, shifts a door near where survivors were last seen.
--   WARDS          - on cooldown, at junctions nothing watches yet, near where survivors were last
--                    seen or on the way to relics. With all Config.WARDS_MAX out, it only moves
--                    one (the oldest) toward survivors spotted somewhere unwatched.
--   FALSE RELICS   - all of them at the start, spread out away from the real relics.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Config)
local MazeLayout = require(ServerStorage.MazeLayout)

local DIRS, key = MazeLayout.DIRS, MazeLayout.key

local THINK_EVERY = 0.2      -- seconds between decisions
local CHASE_STEPS = 5        -- a survivor is "chased" with a monster this many cells away (walking)
local DOOR_AHEAD_MIN = 2     -- shut doors this many cells ahead of a chased survivor...
local DOOR_AHEAD_MAX = 5     -- ...up to this many (closer ones they'd be through before it shuts)
local IDLE_DOOR_EVERY = { 6, 10 }   -- seconds between door shifts when nobody's being chased
local IDLE_DOOR_NEAR = 5     -- ...picking a door within this many cells of a last-seen survivor
local MEMORY = 20            -- seconds a last sighting stays useful
local WARD_SPACING = 3       -- cells between wards
local WARD_MOVE_IF_UNWATCHED = 3   -- with every ward out, move one if survivors were seen this many cells from any ward...
local WARD_MOVE_EVERY = 8    -- ...at most this often (seconds)
local WARD_REPLACE_AFTER = 10   -- no new ward where a survivor destroyed one for this long (so they can tell it worked)
local FAKE_SANCTUARY_GAP = 6      -- false relics go at least this many cells (walking the grid) from any sanctuary

local MazeMasterAI = {}
MazeMasterAI.__index = MazeMasterAI

-- Studio only: each action and why, as the "MazeMasterAI" attribute on ReplicatedStorage.Match
-- (for testing; a counter keeps repeats distinct)
local STUDIO = game:GetService("RunService"):IsStudio()
local actions = 0
local function note(text)
	if not STUDIO then return end
	actions += 1
	ReplicatedStorage.Match:SetAttribute("MazeMasterAI", actions .. " " .. text)
end

function MazeMasterAI.new(tools, parts)
	local self = setmetatable({}, MazeMasterAI)
	self.tools = tools
	for k, v in parts do self[k] = v end
	self.lastSeen = {}             -- [survivor] = { pos = Vector3, at = os.clock() }
	self.timer = 0
	self.nextIdleDoor = os.clock() + IDLE_DOOR_EVERY[1]
	return self
end

---------------------------------------------------------------- helpers
local function cellOf(maze, p)
	local x = math.clamp(math.floor((p.X + maze.half) / maze.S) + 1, 1, maze.n)
	local z = math.clamp(math.floor((p.Z + maze.half) / maze.S) + 1, 1, maze.n)
	return x, z
end

local function cellCenter(maze, x, z)
	return Vector3.new((x - 0.5) * maze.S - maze.half, maze.floorY, (z - 0.5) * maze.S - maze.half)
end

-- Walking distance in cells from (x, z) to everywhere within `limit` steps, through the maze as it
-- is now (a closing door counts as shut). -> dist[key] = steps
local function stepsFrom(maze, x, z, limit)
	local dist = { [key(x, z)] = 0 }
	local queue, head = { { x, z } }, 1
	while head <= #queue do
		local c = queue[head]
		head += 1
		local here = dist[key(c[1], c[2])]
		if here >= limit then continue end
		for _, d in DIRS do
			if not maze.walls[c[1]][c[2]][d[3]] then
				local nx, nz = c[1] + d[1], c[2] + d[2]
				local k = key(nx, nz)
				if dist[k] == nil then
					dist[k] = here + 1
					table.insert(queue, { nx, nz })
				end
			end
		end
	end
	return dist
end

local function rootOf(survivor)
	local character = survivor.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and humanoid and humanoid.Health > 0 and not survivor:GetAttribute("Seized") then return root end
	return nil
end

function MazeMasterAI:ready(tool)
	local def = Config.MAZE_MASTER_TOOLS[tool]
	if os.clock() < (self.tools.readyAt[tool] or 0) then return false end
	return not Config.DARK_MANA_ENABLED or self.tools.mana >= def.cost
end

---------------------------------------------------------------- the match starts
function MazeMasterAI:Start()
	self:placeFalseRelics()
end

-- Every false relic at once: well away from the sanctuaries (or survivors spot it from the start
-- and spring it on a whim), and spread out from the real relics and each other (up to a point:
-- real relics avoid the start sanctuary's quarter, so "as far from them as possible" would mean
-- next to the start)
function MazeMasterAI:placeFalseRelics()
	local maze = self.maze
	for _ = 1, self.tools.falseRelicsLeft do
		local best, bestScore
		for x = 1, maze.n do
			for z = 1, maze.n do
				if not self.objectives:CanPlaceFalseRelic(x, z) then continue end
				local fromSanctuaries = math.huge
				for _, sanctuary in maze.sanctuaries do
					fromSanctuaries = math.min(fromSanctuaries, math.abs(sanctuary.x - x) + math.abs(sanctuary.z - z))
				end
				if fromSanctuaries < FAKE_SANCTUARY_GAP then continue end
				local fromRelics = math.huge
				for _, relic in maze.relics do
					if not relic.collected then fromRelics = math.min(fromRelics, math.abs(relic.x - x) + math.abs(relic.z - z)) end
				end
				for _, relic in self.objectives.fakes do
					fromRelics = math.min(fromRelics, math.abs(relic.x - x) + math.abs(relic.z - z))
				end
				local score = math.min(fromRelics, Config.RELIC_SPACING + 1) + math.random() * 2   -- (spread, then at random)
				if not bestScore or score > bestScore then best, bestScore = { x, z }, score end
			end
		end
		if not best then return end
		self.tools.readyAt.FalseRelic = nil      -- (placing several at the start: no cooldown between)
		if self.tools:Use("FalseRelic", cellCenter(maze, best[1], best[2])) then note(("false relic at %d,%d"):format(best[1], best[2])) end
	end
end

---------------------------------------------------------------- thinking
function MazeMasterAI:Step(dt)
	if not self.tools.active then return end
	self.timer += dt
	if self.timer < THINK_EVERY then return end
	self.timer = 0
	local now = os.clock()

	-- who the monster side can see right now (and remember where)
	local seen = {}
	for _, survivor in self.survivors() do
		local root = rootOf(survivor)
		if root and self.sees(root.Position, survivor) then
			table.insert(seen, { survivor = survivor, root = root })
			self.lastSeen[survivor] = { pos = root.Position, at = now }
		end
	end
	for survivor, memory in self.lastSeen do
		if now - memory.at > MEMORY or not survivor.Parent then self.lastSeen[survivor] = nil end
	end

	self:crush(seen)
	self:haunt(seen)
	if not self:cutOffChases(seen) then self:idleDoor(now) end
	self:ward(now)
end

-- CRUSHING WALLS: will a seen survivor be between the walls when they slam?
function MazeMasterAI:crush(seen)
	if #seen == 0 or not self:ready("Crusher") then return end
	local S = self.maze.S
	local lead = Config.CRUSHER_WARNING + Config.CRUSHER_SLAM_TIME * 0.6
	for id, crusher in self.crushers.list do
		if crusher.state ~= "idle" then continue end
		for _, s in seen do
			local velocity = s.root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
			local function between(p)
				local offset = (p - crusher.center) * Vector3.new(1, 0, 1)
				local across = math.abs(offset:Dot(crusher.inward))
				local along = (offset - crusher.inward * offset:Dot(crusher.inward)).Magnitude
				return across < S / 2 - 1.5 and along < S / 2 - 1
			end
			-- where they'll be as it slams, and (for someone standing still) where they are
			local later = s.root.Position + velocity * lead
			if between(later) or (velocity.Magnitude < 2 and between(s.root.Position)) then
				if self.tools:Use("Crusher", id) then note("crusher " .. id .. " on " .. s.survivor.Name) return end
			end
		end
	end
end

-- HAUNT: a seen survivor, preferring the one nearest a monster
function MazeMasterAI:haunt(seen)
	if #seen == 0 or not self:ready("Haunt") then return end
	local nowServer = workspace:GetServerTimeNow()
	local best, bestScore
	for _, s in seen do
		if (s.survivor:GetAttribute("HauntedUntil") or 0) > nowServer then continue end
		local nearest = math.huge
		for _, monster in self.monsters do
			if monster.pos then nearest = math.min(nearest, ((monster.pos - s.root.Position) * Vector3.new(1, 0, 1)).Magnitude) end
		end
		if not bestScore or nearest < bestScore then best, bestScore = s, nearest end
	end
	if best and self.tools:Use("Haunt", best.survivor.UserId) then note("haunt " .. best.survivor.Name) end
end

-- DOORS, in a chase: shut the open doors just ahead of a chased survivor. Returns true if anyone
-- is being chased (so the idle door shifting waits).
function MazeMasterAI:cutOffChases(seen)
	local maze = self.maze
	local chased = false
	for _, s in seen do
		local sx, sz = cellOf(maze, s.root.Position)
		-- the nearest monster, by walking distance
		local fromMonster, monsterSteps = nil, math.huge
		for _, monster in self.monsters do
			if monster.pos then
				local mx, mz = cellOf(maze, monster.pos)
				local dist = stepsFrom(maze, mx, mz, CHASE_STEPS + DOOR_AHEAD_MAX + 2)
				local steps = dist[key(sx, sz)]
				if steps and steps <= CHASE_STEPS and steps < monsterSteps then fromMonster, monsterSteps = dist, steps end
			end
		end
		if not fromMonster then continue end
		chased = true
		if not self:ready("Door") then continue end
		-- open doors a few cells ahead of them: both sides further from the monster than they are
		local fromSurvivor = stepsFrom(maze, sx, sz, DOOR_AHEAD_MAX + 1)
		local best, bestAhead
		for id, door in self.doors.list do
			if not door.open or door.state ~= "open" or os.clock() < (door.restUntil or 0) then continue end
			local a, b = key(door.x, door.z), key(door.x + door.d[1], door.z + door.d[2])
			local ahead = math.min(fromSurvivor[a] or math.huge, fromSurvivor[b] or math.huge)
			if ahead < DOOR_AHEAD_MIN or ahead > DOOR_AHEAD_MAX then continue end
			local monsterA, monsterB = fromMonster[a] or math.huge, fromMonster[b] or math.huge
			if math.min(monsterA, monsterB) <= monsterSteps then continue end   -- behind them, or the monster's side
			if not bestAhead or ahead < bestAhead then best, bestAhead = id, ahead end
		end
		if best and self.tools:Use("Door", best) then
			note(("door %d shut %d ahead of %s (monster %d behind)"):format(best, bestAhead, s.survivor.Name, monsterSteps))
			return true
		end
	end
	return chased
end

-- DOORS, otherwise: now and then shift a door near where a survivor was last seen
function MazeMasterAI:idleDoor(now)
	if now < self.nextIdleDoor or not self:ready("Door") then return end
	self.nextIdleDoor = now + IDLE_DOOR_EVERY[1] + math.random() * (IDLE_DOOR_EVERY[2] - IDLE_DOOR_EVERY[1])
	local maze = self.maze
	local near, any = {}, {}
	for id, door in self.doors.list do
		if (door.state ~= "open" and door.state ~= "closed") or now < (door.restUntil or 0) then continue end
		table.insert(any, id)
		for _, memory in self.lastSeen do
			local x, z = cellOf(maze, memory.pos)
			if math.max(math.abs(x - door.x), math.abs(z - door.z)) <= IDLE_DOOR_NEAR then
				table.insert(near, id)
				break
			end
		end
	end
	local pool = #near > 0 and near or any
	if #pool > 0 then
		local id = pool[math.random(#pool)]
		if self.tools:Use("Door", id) then note("door " .. id .. " shifted" .. (#near > 0 and " near a sighting" or "")) end
	end
end

-- WARDS: junctions nothing watches yet, near last sightings or on the way to relics
function MazeMasterAI:ward(now)
	if not self:ready("Ward") then return end
	local maze, wards = self.maze, self.wards
	local function wardNear(x, z, reach)
		for _, ward in wards.list do
			if math.max(math.abs(ward.x - x), math.abs(ward.z - z)) <= reach then return true end
		end
		return false
	end
	-- sightings no ward is watching
	local hot = {}
	for _, memory in self.lastSeen do
		local x, z = cellOf(maze, memory.pos)
		if not wardNear(x, z, WARD_MOVE_IF_UNWATCHED) then table.insert(hot, { x, z }) end
	end
	local full = #wards.list >= Config.WARDS_MAX
	if full and (#hot == 0 or now < (self.nextWardMove or 0)) then return end   -- all out, nothing new to watch

	local ringCells = Config.RELIC_VISION_RADIUS / maze.S     -- the Maze Master already sees this far round relics
	local best, bestScore
	for x = 1, maze.n do
		for z = 1, maze.n do
			if MazeLayout.openSides(maze.walls, x, z) < 3 or not wards:CanPlace(x, z) then continue end
			if wardNear(x, z, WARD_SPACING) then continue end
			if now - (wards.destroyedAt[key(x, z)] or -math.huge) < WARD_REPLACE_AFTER then continue end
			local center = cellCenter(maze, x, z)
			local score = math.random() * 0.5
			-- not somewhere already seen (relic rings, crushing walls, monsters)
			local watched = false
			for _, relic in maze.relics do
				if not relic.collected and (relic.center - center).Magnitude < Config.RELIC_VISION_RADIUS then watched = true end
			end
			for _, monster in self.monsters do
				if monster.pos and ((monster.pos - center) * Vector3.new(1, 0, 1)).Magnitude < 25 then watched = true end
			end
			if watched then continue end
			-- near a sighting no ward is watching: the best spot of all
			for _, h in hot do
				local d = math.abs(h[1] - x) + math.abs(h[2] - z)
				if d <= 4 then score += 10 - d end
			end
			-- on the way to a relic (just outside the area already watched round it)
			for _, relic in maze.relics do
				if relic.collected then continue end
				local d = math.max(math.abs(relic.x - x), math.abs(relic.z - z))
				if d <= ringCells + 2 then score += 3 end
			end
			-- busier junctions see more
			score += MazeLayout.openSides(maze.walls, x, z) - 3
			if not bestScore or score > bestScore then best, bestScore = { x, z }, score end
		end
	end
	if not best then return end
	if full then
		-- moving one: only if the new spot really watches a fresh sighting
		local close = false
		for _, h in hot do
			if math.abs(h[1] - best[1]) + math.abs(h[2] - best[2]) <= WARD_MOVE_IF_UNWATCHED then close = true end
		end
		if not close then return end
		self.nextWardMove = now + WARD_MOVE_EVERY
	end
	if self.tools:Use("Ward", cellCenter(maze, best[1], best[2])) then
		note(("ward at %d,%d%s"):format(best[1], best[2], full and " (moved toward a sighting)" or ""))
	end
end

return MazeMasterAI
