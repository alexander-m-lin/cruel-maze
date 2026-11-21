-- The things survivors go after in a match: RELICS and SPAWN ROOMS (built by MazeBuilder).
--
--   local objectives = Objectives.new(maze, { onRelic = fn(player, relic), onCapture = fn(player, room) })
--   objectives:Update(survivors)   -- a few times a second: spotting, collecting, captures
--   objectives:UpdateMonsterSight(monsters)  -- relics the monster side has seen (monsters' pos/facing)
--   objectives:StartCollecting(player, relicId)  -- they clicked to collect a relic (checked here)
--   objectives:IsBlocked(x, z)     -- can a monster enter this cell?
--   objectives:IsSafe(position)    -- is a survivor standing here protected from monsters?
--   objectives:CanPlaceFalseRelic(x, z) / :AddFalseRelic(x, z)   -- the Maze Master's false relics
--   objectives:Destroy()           -- at the end of the match
--
-- False relics: placed by the Maze Master. To survivors they look and act exactly like relics -
-- spotted, shown on the map, a prompt to collect - except that their eyes go out for a moment
-- every few seconds. A survivor near one (in sight of it) is revealed to the monster side
-- ("RevealedUntil" on the player); clicking one springs it (callbacks.onFalseRelic) and it's gone.
--
-- Relics: monsters can go anywhere near them. Once any survivor has seen a relic it is
--   "discovered", and survivors' fog stays clear around it until it's collected (FogOfWar), so a
--   monster waiting there is seen. Standing in a relic's cell shows a prompt; clicking starts
--   collecting, and staying in the cell for Config.RELIC_COLLECT_TIME seconds collects it.
--   Leaving the cell or being caught resets it (click again to restart); nothing else interrupts
--   it, not even the monster turning up.
-- Spawn rooms: monsters can never enter one. The start room is yours from the beginning; walking
--   into another captures it for your team, and you can respawn there.
--
-- Players' computers follow along through ReplicatedStorage.Match:
--   attributes RelicsCollected, RelicsNeeded, RelicsTotal
--   a "SpawnRooms" folder with one Configuration per room: attributes Id, Center (Vector3), Captured
--   a "Relics" folder with one Configuration per relic: attributes Id, Center, Discovered (by the
--   survivors), MonsterDiscovered (by the monster side; the Maze Master knows them all), Collected,
--   CollectSince (server time collecting started; nil when nobody is collecting), Collector (the
--   UserId of the survivor collecting it: their character reaches for it with a beam of light)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Config)
local MazeLayout = require(ServerStorage.MazeLayout)
local MazeBuilder = require(ServerStorage.MazeBuilder)

local key = MazeLayout.key

local Objectives = {}
Objectives.__index = Objectives

-- A folder of Configurations (one per item) under ReplicatedStorage.Match, replacing any old one
local function publishFolder(status, name)
	local old = status:FindFirstChild(name)
	if old then old:Destroy() end
	local folder = Instance.new("Folder")
	folder.Name = name
	return folder
end

function Objectives.new(maze, callbacks)
	local self = setmetatable({}, Objectives)
	self.maze = maze
	self.callbacks = callbacks or {}
	self.collected = 0
	self.blocked = {}            -- [cell key] = true: monsters can't enter (spawn rooms)
	self.relicAt = {}            -- [cell key] = relic (false relics too)
	self.fakes = {}              -- false relics still standing
	self.roomAt = {}             -- [cell key] = room
	self.lastUpdate = os.clock()

	-- sight lines (for spotting relics) are only blocked by the maze
	self.rayParams = RaycastParams.new()
	self.rayParams.FilterType = Enum.RaycastFilterType.Include
	self.rayParams.FilterDescendantsInstances = { maze.model }

	for _, room in maze.rooms do
		room.captured = room.id == 1                -- your team starts with the start room
		for k in room.cells do
			self.blocked[k] = true
			self.roomAt[k] = room
		end
	end
	for _, relic in maze.relics do
		relic.collected = false
		relic.discovered = false
		relic.progress = 0                          -- seconds of collecting so far
		self.relicAt[key(relic.x, relic.z)] = relic
	end

	-- publish to players' computers
	self.status = ReplicatedStorage:WaitForChild("Match")
	self.status:SetAttribute("RelicsCollected", 0)
	self.status:SetAttribute("RelicsNeeded", Config.RELICS_NEEDED)
	self.status:SetAttribute("RelicsTotal", #maze.relics)

	self.roomFolder = publishFolder(self.status, "SpawnRooms")
	for _, room in maze.rooms do
		local info = Instance.new("Configuration")
		info.Name = "Room" .. room.id
		info:SetAttribute("Id", room.id)
		info:SetAttribute("Center", room.center)
		info:SetAttribute("Captured", room.captured)
		info.Parent = self.roomFolder
		room.info = info
		if room.captured then room.floor.Color = MazeBuilder.ROOM_CAPTURED_COLOR end
	end
	self.roomFolder.Parent = self.status

	self.relicFolder = publishFolder(self.status, "Relics")
	for _, relic in maze.relics do
		local info = Instance.new("Configuration")
		info.Name = "Relic" .. relic.id
		info:SetAttribute("Id", relic.id)
		info:SetAttribute("Center", relic.center)
		info:SetAttribute("Discovered", false)
		info:SetAttribute("Collected", false)
		info.Parent = self.relicFolder
		relic.info = info
	end
	self.relicFolder.Parent = self.status
	return self
end

function Objectives:Destroy()
	if self.roomFolder then self.roomFolder:Destroy() end
	if self.relicFolder then self.relicFolder:Destroy() end
	self.destroyed = true
end

---------------------------------------------------------------- questions
function Objectives:CellOf(position)
	local maze = self.maze
	local x = math.floor((position.X + maze.half) / maze.S) + 1
	local z = math.floor((position.Z + maze.half) / maze.S) + 1
	if x < 1 or z < 1 or x > maze.n or z > maze.n then return nil end
	return x, z
end

-- Can a monster enter cell (x, z)?
function Objectives:IsBlocked(x, z)
	return self.blocked[key(x, z)] == true
end

-- Is a survivor at `position` protected (inside a spawn room)?
function Objectives:IsSafe(position)
	local x, z = self:CellOf(position)
	return x ~= nil and self:IsBlocked(x, z)
end

function Objectives:CapturedRoom(id)
	for _, room in self.maze.rooms do
		if room.id == id and room.captured then return room end
	end
	return nil
end

---------------------------------------------------------------- relics and captures
local function discover(relic)
	if relic.discovered then return end
	relic.discovered = true
	relic.info:SetAttribute("Discovered", true)
end

-- Spotted for the survivors by other means (Sara's Treasure hunt), as if they'd seen it
function Objectives:Discover(relic)
	discover(relic)
end

local function collect(self, relic, player)
	relic.collected = true
	relic.info:SetAttribute("Collected", true)
	self.collected += 1
	self.status:SetAttribute("RelicsCollected", self.collected)
	relic.info:SetAttribute("CollectSince", nil)
	relic.info:SetAttribute("Collector", nil)
	relic.gem:Destroy()                         -- the relic is gone from its pedestal
	if self.callbacks.onRelic then self.callbacks.onRelic(player, relic) end
end

local function capture(self, room, player)
	room.captured = true
	room.info:SetAttribute("Captured", true)
	room.floor.Color = MazeBuilder.ROOM_CAPTURED_COLOR
	if self.callbacks.onCapture then self.callbacks.onCapture(player, room) end
end

-- Can someone at `position`, facing `look`, see this relic? Same rules as the fog: within view
-- range, inside the vision cone (or very close), and no wall in between.
local EYE_HEIGHT = 3
local function canSeeFrom(self, position, look, relic)
	local eye = Vector3.new(position.X, self.maze.floorY + EYE_HEIGHT, position.Z)
	local target = Vector3.new(relic.center.X, eye.Y, relic.center.Z)
	local offset = target - eye
	local dist = offset.Magnitude
	if dist > Config.VIEW_RANGE then return false end
	if dist > Config.VIEW_NEAR then
		local facing = look * Vector3.new(1, 0, 1)
		if facing.Magnitude < 0.01 then return false end
		local angle = math.deg(math.acos(math.clamp(offset.Unit:Dot(facing.Unit), -1, 1)))
		if angle > Config.VIEW_CONE / 2 then return false end
	end
	return dist < 0.6 or workspace:Raycast(eye, offset - offset.Unit * 0.5, self.rayParams) == nil
end
function Objectives:CanSee(position, look, relic)   -- (for survivor bots)
	return canSeeFrom(self, position, look, relic)
end
local function canSee(self, root, relic)
	return canSeeFrom(self, root.Position, root.CFrame.LookVector, relic)
end

-- The monster side spots relics too (separately from the survivors): any monster, played or AI
function Objectives:UpdateMonsterSight(monsters)
	for _, relic in self.maze.relics do
		if relic.monsterDiscovered or relic.collected then continue end
		for _, monster in monsters do
			if monster.pos and monster.facing and canSeeFrom(self, monster.pos, monster.facing, relic) then
				relic.monsterDiscovered = true
				relic.info:SetAttribute("MonsterDiscovered", true)
				break
			end
		end
	end
end

-- survivors: the players who can spot, collect and capture (alive, in the match)
function Objectives:Update(survivors)
	local now = os.clock()
	local dt = math.min(now - self.lastUpdate, 0.5)
	self.lastUpdate = now

	local onRelic = {}      -- [player] = the relic whose cell they're standing in
	for _, player in survivors do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not (root and humanoid and humanoid.Health > 0) then continue end

		for _, relic in self.maze.relics do
			if not relic.discovered and not relic.collected and canSee(self, root, relic) then discover(relic) end
		end
		for _, relic in self.fakes do
			if not relic.discovered and canSee(self, root, relic) then discover(relic) end
			-- near one, in sight of it: the monster side sees you
			local offset = Vector3.new(relic.center.X, root.Position.Y, relic.center.Z) - root.Position
			if offset.Magnitude <= Config.FALSE_RELIC_REVEAL_RANGE
				and (offset.Magnitude < 1 or workspace:Raycast(root.Position, offset, self.rayParams) == nil) then
				player:SetAttribute("RevealedUntil", math.max(player:GetAttribute("RevealedUntil") or 0, workspace:GetServerTimeNow() + 0.5))
			end
		end

		local x, z = self:CellOf(root.Position)
		if not x then continue end
		local k = key(x, z)
		local relic = self.relicAt[k]
		if relic and not relic.collected then onRelic[player] = relic end
		local room = self.roomAt[k]
		if room and not room.captured then capture(self, room, player) end
	end

	-- Collecting: progress builds while the player who started it stays on the relic, and resets
	-- if they leave (or are caught). Players' computers draw the bar from CollectSince (when it
	-- started), so it's smooth.
	for _, relic in self.maze.relics do
		local player = relic.collector
		if relic.collected or not player then continue end
		if onRelic[player] == relic then
			relic.progress += dt
			if relic.progress >= Config.RELIC_COLLECT_TIME then collect(self, relic, player) end
		else
			relic.collector = nil
			relic.progress = 0
			relic.info:SetAttribute("CollectSince", nil)
			relic.info:SetAttribute("Collector", nil)
		end
	end
	self.onRelic = onRelic

	-- false relics' eyes go out for a moment every few seconds
	for _, relic in self.fakes do
		if now >= relic.blinkAt then
			local out = not relic.blinking
			relic.blinking = out
			relic.blinkAt = now + (out and Config.FALSE_RELIC_BLINK_TIME
				or Config.FALSE_RELIC_BLINK_EVERY * (0.7 + 0.6 * math.random()))
			for _, d in relic.gem:GetDescendants() do
				if d.Name == "Eye" and d:IsA("BasePart") then d.Transparency = out and 1 or 0
				elseif d:IsA("PointLight") and d.Parent:IsA("Attachment") then d.Enabled = not out end
			end
		end
	end
end

---------------------------------------------------------------- false relics
-- Where the Maze Master may put one: a cell with 2-3 openings (like a real relic's), not in or next
-- to a spawn room, and not within a cell of a relic (real or false).
function Objectives:CanPlaceFalseRelic(x, z)
	local maze = self.maze
	if not x or x < 1 or z < 1 or x > maze.n or z > maze.n then return false end
	local sides = MazeLayout.openSides(maze.walls, x, z)
	if sides < 2 or sides > 3 then return false end
	for _, room in maze.rooms do
		if x >= room.x - 1 and x <= room.x + 2 and z >= room.z - 1 and z <= room.z + 2 then return false end
	end
	for _, relic in maze.relics do
		if not relic.collected and math.max(math.abs(relic.x - x), math.abs(relic.z - z)) <= 1 then return false end
	end
	for _, relic in self.fakes do
		if math.max(math.abs(relic.x - x), math.abs(relic.z - z)) <= 1 then return false end
	end
	return true
end

function Objectives:AddFalseRelic(x, z)
	if not self:CanPlaceFalseRelic(x, z) then return nil end
	local maze = self.maze
	self.fakeCount = (self.fakeCount or 0) + 1
	local id = 100 + self.fakeCount          -- (real relics are 1..9)
	local center = Vector3.new((x - 0.5) * maze.S - maze.half, maze.floorY, (z - 0.5) * maze.S - maze.half)
	local model, gem = MazeBuilder.buildRelic(maze.model, center, id)
	local relic = { id = id, x = x, z = z, center = center, model = model, gem = gem, fake = true,
		discovered = false, monsterDiscovered = true, blinkAt = os.clock() + math.random() * Config.FALSE_RELIC_BLINK_EVERY }
	local info = Instance.new("Configuration")
	info.Name = "Relic" .. id
	info:SetAttribute("Id", id)
	info:SetAttribute("Center", center)
	info:SetAttribute("Discovered", false)
	info:SetAttribute("MonsterDiscovered", true)   -- the monster side's own trap: they all know it
	info:SetAttribute("Collected", false)
	info.Parent = self.relicFolder
	relic.info = info
	self.relicAt[key(x, z)] = relic
	table.insert(self.fakes, relic)
	if self.callbacks.onFalseRelicPlaced then self.callbacks.onFalseRelicPlaced(relic) end
	return relic
end

local function spring(self, relic, player)
	table.remove(self.fakes, table.find(self.fakes, relic))
	self.relicAt[key(relic.x, relic.z)] = nil
	relic.model:Destroy()
	relic.info:Destroy()
	if self.callbacks.onFalseRelic then self.callbacks.onFalseRelic(player, relic) end
end

-- A player clicked to collect a relic. Check it all: alive, standing in its cell, and nobody is
-- already collecting it.
function Objectives:StartCollecting(player, relicId)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and humanoid and humanoid.Health > 0) then return end
	local x, z = self:CellOf(root.Position)
	local relic = x and self.relicAt[key(x, z)]
	if not relic or relic.id ~= relicId or relic.collected or relic.collector then return end
	if relic.fake then
		spring(self, relic, player)
		return
	end
	discover(relic)
	relic.collector = player
	relic.progress = 0
	relic.info:SetAttribute("CollectSince", workspace:GetServerTimeNow())
	relic.info:SetAttribute("Collector", player.UserId)
end

return Objectives
