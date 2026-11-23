-- The maze's DOORS during a match: opening and closing them, safely, and (until the Maze Master is
-- a person) a simple AI that works them.
--
--   local doors = Doors.new(maze, { monsters = list, survivors = function() return players end,
--                                   ai = false })   -- (ai = false: a person is the Maze Master)
--   doors:Request(id, open)   -- start opening/closing a door; false if it can't right now
--   doors:Jam(id, seconds)    -- Kai's EMP: held open that long (opening now if it's shut, a closing
--                             -- that hasn't started moving called off), then shut again if it was
--   doors:Step(dt)            -- every frame while the match plays (moves doors, runs the AI)
--   doors:Destroy()
--
-- Any door may be open or closed at any time: MazeLayout.placeDoors laid the maze out so that
-- even with every door shut, everything is still reachable. So there's no checking here beyond
-- "is this door free to move".
--
-- A change goes: WARNING (Config.DOOR_WARNING seconds: it shakes and rumbles, nothing has moved
-- yet) -> MOVING (Config.DOOR_MOVE_TIME: the slab rises out of the floor or sinks into it) -> done.
-- A closing door counts as closed from the moment it starts to rise (routes are re-planned then),
-- and anyone standing in it is nudged out to the side they're nearer. An opening door counts as
-- open once it's fully down.
--
-- Players' computers follow along through attributes on each door part (see MazeBuilder):
--   Open (true/false: what it is or is becoming), State ("open", "closed", "warning", "moving"),
--   WarnAt / MoveAt (server times the warning and the movement start), JammedUntil (an EMP; server time)

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Config)
local Net = require(ReplicatedStorage.Net)
local Dev = require(game:GetService("ServerStorage").Dev)
local SpeedCheck = require(game:GetService("ServerStorage").SpeedCheck)
local MazeLayout = require(ServerStorage.MazeLayout)

local CHARACTER_CLEARANCE = 2.2   -- studs from the door's face a nudged player ends up at
local MONSTER_CLEARANCE = 4.5     -- ...and a nudged monster (its body is wider)
local AI_NEAR = 6                 -- the AI prefers doors within this many cells of a survivor...
local AI_NEAR_CHANCE = 0.7        -- ...this often (otherwise any door)

local Doors = {}
Doors.__index = Doors

local devEvent = Net.event("DevDoors")   -- developers only: player -> server, { action, ... } (see below)
local active = nil                        -- the match's Doors, for the dev panel
local aiEnabled = true                    -- the dev panel can switch the AI off (kept between matches)

function Doors.new(maze, options)
	local self = setmetatable({}, Doors)
	self.maze = maze
	self.monsters = options.monsters or {}
	self.survivors = options.survivors or function() return {} end
	self.useAI = options.ai ~= false   -- false when a person is the Maze Master
	self.bots = options.bots or function() return {} end   -- survivor bots (nudged like players)
	self.list = {}
	for _, door in maze.doors do
		door.state = door.open and "open" or "closed"
		door.changedAt = -math.huge
		door.part:SetAttribute("State", door.state)
		self.list[door.id] = door
	end
	ReplicatedStorage.Match:SetAttribute("DoorAI", aiEnabled)
	self.running = false             -- the AI only works doors while the match is on
	self.nextAI = os.clock() + self:aiInterval()
	active = self
	return self
end

function Doors:Destroy()
	if active == self then active = nil end
	self.list = {}
end

function Doors:aiInterval()
	return Config.DOOR_AI_MIN + math.random() * (Config.DOOR_AI_MAX - Config.DOOR_AI_MIN)
end

---------------------------------------------------------------- changing a door
-- Returns true if the door started changing
function Doors:Request(id, open)
	local door = self.list[id]
	if not door or (door.state ~= "open" and door.state ~= "closed") then return false end
	if door.open == open then return false end
	if not open and (door.jamUntil or 0) > os.clock() then return false end   -- jammed open (EMP)
	door.open = open
	door.state = "warning"
	door.changedAt = os.clock()
	door.moveAt = os.clock() + Config.DOOR_WARNING
	local now = workspace:GetServerTimeNow()
	door.part:SetAttribute("Open", open)
	door.part:SetAttribute("WarnAt", now)
	door.part:SetAttribute("MoveAt", now + Config.DOOR_WARNING)
	door.part:SetAttribute("State", "warning")
	return true
end

function Doors:Jam(id, seconds)
	local door = self.list[id]
	if not door then return end
	local now = os.clock()
	if (door.jamUntil or 0) <= now then door.wasShut = not door.open end   -- (a new jam: remember how it stood)
	door.jamUntil = math.max(door.jamUntil or 0, now + seconds)
	door.part:SetAttribute("JammedUntil", workspace:GetServerTimeNow() + (door.jamUntil - now))
	if door.state == "warning" and not door.open then
		-- about to close, hasn't moved yet: called off
		door.open = true
		door.state = "open"
		door.part:SetAttribute("Open", true)
		door.part:SetAttribute("State", "open")
	elseif door.state == "closed" then
		self:Request(id, true)
	end
	-- (one already rising finishes shutting, then stepJam opens it)
end

-- A jammed door that's shut opens; once the jam is over, one that was shut closes again
local function stepJam(self, door, now)
	if not door.jamUntil then return end
	if now < door.jamUntil then
		if door.state == "closed" then self:Request(door.id, true) end
		return
	end
	door.jamUntil = nil
	door.part:SetAttribute("JammedUntil", nil)
	if door.wasShut and door.open and door.state == "open" then self:Request(door.id, false) end
	door.wasShut = nil
end

function Doors:Toggle(id)
	local door = self.list[id]
	return door ~= nil and self:Request(id, not door.open)
end

-- The walls table changed: tell everything that plans routes over it
function Doors:mazeChanged()
	for _, monster in self.monsters do
		if monster.MazeChanged then monster:MazeChanged() end
	end
end

local function setPassable(self, door, passable)
	MazeLayout.setWall(self.maze.walls, door.x, door.z, door.d, not passable)
	self:mazeChanged()
end

-- Anyone standing in a door that's rising gets moved out to the nearer side.
-- `across` measures distance from the door's centre line, along the way through it.
local function nudge(self, door)
	local cf, size = door.closedCF, door.part.Size
	local alongX = door.d[3] == "S"                       -- the slab runs along X
	local length = alongX and size.X or size.Z
	local thick = alongX and size.Z or size.X
	local function measure(p)
		local offset = p - cf.Position
		local along = alongX and offset.X or offset.Z
		local across = alongX and offset.Z or offset.X
		return along, across
	end
	local function pushed(p, across, clearance)
		local side = across >= 0 and 1 or -1
		local delta = side * (thick / 2 + clearance) - across
		return alongX and Vector3.new(0, 0, delta) or Vector3.new(delta, 0, 0)
	end
	local everyone = Players:GetPlayers()
	for _, bot in self.bots() do table.insert(everyone, bot) end
	for _, player in everyone do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and not root.Anchored then
			local along, across = measure(root.Position)
			if math.abs(along) < length / 2 + 1 and math.abs(across) < thick / 2 + CHARACTER_CLEARANCE - 0.2 then
				character:PivotTo(character:GetPivot() + pushed(root.Position, across, CHARACTER_CLEARANCE))
				SpeedCheck.moved(player)      -- (the server moved them, not their computer)
			end
		end
	end
	for _, monster in self.monsters do
		if monster.pos then
			local along, across = measure(monster.pos)
			if math.abs(along) < length / 2 + 2 and math.abs(across) < thick / 2 + MONSTER_CLEARANCE - 0.2 then
				monster.pos += pushed(monster.pos, across, MONSTER_CLEARANCE)
				monster.path = {}
			end
		end
	end
end

local function stepDoor(self, door, now)
	if door.state == "warning" and now >= door.moveAt then
		door.state = "moving"
		door.part:SetAttribute("State", "moving")
		if not door.open then
			-- closing: it blocks from now on
			door.part.CanCollide = true
			setPassable(self, door, false)
		end
	end
	if door.state == "moving" then
		local t = math.clamp((now - door.moveAt) / Config.DOOR_MOVE_TIME, 0, 1)
		local from, to = door.closedCF, door.openCF
		if not door.open then from, to = to, from end
		local eased = t * t * (3 - 2 * t)                 -- smoothstep: eases in and out
		door.part.CFrame = from:Lerp(to, eased)
		if not door.open then nudge(self, door) end
		if t >= 1 then
			door.state = door.open and "open" or "closed"
			door.part:SetAttribute("State", door.state)
			if door.open then
				door.part.CanCollide = false
				setPassable(self, door, true)
			end
		end
	end
end

---------------------------------------------------------------- the AI
-- Until the Maze Master is a person: every DOOR_AI_MIN..MAX seconds, change DOOR_AI_COUNT doors
-- that haven't changed for DOOR_COOLDOWN seconds, usually ones near a survivor (so people see the
-- maze shift).
function Doors:stepAI(now)
	if not (aiEnabled and self.useAI and self.running) or now < self.nextAI then return end
	self.nextAI = now + self:aiInterval()
	local maze = self.maze
	local cells = {}
	for _, player in self.survivors() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			local p = root.Position
			table.insert(cells, { math.floor((p.X + maze.half) / maze.S) + 1, math.floor((p.Z + maze.half) / maze.S) + 1 })
		end
	end
	local near, any = {}, {}
	for _, door in self.list do
		if (door.state == "open" or door.state == "closed") and now - door.changedAt >= Config.DOOR_COOLDOWN then
			table.insert(any, door)
			for _, c in cells do
				if math.max(math.abs(c[1] - door.x), math.abs(c[2] - door.z)) <= AI_NEAR then
					table.insert(near, door)
					break
				end
			end
		end
	end
	-- DOOR_AI_COUNT different doors, each one usually from those near a survivor
	for _ = 1, Config.DOOR_AI_COUNT do
		local pool = (#near > 0 and math.random() < AI_NEAR_CHANCE) and near or any
		if #pool == 0 then break end
		local door = pool[math.random(#pool)]
		self:Request(door.id, not door.open)
		table.remove(near, table.find(near, door) or #near + 1)
		table.remove(any, table.find(any, door) or #any + 1)
	end
end

function Doors:Step(dt)
	local now = os.clock()
	for _, door in self.list do
		stepDoor(self, door, now)
		stepJam(self, door, now)
	end
	self:stepAI(now)
end

---------------------------------------------------------------- dev panel (developers only, see Dev)
-- { "toggle", id } | { "ai", on } | { "all", open }
devEvent.OnServerEvent:Connect(function(player, action, value)
	if not Dev.isDev(player) or not active then return end
	if action == "toggle" and typeof(value) == "number" then
		active:Toggle(value)
	elseif action == "ai" and typeof(value) == "boolean" then
		aiEnabled = value
		ReplicatedStorage.Match:SetAttribute("DoorAI", value)
	elseif action == "all" and typeof(value) == "boolean" then
		for id in active.list do active:Request(id, value) end
	end
end)

-- Test hook (Studio only): tools that run code in Studio get their own copy of this module, so
-- they reach the match's doors through ServerStorage.DoorsTest:Invoke(action, id, value):
--   "request", id, open -> started?     "info", id -> { state, open, blocked (walls table says shut) }
if RunService:IsStudio() then
	local hook = Instance.new("BindableFunction")
	hook.Name = "DoorsTest"
	hook.OnInvoke = function(action, id, value)
		if not active then return nil end
		if action == "request" then return active:Request(id, value) end
		if action == "ai" then aiEnabled = value return true end
		local door = active.list[id]
		if action == "info" and door then
			return { state = door.state, open = door.open, x = door.x, z = door.z, side = door.d[3],
				blocked = active.maze.walls[door.x][door.z][door.d[3]], center = door.closedCF.Position }
		end
		return nil
	end
	hook.Parent = ServerStorage
end

return Doors
