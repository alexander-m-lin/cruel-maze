-- The things survivors go after in a match: RELICS and SPAWN ROOMS (built by MazeBuilder).
--
--   local objectives = Objectives.new(maze, { onRelic = fn(player, relic), onCapture = fn(player, room) })
--   objectives:Update(survivors)   -- a few times a second: spotting, collecting, captures
--   objectives:IsBlocked(x, z)     -- can a monster enter this cell?
--   objectives:IsSafe(position)    -- is a survivor standing here protected from monsters?
--   objectives:Destroy()           -- at the end of the match
--
-- Relics: monsters can go anywhere near them. Once any survivor has seen a relic it is
--   "discovered", and survivors' fog stays clear around it until it's collected (FogOfWar), so a
--   monster waiting there is seen. Standing in a relic's cell for Config.RELIC_COLLECT_TIME
--   seconds collects it; leaving the cell or being caught resets the bar.
-- Spawn rooms: monsters can never enter one. The start room is yours from the beginning; walking
--   into another captures it for your team, and you can respawn there.
--
-- Players' computers follow along through ReplicatedStorage.Match:
--   attributes RelicsCollected, RelicsNeeded, RelicsTotal
--   a "SpawnRooms" folder with one Configuration per room: attributes Id, Center (Vector3), Captured
--   a "Relics" folder with one Configuration per relic: attributes Id, Center, Discovered, Collected,
--   CollectSince (server time collecting started; nil when nobody is collecting)

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
	self.relicAt = {}            -- [cell key] = relic
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

local function collect(self, relic, player)
	relic.collected = true
	relic.info:SetAttribute("Collected", true)
	self.collected += 1
	self.status:SetAttribute("RelicsCollected", self.collected)
	relic.info:SetAttribute("CollectSince", nil)
	relic.gem:Destroy()                         -- the relic is gone from its pedestal
	if self.callbacks.onRelic then self.callbacks.onRelic(player, relic) end
end

local function capture(self, room, player)
	room.captured = true
	room.info:SetAttribute("Captured", true)
	room.floor.Color = MazeBuilder.ROOM_CAPTURED_COLOR
	if self.callbacks.onCapture then self.callbacks.onCapture(player, room) end
end

-- Can a survivor standing at `root` see this relic? Same rules as their fog: within view range,
-- inside the vision cone (or very close), and no wall in between.
local EYE_HEIGHT = 3
local function canSee(self, root, relic)
	local eye = Vector3.new(root.Position.X, self.maze.floorY + EYE_HEIGHT, root.Position.Z)
	local target = Vector3.new(relic.center.X, eye.Y, relic.center.Z)
	local offset = target - eye
	local dist = offset.Magnitude
	if dist > Config.VIEW_RANGE then return false end
	if dist > Config.VIEW_NEAR then
		local facing = root.CFrame.LookVector * Vector3.new(1, 0, 1)
		if facing.Magnitude < 0.01 then return false end
		local angle = math.deg(math.acos(math.clamp(offset.Unit:Dot(facing.Unit), -1, 1)))
		if angle > Config.VIEW_CONE / 2 then return false end
	end
	return dist < 0.6 or workspace:Raycast(eye, offset - offset.Unit * 0.5, self.rayParams) == nil
end

-- survivors: the players who can spot, collect and capture (alive, in the match)
function Objectives:Update(survivors)
	local now = os.clock()
	local dt = math.min(now - self.lastUpdate, 0.5)
	self.lastUpdate = now

	local collecting = {}   -- [relic] = the first survivor standing on it
	for _, player in survivors do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not (root and humanoid and humanoid.Health > 0) then continue end

		for _, relic in self.maze.relics do
			if not relic.discovered and not relic.collected and canSee(self, root, relic) then discover(relic) end
		end

		local x, z = self:CellOf(root.Position)
		if not x then continue end
		local k = key(x, z)
		local relic = self.relicAt[k]
		if relic and not relic.collected and not collecting[relic] then collecting[relic] = player end
		local room = self.roomAt[k]
		if room and not room.captured then capture(self, room, player) end
	end

	-- Collecting: progress builds while someone stands on the relic, and resets the moment nobody
	-- does. Players' computers draw the bar from CollectSince (when it started), so it's smooth.
	for _, relic in self.maze.relics do
		if relic.collected then continue end
		local player = collecting[relic]
		if player then
			discover(relic)
			if relic.progress == 0 then relic.info:SetAttribute("CollectSince", workspace:GetServerTimeNow()) end
			relic.progress += dt
			if relic.progress >= Config.RELIC_COLLECT_TIME then collect(self, relic, player) end
		elseif relic.progress > 0 then
			relic.progress = 0
			relic.info:SetAttribute("CollectSince", nil)
		end
	end
end

return Objectives
