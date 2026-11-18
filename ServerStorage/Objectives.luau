-- The things survivors go after in a match: RELICS and SPAWN ROOMS (built by MazeBuilder).
--
--   local objectives = Objectives.new(maze, { onRelic = fn(player, relic), onCapture = fn(player, room) })
--   objectives:Update(survivors)   -- a few times a second: pick-ups and captures
--   objectives:IsBlocked(x, z)     -- can a monster enter this cell?
--   objectives:IsSafe(position)    -- is a survivor standing here protected from monsters?
--   objectives:Destroy()           -- at the end of the match
--
-- Relics: walking into a relic room collects its relic for your team. Its barrier stays up for
--   Config.RELIC_BARRIER_DELAY seconds more, then disappears and monsters can enter.
-- Spawn rooms: monsters can never enter one. The start room is yours from the beginning; walking
--   into another captures it for your team, and you can respawn there.
--
-- Players' computers follow along through ReplicatedStorage.Match:
--   attributes RelicsCollected, RelicsNeeded, RelicsTotal
--   a "SpawnRooms" folder with one Configuration per room: attributes Id, Center (Vector3), Captured

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Config)
local MazeLayout = require(ServerStorage.MazeLayout)
local MazeBuilder = require(ServerStorage.MazeBuilder)

local key = MazeLayout.key

local Objectives = {}
Objectives.__index = Objectives

function Objectives.new(maze, callbacks)
	local self = setmetatable({}, Objectives)
	self.maze = maze
	self.callbacks = callbacks or {}
	self.collected = 0
	self.blocked = {}            -- [cell key] = true while monsters can't enter
	self.relicAt = {}            -- [cell key] = relic
	self.roomAt = {}             -- [cell key] = room

	for _, room in maze.rooms do
		room.captured = room.id == 1                -- your team starts with the start room
		for k in room.cells do
			self.blocked[k] = true
			self.roomAt[k] = room
		end
	end
	for _, relic in maze.relics do
		relic.collected = false
		local k = key(relic.x, relic.z)
		self.blocked[k] = true
		self.relicAt[k] = relic
	end

	-- publish to players' computers
	self.status = ReplicatedStorage:WaitForChild("Match")
	self.status:SetAttribute("RelicsCollected", 0)
	self.status:SetAttribute("RelicsNeeded", Config.RELICS_NEEDED)
	self.status:SetAttribute("RelicsTotal", #maze.relics)
	local old = self.status:FindFirstChild("SpawnRooms")
	if old then old:Destroy() end
	self.roomFolder = Instance.new("Folder")
	self.roomFolder.Name = "SpawnRooms"
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
	return self
end

function Objectives:Destroy()
	if self.roomFolder then self.roomFolder:Destroy() end
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

-- Is a survivor at `position` protected (inside a spawn room or a relic room whose barrier is up)?
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

---------------------------------------------------------------- pick-ups and captures
local function collect(self, relic, player)
	relic.collected = true
	self.collected += 1
	self.status:SetAttribute("RelicsCollected", self.collected)
	relic.gem:Destroy()                         -- the relic is gone from its pedestal
	if self.callbacks.onRelic then self.callbacks.onRelic(player, relic) end

	-- the barrier stays up a little longer, then drops
	task.delay(Config.RELIC_BARRIER_DELAY, function()
		if self.destroyed then return end
		self.blocked[key(relic.x, relic.z)] = nil
		for _, ward in relic.wards do ward:Destroy() end
	end)
end

local function capture(self, room, player)
	room.captured = true
	room.info:SetAttribute("Captured", true)
	room.floor.Color = MazeBuilder.ROOM_CAPTURED_COLOR
	if self.callbacks.onCapture then self.callbacks.onCapture(player, room) end
end

-- survivors: the players who can collect and capture (alive, in the match)
function Objectives:Update(survivors)
	for _, player in survivors do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not (root and humanoid and humanoid.Health > 0) then continue end
		local x, z = self:CellOf(root.Position)
		if not x then continue end
		local k = key(x, z)
		local relic = self.relicAt[k]
		if relic and not relic.collected then collect(self, relic, player) end
		local room = self.roomAt[k]
		if room and not room.captured then capture(self, room, player) end
	end
end

return Objectives
