-- An AI monster that roams the maze and hunts players.
--
--   local monster = MonsterAI.new(maze, { onCatch = function(player) ... end })
--   monster:Step(dt, targets)   -- every frame; targets = the players it may hunt
--   monster:Stun(seconds)       -- can't move or catch for a while ("StunnedUntil" on the body)
--   monster:Pull(to, speed)     -- dragged in a straight line to `to` (Sara's whip); -> seconds
--   (neither while it's in the middle of a kill: monster:Killing())
--   monster:Destroy()           -- at the end of the match
--
-- A match can create as many as it likes; each keeps its own state.
--
-- It plans routes over the maze's grid of cells (the layout MazeBuilder generated), so it never
-- gets stuck on walls. To find a route it uses "breadth-first search" (BFS): explore outward from
-- the monster's cell one step at a time until reaching the target cell, then walk back along the
-- steps taken. That's always the shortest route in cells. It doesn't walk the grid stiffly,
-- though: it cuts corners whenever a straight line is clear, and if it has a clear line to you it
-- comes straight at you from any angle.
--
-- Behaviour:
--   ROAM   - wander the maze. With other monsters about (options.pack), it heads for places far
--            from them and from where they're going, so a pack spreads out and covers the maze
--   CHASE  - it saw you (line of sight) or heard you (very close, even through walls)
--   SEARCH - lost you: go to where it last saw you, then go back to roaming
-- If it gets close enough to you, you're caught (what that means is up to the match: onCatch).
--
-- This module doesn't move the model itself. Roblox sends an anchored part's position to players
-- only every other frame or so, which looks jittery. Instead it publishes where the monster should
-- be in a "Pivot" attribute (and its behaviour in "Mode"), and the MonsterAnimate script on each
-- player's computer moves the model smoothly between those updates and animates its limbs.

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local Config = require(game:GetService("ReplicatedStorage").Config)
local Heroes = require(game:GetService("ReplicatedStorage").Heroes)
local Abilities = require(ServerStorage.Abilities)

local ROAM_SPEED   = 15     -- studs per second (players walk at Config.PLAYER_SPEED)
local SEARCH_SPEED = 18
-- Chase speed is relative to the WalkSpeed of the player being chased: it starts a bit slower than
-- you, then speeds up the longer the chase lasts, until it's faster than you. So escaping takes
-- breaking line of sight early, not just outrunning it.
local CHASE_START  = 0.85   -- starts at 85% of your speed...
local CHASE_RAMP   = 0.03   -- ...gains 3% of your speed for every second of chasing...
local CHASE_MAX    = 1.15   -- ...up to 115% of your speed (reached after 10 seconds)
local SIGHT_RANGE  = 60     -- sees you this far if no wall is in the way
local HEAR_RANGE   = 14     -- notices you this close even through walls
local LOSE_AFTER   = 4      -- seconds without seeing you before it stops chasing
local CATCH_DIST   = 6      -- how close counts as caught
local CATCH_GRACE  = 4      -- seconds it ignores a player it just caught
local HOVER        = 3.2    -- how high the fallback orb floats above the floor (and its eye height)
local BODY_RADIUS  = 4      -- how wide it is, for checking it can fit past wall corners
local RIG_SCALE    = 1.8    -- the rig is scaled up by this much (bigger = longer, slower strides)
local TURN_SPEED   = 8      -- how quickly it turns to face where it's going
local ROAM_CHOICES = 12     -- when roaming with other monsters, how many random cells it weighs up

-- THE KILL (the stand-in monster): when it catches someone it stops, lifts them over its head, and
-- tears them apart. Times in seconds from the catch. MonsterAnimate draws it on players' computers
-- (arms, victim and pieces); Match freezes the victim and decides what happens to them afterwards.
-- A hero monster has its own kill (its HeroData's "kill", e.g. Fear Eater's Devour), with at
-- least DONE (it moves again) and RELEASE (the victim's body is let go of).
local KILL = {
	LIFT = 0.7,   -- raising them overhead
	RIP  = 1.7,   -- the moment they're torn apart
	DONE = 2.6,   -- it starts moving again
}
KILL.RELEASE = KILL.RIP

local DIRS = { {0, -1, "N"}, {1, 0, "E"}, {0, 1, "S"}, {-1, 0, "W"} }

local MonsterAI = {}
MonsterAI.__index = MonsterAI
MonsterAI.KILL = KILL

---------------------------------------------------------------- the body
local function finishBody(model)
	model.Name = "Monster"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent  -- clients always know where it is (for pings)
	CollectionService:AddTag(model, "Monster")       -- the ping and animate scripts look for this
	CollectionService:AddTag(model, "HiddenByFog")   -- the fog script hides it unless you can see it
	model.Parent = workspace
	return model
end

-- A copy of a monster rig: ServerStorage.MonsterRig (the stand-in creature), or a hero's own body
-- (its HeroData's "rig"). Its HumanoidRootPart stays anchored; the other body parts hang off it on
-- joints that MonsterAnimate (or the hero's HeroVisuals module) bends. A rig that floats says how
-- high in a "GroundOffset" attribute (studs from the floor to its root, before scaling).
-- Returns model, groundOffset (how far its pivot sits above the floor), or nil if the rig is unusable.
local function buildFromRig(template, scale)
	local model = template:Clone()
	model:ScaleTo(model:GetScale() * scale)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root then
		warn(template.Name .. " needs a HumanoidRootPart; using the orb instead")
		model:Destroy()
		return nil
	end
	model.PrimaryPart = root
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = d == root
			d.CanCollide, d.CanTouch, d.CanQuery = false, false, false
			d.CastShadow = false   -- a shadow would give its position away through the fog
			d.Massless = true
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()            -- e.g. a default "Animate" script; MonsterAnimate does the animating
		end
	end
	if humanoid then
		humanoid.EvaluateStateMachine = false     -- no physics/falling logic: we position it ourselves
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None   -- no name or health bar
		humanoid.BreakJointsOnDeath = false
	end

	local groundOffset = model:GetAttribute("GroundOffset")
	if groundOffset then
		groundOffset *= scale
	else
		local cf, size = model:GetBoundingBox()
		groundOffset = model:GetPivot().Position.Y - (cf.Position.Y - size.Y / 2)
	end

	local glow = Instance.new("PointLight")  -- a faint red glow
	glow.Color = Color3.fromRGB(255, 40, 40)
	glow.Range = 10
	glow.Brightness = 1
	glow.Parent = root

	return finishBody(model), groundOffset
end

-- The fallback body: a floating orb with glowing eyes
local function buildOrb()
	local model = Instance.new("Model")
	local function piece(name, shape, size, offset, color, material)
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = shape
		p.Size = size
		p.CFrame = CFrame.new(offset)
		p.Color = color
		p.Material = material
		p.Anchored = true
		p.CanCollide, p.CanTouch, p.CanQuery = false, false, false
		p.CastShadow = false
		p.Parent = model
		return p
	end
	local body = piece("Body", Enum.PartType.Ball, Vector3.new(5, 5, 5), Vector3.zero,
		Color3.fromRGB(40, 15, 50), Enum.Material.SmoothPlastic)
	piece("EyeL", Enum.PartType.Ball, Vector3.new(0.9, 0.9, 0.9), Vector3.new(-0.9, 0.6, -2.1),
		Color3.fromRGB(255, 40, 40), Enum.Material.Neon)
	piece("EyeR", Enum.PartType.Ball, Vector3.new(0.9, 0.9, 0.9), Vector3.new(0.9, 0.6, -2.1),
		Color3.fromRGB(255, 40, 40), Enum.Material.Neon)
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 40, 40)
	glow.Range = 12
	glow.Brightness = 1.5
	glow.Parent = body
	model.PrimaryPart = body
	return finishBody(model)
end

-- A monster's body (its hero's rig, the stand-in rig, or the orb if neither is there), placed in
-- the workspace and tagged for the animate, ping and fog scripts. Its hero's id is in its "Hero"
-- attribute. Also used for monsters played by people (PlayerMonster).
-- Returns model, groundOffset (how far its pivot sits above the floor), isRig
function MonsterAI.buildBody(heroId)
	local hero = Heroes.get(heroId)
	local template = hero and hero.rig and ServerStorage:FindFirstChild(hero.rig)
	local scale = hero and hero.rigScale or 1
	if not template then
		template, scale = ServerStorage:FindFirstChild("MonsterRig"), RIG_SCALE
		hero = nil                                 -- (the stand-in body moves like the stand-in)
	end
	local model, groundOffset
	if template then
		local clone = template:Clone()             -- (the attribute has to be there before it's in the workspace)
		clone:SetAttribute("Hero", hero and hero.id or nil)
		model, groundOffset = buildFromRig(clone, scale)
		clone:Destroy()
	end
	if model then return model, groundOffset, true end
	return buildOrb(), 0, false
end

-- The kill timing for a monster of this hero (its own, or the stand-in's)
function MonsterAI.killFor(heroId)
	local hero = Heroes.get(heroId)
	return hero and hero.kill or KILL
end
MonsterAI.HOVER = HOVER

---------------------------------------------------------------- helpers
local function rootOf(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return character:FindFirstChild("HumanoidRootPart"), humanoid
	end
end

---------------------------------------------------------------- construction
-- maze: the table MazeBuilder.build returns.
-- options.onCatch(player, monster): called when it catches someone (default: knock them out).
--   The monster then stands still while the kill plays out (its kill's DONE seconds).
-- options.isBlocked(x, z): true for cells it may not enter (sanctuaries, protected relic rooms).
-- options.startCell = {x, z}: where it appears.
-- options.pack: a list of all the match's monsters (this one included), to spread out from.
-- options.spottedBySide(player): true if the monster side can see them right now (another
-- monster, a ward, a crushing wall): it goes after them as if it saw them itself, when near.
-- options.hero: its hero's id (ReplicatedStorage.Heroes). A hero whose Primary is Devour catches
-- only with Devour (it dashes at you once you're in range); otherwise it catches anyone who gets
-- within CATCH_DIST, like the stand-in.
-- options.castsAbilities: also uses its hero's Secondary and Ultimate (for now only Fear Eater's):
-- Instill Fear whenever it's ready, Living Nightmare whenever it's ready and a survivor is feared.
function MonsterAI.new(maze, options)
	options = options or {}
	local self = setmetatable({}, MonsterAI)
	self.maze = maze
	self.isBlocked = options.isBlocked or function() return false end
	self.pack = options.pack or {}
	self.spottedBySide = options.spottedBySide
	self.onCatch = options.onCatch or function(player)
		local _, humanoid = rootOf(player)
		if humanoid then humanoid.Health = 0 end
	end

	self.rayParams = RaycastParams.new()
	self.rayParams.FilterType = Enum.RaycastFilterType.Include
	self.rayParams.FilterDescendantsInstances = { maze.model }

	self.hero = options.hero
	self.model, self.groundOffset, self.isRig = MonsterAI.buildBody(self.hero)
	self.kill = MonsterAI.killFor(self.model:GetAttribute("Hero"))
	local heroDef = Heroes.get(self.model:GetAttribute("Hero"))
	local primary = heroDef and heroDef.abilities.Primary
	self.devourDef = primary and primary.id == "Devour" and primary or nil
	self.castsAbilities = options.castsAbilities == true

	local start = options.startCell or { math.ceil(maze.n / 2), math.ceil(maze.n / 2) }
	self.pos = self:centerOf(start[1], start[2])
	self.facing = Vector3.new(0, 0, -1)
	self.path = {}            -- list of {x, z} cells still to walk through
	self.mode = "roam"
	self.chaseTarget, self.targetCell, self.lastSeenAt = nil, nil, 0
	self.chaseStartedAt = 0
	self.detectTimer = 0
	self.graceUntil = {}
	self.active = true        -- false = stands still and ignores players (e.g. during the countdown)
	self:publish(os.clock())
	return self
end

function MonsterAI:Destroy()
	if self.model then self.model:Destroy() end
	self.model = nil
end

---------------------------------------------------------------- grid helpers
function MonsterAI:cellOf(p)
	local maze = self.maze
	local x = math.clamp(math.floor((p.X + maze.half) / maze.S) + 1, 1, maze.n)
	local z = math.clamp(math.floor((p.Z + maze.half) / maze.S) + 1, 1, maze.n)
	return x, z
end

function MonsterAI:centerOf(x, z)
	local maze = self.maze
	return Vector3.new((x - 0.5) * maze.S - maze.half, maze.floorY, (z - 0.5) * maze.S - maze.half)
end

-- Shortest route from one cell to another (list of cells, not including the start)
function MonsterAI:findPath(sx, sz, tx, tz)
	local walls = self.maze.walls
	if sx == tx and sz == tz then return {} end
	local function key(x, z) return x * 1000 + z end
	local cameFrom = { [key(sx, sz)] = false }
	local queue, head = { {sx, sz} }, 1
	while head <= #queue do
		local c = queue[head]
		head += 1
		if c[1] == tx and c[2] == tz then break end
		for _, d in DIRS do
			if not walls[c[1]][c[2]][d[3]] then          -- no wall on that side = can walk through
				local nx, nz = c[1] + d[1], c[2] + d[2]
				if cameFrom[key(nx, nz)] == nil and not self.isBlocked(nx, nz) then
					cameFrom[key(nx, nz)] = c
					table.insert(queue, {nx, nz})
				end
			end
		end
	end
	if cameFrom[key(tx, tz)] == nil then return {} end
	local route, c = {}, {tx, tz}
	while c and not (c[1] == sx and c[2] == sz) do
		table.insert(route, 1, c)
		c = cameFrom[key(c[1], c[2])]
	end
	return route
end

-- A door opened or closed (see Doors): the route it's following may be wrong now, so plan afresh
function MonsterAI:MazeChanged()
	self.path = {}
end

---------------------------------------------------------------- stun and pull
-- Mid-kill, a monster can't be stunned or pulled: the kill plays out (the survivor has already
-- lost the life), and it's only after that that it's free to be pushed around.
function MonsterAI:Killing()
	return self.killUntil ~= nil and os.clock() < self.killUntil
end

function MonsterAI:Stun(seconds)
	if self:Killing() then return end
	self.dash = nil
	self.stunUntil = math.max(self.stunUntil or 0, os.clock() + seconds)
	if self.model then
		self.model:SetAttribute("StunnedUntil", workspace:GetServerTimeNow() + (self.stunUntil - os.clock()))
	end
end

function MonsterAI:Pull(to, speed)
	if self:Killing() then return 0 end
	local target = Vector3.new(to.X, self.pos.Y, to.Z)
	local distance = (target - self.pos).Magnitude
	if distance < 0.5 then return 0 end
	self.dash = nil
	self.pull = { from = self.pos, to = target, startedAt = os.clock(), time = distance / speed }
	if self.model then   -- (players' computers draw the drag: dust and a scrape)
		self.model:SetAttribute("PullAt", workspace:GetServerTimeNow())
		self.model:SetAttribute("PullTime", self.pull.time)
	end
	return self.pull.time
end

---------------------------------------------------------------- senses
-- revealed: the survivor is revealed to the monster side (a false relic, feared...) or their side
-- can see them (another monster, a ward, a crushing wall: options.spottedBySide): seen within
-- Config.REVEALED_CHASE_RANGE even through walls
function MonsterAI:canDetect(root, revealed)
	local eye = self.pos + Vector3.new(0, HOVER, 0)
	local offset = root.Position - eye
	local flat = Vector3.new(offset.X, 0, offset.Z).Magnitude
	if flat <= HEAR_RANGE then return true end
	if revealed then return flat <= Config.REVEALED_CHASE_RANGE end
	if flat > SIGHT_RANGE then return false end
	return workspace:Raycast(eye, offset, self.rayParams) == nil   -- nothing in the way = it can see you
end

-- Can the monster's body travel in a straight line from a to b without touching a wall?
-- (A "spherecast" sweeps a ball along the line, so it accounts for the monster's width.)
-- It also mustn't cut through a cell it's not allowed into.
function MonsterAI:canPass(a, b)
	local from = a + Vector3.new(0, BODY_RADIUS + 0.6, 0)   -- ball clears the floor, below wall tops
	local offset = (b - a) * Vector3.new(1, 0, 1)
	if offset.Magnitude < 0.1 then return true end
	if self.nightmareUntil then return self:canPassNightmare(a, b) end
	-- check the cells along the line (and the body's width either side) every couple of studs
	local side = Vector3.new(-offset.Z, 0, offset.X).Unit * BODY_RADIUS
	local steps = math.ceil(offset.Magnitude / 2)
	for i = 0, steps do
		local p = a + offset * (i / steps)
		for _, q in { p, p + side, p - side } do
			if self.isBlocked(self:cellOf(q)) then return false end
		end
	end
	return workspace:Spherecast(from, BODY_RADIUS, offset, self.rayParams) == nil
end

-- In Living Nightmare: through inner walls and doors, so only the cells matter - none it may not
-- enter (sanctuaries), and nothing outside the maze (the outer wall), along the line or the body's
-- width either side
function MonsterAI:canPassNightmare(a, b)
	local maze = self.maze
	local offset = (b - a) * Vector3.new(1, 0, 1)
	if offset.Magnitude < 0.1 then return true end
	local side = Vector3.new(-offset.Z, 0, offset.X).Unit * BODY_RADIUS
	local steps = math.ceil(offset.Magnitude / 2)
	for i = 0, steps do
		local p = a + offset * (i / steps)
		for _, q in { p, p + side, p - side } do
			if math.abs(q.X) > maze.half - 1 or math.abs(q.Z) > maze.half - 1 then return false end
			if self.isBlocked(self:cellOf(q)) then return false end
		end
	end
	return true
end

---------------------------------------------------------------- abilities (castsAbilities)
-- Instill Fear on cooldown; Living Nightmare when it's ready and any survivor is feared
function MonsterAI:castAbilities(targets)
	if self.dash or self.killUntil then return end
	if Abilities.ready(self, "Secondary") then
		Abilities.useMonster(self, "Secondary", self.facing)
	end
	if not self.nightmareUntil and Abilities.ready(self, "Ultimate") then
		local now = workspace:GetServerTimeNow()
		for _, player in targets do
			if (player:GetAttribute("FearedUntil") or 0) > now then
				Abilities.useMonster(self, "Ultimate", self.facing)
				break
			end
		end
	end
end

-- Stand still for `seconds` (casting)
function MonsterAI:Cast(seconds)
	self.castUntil = os.clock() + seconds
end

-- LIVING NIGHTMARE (HeroAbilities.FearEater): for def.duration it goes straight through inner
-- walls and doors (canPass only minds sanctuaries and the outer wall), and chases feared
-- survivors def.speedBoost faster. (onEnd is for monster players; it sorts itself out: endNightmare.)
function MonsterAI:Nightmare(def)
	if not self.active or self.killUntil or self.pull or os.clock() < (self.stunUntil or 0) then return false end
	self.nightmareUntil = os.clock() + def.duration
	self.nightmareBoost = def.speedBoost
	self.path = {}
	local untilServer = workspace:GetServerTimeNow() + def.duration
	self.model:SetAttribute("NightmareUntil", untilServer)
	self.model:SetAttribute("CastKind", "LivingNightmare")
	self.model:SetAttribute("CastAt", workspace:GetServerTimeNow())
	return true
end

function MonsterAI:Nightmaring()
	return self.nightmareUntil ~= nil and os.clock() < self.nightmareUntil
end

-- It wore off: if it's inside a wall, out into the middle of its cell; then plan routes afresh
function MonsterAI:endNightmare()
	self.nightmareUntil, self.nightmareBoost = nil, nil
	self.model:SetAttribute("NightmareUntil", nil)
	self.path = {}
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { self.maze.model }
	local stuck = false
	for _, part in workspace:GetPartBoundsInRadius(self.pos + Vector3.new(0, 3, 0), BODY_RADIUS * 0.6, params) do
		if part.CanCollide and (part.Name == "Wall" or part.Name == "Door") then stuck = true break end
	end
	if stuck then self.pos = self:centerOf(self:cellOf(self.pos)) end
end

---------------------------------------------------------------- publishing to clients
function MonsterAI:publish(now)
	local model = self.model
	if not model then return end
	-- The rig stands on the floor; the orb floats and bobs. Both face the way they're moving.
	local at = self.isRig and self.pos + Vector3.new(0, self.groundOffset, 0)
		or self.pos + Vector3.new(0, HOVER + math.sin(now * 3) * 0.3, 0)
	local pivot = CFrame.lookAt(at, at + self.facing)
	if model:GetAttribute("Pivot") ~= pivot then
		model:SetAttribute("Pivot", pivot)
	end
	if model:GetAttribute("Mode") ~= self.mode then
		model:SetAttribute("Mode", self.mode)   -- "roam" / "chase" / "search", e.g. so it reaches for you while chasing
	end
end

-- Where to roam next: a random cell it's allowed into. With other monsters about, it weighs up
-- several random cells and takes the one furthest from the others - both where they are and
-- where they're heading - so they spread out instead of bunching up.
function MonsterAI:pickRoamCell()
	local maze = self.maze
	local function randomCell()
		local tx, tz
		for _ = 1, 20 do
			tx, tz = math.random(maze.n), math.random(maze.n)
			if not self.isBlocked(tx, tz) then break end
		end
		return tx, tz
	end
	local others = {}
	for _, other in self.pack do
		if other ~= self and other.model then
			table.insert(others, { self:cellOf(other.pos) })
			if other.roamGoal then table.insert(others, other.roamGoal) end
		end
	end
	if #others == 0 then return randomCell() end
	local bestX, bestZ, bestScore
	for _ = 1, ROAM_CHOICES do
		local tx, tz = randomCell()
		local nearest = math.huge
		for _, c in others do
			nearest = math.min(nearest, math.abs(c[1] - tx) + math.abs(c[2] - tz))
		end
		if not bestScore or nearest > bestScore then bestX, bestZ, bestScore = tx, tz, nearest end
	end
	return bestX, bestZ
end

---------------------------------------------------------------- every frame
-- targets: the players it's allowed to hunt
function MonsterAI:Step(dt, targets)
	if not (self.model and self.maze.model.Parent) then return end
	local now = os.clock()
	if not self.active then
		self:publish(now)
		return
	end
	-- In the middle of a kill: stand still until it's over
	if self.killUntil then
		if now < self.killUntil then
			self:publish(now)
			return
		end
		self.killUntil = nil
		self.mode = "roam"
		self.model:SetAttribute("KillVictim", nil)
		self.model:SetAttribute("KillStart", nil)
	end
	-- Mid-Devour: the dash, nothing else
	if self.dash then
		self:stepDash(now, targets)
		self:publish(now)
		return
	end
	-- Being pulled (a whip): dragged along, nothing else
	if self.pull then
		local k = math.clamp((now - self.pull.startedAt) / self.pull.time, 0, 1)
		self.pos = self.pull.from:Lerp(self.pull.to, k)
		if k >= 1 then
			self.pull = nil
			self.path = {}
		end
		self:publish(now)
		return
	end
	-- Stunned: stands still and catches nobody
	if now < (self.stunUntil or 0) then
		self:publish(now)
		return
	end
	-- Casting (Instill Fear): stands still
	if now < (self.castUntil or 0) then
		self:publish(now)
		return
	end
	if self.castsAbilities then self:castAbilities(targets) end
	if self.nightmareUntil and now >= self.nightmareUntil then self:endNightmare() end
	local maze = self.maze

	-- The player it was chasing is out of reach (reached safety, caught, left): give up on them
	-- and search around where it last saw them instead
	if self.chaseTarget and not table.find(targets, self.chaseTarget) then
		self.chaseTarget = nil
		if self.mode == "chase" then
			self.mode = "search"
			self.path = {}
		end
	end

	-- 1. SENSES (5 times a second): pick the closest player it can detect
	self.detectTimer -= dt
	if self.detectTimer <= 0 then
		self.detectTimer = 0.2
		local best, bestDist
		for _, player in targets do
			local root = rootOf(player)
			local revealed = root and ((player:GetAttribute("RevealedUntil") or 0) > workspace:GetServerTimeNow()
				or (self.spottedBySide ~= nil and self.spottedBySide(player)))
			if root and (self.graceUntil[player] or 0) < now and self:canDetect(root, revealed) then
				local d = (root.Position - self.pos).Magnitude
				if not bestDist or d < bestDist then best, bestDist = player, d end
			end
		end
		if best then
			if self.mode ~= "chase" then
				self.path = {}
				self.chaseStartedAt = now                  -- a new chase: start slow again
			end
			self.mode, self.chaseTarget, self.lastSeenAt = "chase", best, now
			local tx, tz = self:cellOf(rootOf(best).Position)
			if not self.targetCell or self.targetCell[1] ~= tx or self.targetCell[2] ~= tz then
				self.path = {}                             -- you moved to another cell: re-plan
			end
			self.targetCell = { tx, tz }
		elseif self.mode == "chase" and now - self.lastSeenAt > LOSE_AFTER then
			self.mode = "search"                       -- head for where it last saw you
			self.path = {}
		end
	end

	-- 2. DECIDE where to move next
	local cx, cz = self:cellOf(self.pos)
	local goal, speed
	local targetRoot = self.chaseTarget and rootOf(self.chaseTarget)
	local targetFloor = targetRoot and Vector3.new(targetRoot.Position.X, maze.floorY, targetRoot.Position.Z)
	local sameCell = false
	if targetFloor then
		local tx, tz = self:cellOf(targetFloor)
		sameCell = tx == cx and tz == cz
	end
	if self.mode == "chase" and targetFloor and now - self.lastSeenAt < 0.5
		and (sameCell or self:canPass(self.pos, targetFloor)) then
		-- A clear straight line to you (or you're in its cell, which has no walls inside): go
		-- directly for you, in any direction
		goal = targetFloor
		self.path = {}
	else
		if #self.path == 0 then
			if (self.mode == "chase" or self.mode == "search") and self.targetCell then
				self.path = self:findPath(cx, cz, self.targetCell[1], self.targetCell[2])
				if #self.path == 0 and self.mode == "search" then self.mode = "roam" end   -- reached it, nobody here
			end
			if self.mode == "roam" and #self.path == 0 then
				local tx, tz = self:pickRoamCell()
				self.roamGoal = { tx, tz }
				self.path = self:findPath(cx, cz, tx, tz)
			end
			-- if we're off-centre (e.g. after lunging at a player), go back to the cell centre first
			if #self.path > 0 and (self.pos - self:centerOf(cx, cz)).Magnitude > 0.5 then
				table.insert(self.path, 1, { cx, cz })
			end
		end
		-- Cut corners: skip ahead along the route while the cell after next is in a clear straight
		-- line, so it moves diagonally and smoothly instead of centre-to-centre in 4 directions
		local path = self.path
		while #path >= 2 and self:canPass(self.pos, self:centerOf(path[2][1], path[2][2])) do
			table.remove(path, 1)
		end
		goal = path[1] and self:centerOf(path[1][1], path[1][2])
	end
	if self.mode == "chase" then
		local _, targetHumanoid = rootOf(self.chaseTarget)
		local playerSpeed = targetHumanoid and targetHumanoid.WalkSpeed or 16
		local ratio = math.min(CHASE_START + CHASE_RAMP * (now - self.chaseStartedAt), CHASE_MAX)
		speed = playerSpeed * ratio
		-- Living Nightmare: much faster after a feared survivor
		if self.nightmareUntil and (self.chaseTarget:GetAttribute("FearedUntil") or 0) > workspace:GetServerTimeNow() then
			speed *= 1 + (self.nightmareBoost or 0)
		end
	else
		speed = (self.mode == "search" and SEARCH_SPEED) or ROAM_SPEED
	end

	-- 3. MOVE toward the goal
	if goal then
		local toGoal = goal - self.pos
		local step = speed * dt
		if toGoal.Magnitude <= step then
			self.pos = goal
			if self.path[1] then table.remove(self.path, 1) end
		else
			self.pos += toGoal.Unit * step
		end
		-- turn smoothly toward the way it's going rather than snapping
		if toGoal.Magnitude > 0.05 then
			local facing = self.facing:Lerp(toGoal.Unit, math.min(1, dt * TURN_SPEED))
			self.facing = facing.Magnitude > 0.01 and facing.Unit or toGoal.Unit
		end
	end

	self:publish(now)

	-- 4. CATCH: Devour at the one it's chasing once they're in range (a Devour hero), or anyone
	-- close enough (the stand-in)
	if self.devourDef then
		self:tryDevour(targets)
		return
	end
	for _, player in targets do
		local root = rootOf(player)
		if root and (self.graceUntil[player] or 0) < now then
			local flat = Vector3.new(root.Position.X - self.pos.X, 0, root.Position.Z - self.pos.Z).Magnitude
			if flat < CATCH_DIST then
				self:catch(player, root, now)
				break                                  -- one at a time
			end
		end
	end
end

-- Caught someone: turn to face them and start the kill (players' computers animate it from these)
function MonsterAI:catch(player, root, now)
	self.graceUntil[player] = now + CATCH_GRACE
	self.chaseTarget, self.path, self.dash = nil, {}, nil
	local toThem = Vector3.new(root.Position.X - self.pos.X, 0, root.Position.Z - self.pos.Z)
	if toThem.Magnitude > 0.1 then self.facing = toThem.Unit end
	self.mode = "kill"
	self.killUntil = now + self.kill.DONE
	self.model:SetAttribute("KillVictim", player.UserId)
	self.model:SetAttribute("KillStart", workspace:GetServerTimeNow())
	self:publish(now)
	self.onCatch(player, self)
end

---------------------------------------------------------------- Devour
-- Chasing someone within Devour's reach (or a feared survivor within its feared reach), in a clear
-- line, with Devour ready: dash at them, aiming a little ahead of where they're running.
function MonsterAI:tryDevour(targets)
	local def = self.devourDef
	if self.mode ~= "chase" or not self.chaseTarget or not Abilities.ready(self, "Primary") then return end
	local root = rootOf(self.chaseTarget)
	if not root then return end
	local feared = (self.chaseTarget:GetAttribute("FearedUntil") or 0) > workspace:GetServerTimeNow()
	local target = Vector3.new(root.Position.X, self.pos.Y, root.Position.Z)
	local d = (target - self.pos).Magnitude
	if d > (feared and def.fearedRange or def.range) or not self:canPass(self.pos, target) then return end
	local lead = root.AssemblyLinearVelocity * Vector3.new(1, 0, 1) * (def.windup + def.dashTime * 0.5)
	local aim = (target + lead - self.pos) * Vector3.new(1, 0, 1)
	if aim.Magnitude < 0.1 then aim = target - self.pos end
	if aim.Magnitude < 0.1 then aim = self.facing end
	Abilities.useMonster(self, "Primary", aim.Unit)
end

-- Start a Devour dash (called by HeroAbilities.FearEater): stands still for def.windup, then dashes
-- `distance` studs along `aim` in `time` seconds, stopping at walls; the first survivor within
-- def.reach of its reach point is caught. Players' computers draw it from "DevourAt" (server time),
-- "DevourAim" (the dash: direction times distance), "DevourWindup" and "DevourTime".
function MonsterAI:Devour(aim, distance, time, def)
	if not self.active or self.killUntil or self.pull or os.clock() < (self.stunUntil or 0) then return false end
	local now = os.clock()
	self.facing = aim
	self.path = {}
	self.dash = { aim = aim, distance = distance, def = def, from = self.pos,
		start = now + def.windup, stop = now + def.windup + time, time = time }
	self.mode = "chase"
	self.model:SetAttribute("DevourAim", aim * distance)
	self.model:SetAttribute("DevourWindup", def.windup)
	self.model:SetAttribute("DevourTime", time)
	self.model:SetAttribute("DevourAt", workspace:GetServerTimeNow())
	self:publish(now)
	return true
end

function MonsterAI:stepDash(now, targets)
	local dash = self.dash
	if now < dash.start then return end                         -- gathering itself
	local k = math.clamp((now - dash.start) / dash.time, 0, 1)
	local want = dash.from + dash.aim * dash.distance * k
	if (want - self.pos).Magnitude > 0.01 then
		if self:canPass(self.pos, want) then
			self.pos = want
		else
			k = 1                                                -- hit a wall: the dash ends here
		end
	end
	-- anyone within reach of its hands
	local reachAt = self.pos + dash.aim * dash.def.reachForward
	for _, player in targets do
		local root = rootOf(player)
		if root and (self.graceUntil[player] or 0) < now and not player:GetAttribute("Seized") then
			local flat = Vector3.new(root.Position.X - reachAt.X, 0, root.Position.Z - reachAt.Z).Magnitude
			if flat < dash.def.reach then
				self:catch(player, root, now)
				return
			end
		end
	end
	if k >= 1 then
		self.dash = nil
		self.path = {}                                           -- re-plan from wherever it ended up
	end
end

return MonsterAI
