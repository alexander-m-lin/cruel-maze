-- CRUSHING WALLS during a match (built into the maze by MazeBuilder; set off by the Maze Master).
--
--   local crushers = Crushers.new(maze, { onCrush = function(player) ... end })
--   crushers:Trigger(id)   -- set one off; false if it's already going
--   crushers:Step()        -- every frame
--
-- A crusher goes: WARNING (Config.CRUSHER_WARNING seconds: the two walls rumble, nothing moves)
-- -> SLAM (Config.CRUSHER_SLAM_TIME: a slab shoots out of each wall and they meet in the middle)
-- -> HOLD (Config.CRUSHER_HOLD_TIME) -> RETURN (Config.CRUSHER_RETURN_TIME: back into the walls).
-- A survivor caught between the slabs as they meet is crushed (loses a life). Monsters are never
-- hurt: monster players' characters pass through the slabs (collision groups, see Match).
--
-- Players' computers follow along through attributes on each slab: State ("idle", "warning",
-- "slam", "hold", "return"), WarnAt and SlamAt (server times).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)

local Crushers = {}
Crushers.__index = Crushers

function Crushers.new(maze, options)
	local self = setmetatable({}, Crushers)
	self.maze = maze
	self.onCrush = options.onCrush or function() end
	self.survivors = options.survivors or function() return {} end   -- players and survivor bots
	self.list = {}
	for _, crusher in maze.crushers do
		crusher.state = "idle"
		for _, slab in crusher.slabs do
			slab:SetAttribute("State", "idle")
			slab.CollisionGroup = "Crushers"
		end
		self.list[crusher.id] = crusher
	end
	return self
end

local function setState(crusher, state)
	crusher.state = state
	for _, slab in crusher.slabs do slab:SetAttribute("State", state) end
end

function Crushers:Trigger(id)
	local crusher = self.list[id]
	if not crusher or crusher.state ~= "idle" then return false end
	local now = os.clock()
	crusher.slamAt = now + Config.CRUSHER_WARNING
	crusher.crushed = {}
	local serverNow = workspace:GetServerTimeNow()
	for _, slab in crusher.slabs do
		slab:SetAttribute("WarnAt", serverNow)
		slab:SetAttribute("SlamAt", serverNow + Config.CRUSHER_WARNING)
	end
	setState(crusher, "warning")
	return true
end

local function placeSlabs(crusher, t)   -- t: 0 = in the walls, 1 = shut
	for k, slab in crusher.slabs do
		slab.CFrame = crusher.homes[k]:Lerp(crusher.shuts[k], t)
	end
end

-- Survivors standing between the slabs once they're nearly shut
local function crush(self, crusher)
	local S = self.maze.S
	for _, player in self.survivors() do
		if player:GetAttribute("Seized") then continue end
		if crusher.crushed[player] then continue end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not (root and humanoid and humanoid.Health > 0) then continue end
		local offset = root.Position - crusher.center
		local across = math.abs(offset:Dot(crusher.inward))
		local along = ((offset - crusher.inward * offset:Dot(crusher.inward)) * Vector3.new(1, 0, 1)).Magnitude
		if across < S / 2 - 1 and along < S / 2 - 0.5 then
			crusher.crushed[player] = true
			self.onCrush(player)
		end
	end
end

function Crushers:Step()
	local now = os.clock()
	local slam, hold, back = Config.CRUSHER_SLAM_TIME, Config.CRUSHER_HOLD_TIME, Config.CRUSHER_RETURN_TIME
	for _, crusher in self.list do
		if crusher.state == "idle" then continue end
		local t = now - crusher.slamAt
		if t < 0 then continue end                          -- still rumbling
		if t < slam then
			if crusher.state ~= "slam" then setState(crusher, "slam") end
			local k = t / slam
			placeSlabs(crusher, k * k)                     -- speeding up as it goes
			-- from halfway, anyone still between them is caught (before physics can squeeze them out)
			if k > 0.5 then crush(self, crusher) end
		elseif t < slam + hold then
			if crusher.state ~= "hold" then
				setState(crusher, "hold")
				placeSlabs(crusher, 1)
				crush(self, crusher)                       -- anyone still in between is caught as they meet
			end
		elseif t < slam + hold + back then
			if crusher.state ~= "return" then setState(crusher, "return") end
			local k = (t - slam - hold) / back
			placeSlabs(crusher, 1 - k * k * (3 - 2 * k))
		else
			placeSlabs(crusher, 0)
			setState(crusher, "idle")
		end
	end
end

return Crushers
