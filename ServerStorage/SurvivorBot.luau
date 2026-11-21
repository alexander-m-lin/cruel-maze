-- A SURVIVOR BOT: fills an empty survivor slot, so a match with few people still has survivors.
--
--   local bot = SurvivorBot.new(maze, objectives, number)
--   bot:LoadCharacter()          -- a fresh body (Match then places it, as for a player)
--   bot:Step(dt, monsters)       -- every frame
--   bot:Destroy()
--
-- To the rest of the game a bot passes for a player: it has a UserId (negative), a Name and
-- DisplayName ("Bot 1"...), a Character, and Get/SetAttribute. So Match, Objectives, the monsters
-- and the crushing walls treat it like any survivor without special cases. Its attributes are
-- copied onto its character model, which is tagged "SurvivorBot" (with "BotUserId"), so players'
-- computers can tell what it is (fog, minimap, the kill).
--
-- THE BRAIN (a few times a second):
--   FLEE    - sees a monster (within FLEE_SIGHT studs, in line of sight): runs to the nearest
--             sanctuary (monsters can't follow) and waits there until none has been seen for
--             SAFE_AFTER (+ up to SAFE_JITTER) seconds. It then leaves by an exit picked with
--             some randomness, favouring ones far from the monster it fled and not the one it
--             last left by (so it doesn't walk back out into the same monster again and again)
--   COLLECT - sees a relic nobody has collected: goes to it and collects it (it can be fooled by a
--             false relic, like anyone)
--   ROAM    - otherwise wanders, preferring cells it hasn't been to
-- Routes are planned over the maze's grid (shut doors block them) and re-planned every few seconds.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Config)
local Movement = require(ReplicatedStorage.Movement)   -- the same speed rules as players

local THINK_EVERY = 0.2
local REPLAN_EVERY = 3        -- seconds: re-plan the route (doors change)
local FLEE_SIGHT = 50         -- studs: sees a monster this far, in line of sight
local SAFE_AFTER = 4          -- seconds without seeing a monster before leaving a sanctuary...
local SAFE_JITTER = 4         -- ...plus up to this many more (so it doesn't come out on a beat)
local EXIT_NOISE = 60         -- studs of randomness when choosing which exit to leave by
local EYE = 3
local DIRS = { {0, -1, "N"}, {1, 0, "E"}, {0, 1, "S"}, {-1, 0, "W"} }

local SurvivorBot = {}
SurvivorBot.__index = SurvivorBot

function SurvivorBot.new(maze, objectives, number)
	local self = setmetatable({}, SurvivorBot)
	self.isBot = true
	self.UserId = -(1000 + number)
	self.Name = "Bot" .. number
	self.DisplayName = "Bot " .. number
	self.Parent = Players          -- (so "is this player still here?" checks pass)
	self.Character = nil
	self.maze, self.objectives = maze, objectives
	self.attributes = {}
	self.visited = {}
	self.path = {}
	self.mode = "roam"
	self.thinkAt, self.replanAt = 0, 0
	self.lastThreatAt = -math.huge
	self.stuckCheck = { at = 0, pos = Vector3.zero }
	self.rays = RaycastParams.new()
	self.rays.FilterType = Enum.RaycastFilterType.Include
	self.rays.FilterDescendantsInstances = { maze.model }
	return self
end

---------------------------------------------------------------- passing for a player
function SurvivorBot:GetAttribute(name) return self.attributes[name] end
function SurvivorBot:SetAttribute(name, value)
	self.attributes[name] = value
	if self.Character then self.Character:SetAttribute(name, value) end
end
function SurvivorBot:FindFirstChild() return nil end

function SurvivorBot:LoadCharacter()
	if self.Character then self.Character:Destroy() end
	-- the default avatar
	local character = Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	character.Name = self.DisplayName
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	humanoid.DisplayName = self.DisplayName .. " (bot)"
	character:SetAttribute("BotUserId", self.UserId)
	for name, value in self.attributes do character:SetAttribute(name, value) end
	CollectionService:AddTag(character, "SurvivorBot")
	character.Parent = workspace
	local root = character:FindFirstChild("HumanoidRootPart")
	if root then root:SetNetworkOwner(nil) end     -- the server moves it
	self.Character = character
	self.path = {}
	self.mode = "roam"
	self:animate(character)
	return character
end

-- ANIMATIONS: the very same Animate script players have (a server copy, ServerStorage.BotAnimate),
-- set up with the same animations a player's character gets. Its config is a StringValue per
-- animation set, holding Animation objects.
local ANIMATION_SETS = {
	idle = { Animation1 = 507766388, Animation2 = 507766666 },
	walk = { WalkAnim = 913402848 },
	run = { RunAnim = 913376220 },
	jump = { JumpAnim = 507765000 },
	fall = { FallAnim = 507767968 },
	climb = { ClimbAnim = 507765644 },
	swim = { Swim = 913384386 },
	swimidle = { SwimIdle = 913389285 },
	sit = { SitAnim = 2506281703 },
	toolnone = { ToolNoneAnim = 507768375 },
}

function SurvivorBot:animate(character)
	local template = ServerStorage:FindFirstChild("BotAnimate")
	if not template then
		warn("ServerStorage.BotAnimate is missing: survivor bots won't animate")
		return
	end
	-- the body comes with Roblox's own Animate LocalScript, which never runs in a bot: swap it out
	local inert = character:FindFirstChild("Animate")
	if inert then inert:Destroy() end
	local animate = template:Clone()
	animate.Name = "Animate"
	for setName, animations in ANIMATION_SETS do
		local set = Instance.new("StringValue")
		set.Name = setName
		for name, id in animations do
			local animation = Instance.new("Animation")
			animation.Name = name
			animation.AnimationId = "rbxassetid://" .. id
			animation.Parent = set
		end
		set.Parent = animate
	end
	Instance.new("BindableFunction", animate).Name = "PlayEmote"
	animate.Parent = character      -- (scripts don't run in ServerStorage; this copy does)
end

function SurvivorBot:Destroy()
	if self.Character then self.Character:Destroy() end
	self.Character = nil
	self.Parent = nil
end

---------------------------------------------------------------- the grid
function SurvivorBot:cellOf(p)
	local maze = self.maze
	local x = math.clamp(math.floor((p.X + maze.half) / maze.S) + 1, 1, maze.n)
	local z = math.clamp(math.floor((p.Z + maze.half) / maze.S) + 1, 1, maze.n)
	return x, z
end

function SurvivorBot:centerOf(x, z)
	local maze = self.maze
	return Vector3.new((x - 0.5) * maze.S - maze.half, maze.floorY, (z - 0.5) * maze.S - maze.half)
end

-- Breadth-first search outward from (sx, sz) until `isGoal(x, z)`; returns the route (cells after
-- the start), or nil
function SurvivorBot:search(sx, sz, isGoal)
	local walls = self.maze.walls
	local function key(x, z) return x * 1000 + z end
	local cameFrom = { [key(sx, sz)] = false }
	local queue, head = { {sx, sz} }, 1
	local found
	while head <= #queue do
		local c = queue[head]
		head += 1
		if isGoal(c[1], c[2]) then found = c break end
		for _, d in DIRS do
			if not walls[c[1]][c[2]][d[3]] then
				local nx, nz = c[1] + d[1], c[2] + d[2]
				if cameFrom[key(nx, nz)] == nil then
					cameFrom[key(nx, nz)] = c
					table.insert(queue, {nx, nz})
				end
			end
		end
	end
	if not found then return nil end
	local route, c = {}, found
	while c and not (c[1] == sx and c[2] == sz) do
		table.insert(route, 1, c)
		c = cameFrom[key(c[1], c[2])]
	end
	return route
end

---------------------------------------------------------------- senses
function SurvivorBot:canSeePoint(from, to, range)
	local offset = Vector3.new(to.X, from.Y, to.Z) - from
	if offset.Magnitude > range then return false end
	return offset.Magnitude < 1 or workspace:Raycast(from, offset, self.rays) == nil
end

-- the nearest monster it can see, or nil
function SurvivorBot:seeMonster(eye, monsters)
	local best, bestDist
	for _, monster in monsters do
		if monster.pos and self:canSeePoint(eye, monster.pos, FLEE_SIGHT) then
			local d = (monster.pos - eye).Magnitude
			if not bestDist or d < bestDist then best, bestDist = monster, d end
		end
	end
	return best
end

-- the nearest relic (or false relic) it can see that nobody has collected, or nil
function SurvivorBot:seeRelic(root)
	local best, bestDist
	local all = table.clone(self.maze.relics)
	for _, fake in self.objectives.fakes do table.insert(all, fake) end
	for _, relic in all do
		if relic.collected or (relic.collector and relic.collector ~= self) then continue end
		if self.objectives:CanSee(root.Position, root.CFrame.LookVector, relic) then
			local d = (relic.center - root.Position).Magnitude
			if not bestDist or d < bestDist then best, bestDist = relic, d end
		end
	end
	return best
end

---------------------------------------------------------------- thinking
function SurvivorBot:Step(dt, monsters)
	local character = self.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root and humanoid.Health > 0) or self:GetAttribute("Seized") or self:GetAttribute("Out") then return end
	if self.heldAt then                       -- (Studio tests: held in place, see Match's MatchTest "bot")
		root.AssemblyLinearVelocity = Vector3.zero
		character:PivotTo(self.heldAt)
		humanoid:Move(Vector3.zero)
		return
	end
	local now = os.clock()

	-- collecting a relic: face it, as a player does (Controls), so its eyes stay on it
	local collecting = self.relic and self.relic.collector == self and not self.relic.collected
	humanoid.AutoRotate = not collecting
	if collecting then
		local flat = (self.relic.center - root.Position) * Vector3.new(1, 0, 1)
		if flat.Magnitude >= 0.5 then root.CFrame = CFrame.lookAt(root.Position, root.Position + flat) end
	end

	-- speed: the same rules as players (Movement). Walking, a bot faces the way it goes, so it
	-- never pays the facing penalty; the run animation's direction is handled the same way too.
	local speed, angle = Movement.walkSpeed(self, humanoid, root, { collecting = collecting })
	humanoid.WalkSpeed = speed
	Movement.setRunBackwards(humanoid, angle > Movement.BACKWARDS_FROM)

	-- SAFETY NET: bots have been seen flung high into the air (cause not found yet). If one ends up
	-- far above or below the floor, put it back where it last stood, and note it on its body
	-- ("Rescued", a count) so it can be looked into.
	local height = root.Position.Y - self.maze.floorY
	if height > 0 and height < 5 and humanoid.FloorMaterial ~= Enum.Material.Air then
		self.lastGround = root.CFrame
	elseif (height > 20 or height < -5) and self.lastGround then
		root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
		character:PivotTo(self.lastGround)
		character:SetAttribute("Rescued", (character:GetAttribute("Rescued") or 0) + 1)
		warn(("%s was flung %.0f studs from the floor; put back"):format(self.DisplayName, height))
		self.replanAt = 0
	end

	local cx, cz = self:cellOf(root.Position)
	self.visited[cx * 1000 + cz] = true

	if now >= self.thinkAt then
		self.thinkAt = now + THINK_EVERY
		self:think(root, cx, cz, monsters, now)
		if character:GetAttribute("BotMode") ~= self.mode then character:SetAttribute("BotMode", self.mode) end   -- (for testing)
	end

	-- follow the route, cell centre to cell centre
	local target = self.goalPoint
	if self.path[1] then
		target = self:centerOf(self.path[1][1], self.path[1][2])
		if ((target - root.Position) * Vector3.new(1, 0, 1)).Magnitude < 2.5 then
			table.remove(self.path, 1)
			target = self.path[1] and self:centerOf(self.path[1][1], self.path[1][2]) or self.goalPoint
		end
	end
	if target then humanoid:MoveTo(target + Vector3.new(0, 3, 0)) end

	-- stuck (e.g. a door shut in its face): plan again
	if now - self.stuckCheck.at > 2 then
		if self.path[1] and (root.Position - self.stuckCheck.pos).Magnitude < 1 then self.replanAt = 0 end
		self.stuckCheck = { at = now, pos = root.Position }
	end
end

-- the sanctuary that cell (x, z) is in, or nil
function SurvivorBot:sanctuaryAt(x, z)
	for _, sanctuary in self.maze.sanctuaries do
		if sanctuary.cells[x * 1000 + z] then return sanctuary end
	end
	return nil
end

-- Which exit to leave a sanctuary by: each scores how far its outside cell is from the monster it
-- last fled (if that was recent), plus random noise, minus a lot for the exit it last left by.
function SurvivorBot:pickExit(sanctuary, now)
	local best, bestScore
	local threat = now - (self.lastThreatAt or -math.huge) < 30 and self.lastThreatPos or nil
	for _, exit in sanctuary.exits or {} do
		if not exit.out then continue end
		local at = self:centerOf(exit.out[1], exit.out[2])
		local score = math.random() * EXIT_NOISE
		if threat then score += ((at - threat) * Vector3.new(1, 0, 1)).Magnitude end
		if exit == self.lastExit then score -= EXIT_NOISE end
		if not bestScore or score > bestScore then best, bestScore = exit, score end
	end
	return best
end

function SurvivorBot:think(root, cx, cz, monsters, now)
	local eye = Vector3.new(root.Position.X, self.maze.floorY + EYE, root.Position.Z)
	local objectives = self.objectives

	-- 1. FLEE from any monster it sees, to the nearest sanctuary
	local threat = self:seeMonster(eye, monsters)
	if threat then
		if now - (self.lastThreatAt or -math.huge) > 1 then self.waitFor = SAFE_AFTER + math.random() * SAFE_JITTER end
		self.lastThreatAt = now
		self.lastThreatPos = threat.pos
	end
	local safe = objectives:IsSafe(root.Position)
	if threat or (self.mode == "flee" and now - self.lastThreatAt < (self.waitFor or SAFE_AFTER)) then
		if self.mode ~= "flee" or now >= self.replanAt then
			self.mode = "flee"
			self.replanAt = now + 1
			self.path = self:search(cx, cz, function(x, z) return objectives:IsBlocked(x, z) end) or {}
			local last = self.path[#self.path]
			self.goalPoint = last and self:centerOf(last[1], last[2]) or nil
		end
		if safe then self.path = {} self.goalPoint = root.Position end   -- inside: wait here
		return
	end

	-- 2. COLLECT: keep at it while collecting; else go for a relic it can see
	if self.mode == "collect" and self.relic and not self.relic.collected and self.relic.model.Parent then
		local rx, rz = self.relic.x, self.relic.z
		if cx == rx and cz == rz then
			if self.relic.collector ~= self then objectives:StartCollecting(self, self.relic.id) end
			self.path = {}
			self.goalPoint = self.relic.center + Vector3.new(2.5, 0, 0)
			return
		end
	end
	local relic = self:seeRelic(root)
	if relic and (self.mode ~= "collect" or self.relic ~= relic or now >= self.replanAt) then
		self.mode = "collect"
		self.relic = relic
		self.replanAt = now + REPLAN_EVERY
		self.path = self:search(cx, cz, function(x, z) return x == relic.x and z == relic.z end) or {}
		self.goalPoint = relic.center + Vector3.new(2.5, 0, 0)
		return
	end
	if self.mode == "collect" and self.relic and not self.relic.collected and self.relic.model.Parent then return end

	-- 3. LEAVE a sanctuary it's sheltering in by a well-picked exit (see FLEE above)
	if safe and self.mode == "flee" then
		local sanctuary = self:sanctuaryAt(cx, cz)
		local exit = sanctuary and self:pickExit(sanctuary, now)
		if exit then
			self.mode = "leave"
			self.lastExit = exit
			self.replanAt = now + REPLAN_EVERY * 2
			self.path = self:search(cx, cz, function(x, z) return x == exit.out[1] and z == exit.out[2] end) or {}
			local last = self.path[#self.path]
			self.goalPoint = last and self:centerOf(last[1], last[2]) or nil
			return
		end
	end
	if self.mode == "leave" and #self.path > 0 and now < self.replanAt then return end

	-- 4. ROAM: head for the nearest cell it hasn't visited (or anywhere, once it's seen it all)
	if self.mode ~= "roam" or #self.path == 0 or now >= self.replanAt then
		self.mode = "roam"
		self.relic = nil
		self.replanAt = now + REPLAN_EVERY * 2
		local skip = math.random(0, 3)    -- not always the very nearest, so bots spread out
		self.path = self:search(cx, cz, function(x, z)
			if self.visited[x * 1000 + z] or objectives:IsBlocked(x, z) then return false end
			if skip > 0 then skip -= 1 return false end
			return true
		end) or self:search(cx, cz, function(x, z) return math.random() < 0.02 end) or {}
		local last = self.path[#self.path]
		self.goalPoint = last and self:centerOf(last[1], last[2]) or nil
	end
end

return SurvivorBot
