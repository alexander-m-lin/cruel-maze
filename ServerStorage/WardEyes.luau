-- WARDS: floating eyes the Maze Master places in open cells (see MazeMaster).
-- (Called "ward eyes" in the code: the sanctuaries' monster barriers are already called wards.)
--
--   local wards = WardEyes.new(maze, objectives, { onDestroying = fn(ward), onDestroyed = fn(ward) })
--   wards:CanPlace(x, z)         -- an open cell: not a sanctuary, not a relic's cell, no ward yet
--   wards:Add(x, z)              -- -> ward (the oldest fades if there are Config.WARDS_MAX already)
--   wards:Update(survivors)      -- a few times a second: spotting, and destroying
--   wards:StartDestroying(player, id)   -- a survivor clicked to destroy one (checked here)
--   wards:Sees(position)         -- does any ward see this spot? (for Haunt's "can the monster side see them")
--   wards.destroyedAt[MazeLayout.key(x, z)] -- os.clock() a survivor last destroyed a ward in that cell
--   wards:Destroy()
--
-- The monster side sees all around a ward (FogOfWar, Config.WARD_VISION_RADIUS, walls block it).
-- Survivors see one like any object: once one of them has spotted it, it's "Discovered" and stays
-- shown to them. Standing within Config.WARD_REACH of one shows a prompt; clicking starts
-- destroying it (the same reaching beam as collecting a relic), and staying close for
-- Config.WARD_DESTROY_TIME destroys it.
--
-- Players' computers follow along through ReplicatedStorage.Match.WardEyes: one Configuration per
-- ward, attributes Id, Center (floor), Eye (where the eye floats), Discovered, CollectSince and
-- Collector (as on relics, so RelicEffects and Controls treat both alike). The eye itself is the
-- model "Ward<id>" in the maze, tagged "WardEye", with its "Eye" part.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage.Config)
local MazeLayout = require(game:GetService("ServerStorage").MazeLayout)
local MazeBuilder = require(game:GetService("ServerStorage").MazeBuilder)

local WardEyes = {}
WardEyes.__index = WardEyes

local EYE_HEIGHT = 3     -- sight lines run at this height (as in FogOfWar and Objectives)
local IRIS = Color3.fromRGB(170, 60, 235)

function WardEyes.new(maze, objectives, callbacks)
	local self = setmetatable({}, WardEyes)
	self.maze = maze
	self.objectives = objectives
	self.callbacks = callbacks or {}
	self.list = {}           -- wards standing, oldest first
	self.destroyedAt = {}    -- [cell key] = when a survivor destroyed a ward there
	self.count = 0
	self.lastUpdate = os.clock()
	self.rayParams = RaycastParams.new()
	self.rayParams.FilterType = Enum.RaycastFilterType.Include
	self.rayParams.FilterDescendantsInstances = { maze.model }

	local status = ReplicatedStorage:WaitForChild("Match")
	local old = status:FindFirstChild("WardEyes")
	if old then old:Destroy() end
	self.folder = Instance.new("Folder")
	self.folder.Name = "WardEyes"
	self.folder.Parent = status
	return self
end

function WardEyes:Destroy()
	for _, ward in self.list do ward.model:Destroy() end
	table.clear(self.list)
	if self.folder then self.folder:Destroy() end
end

local function cellCenter(maze, x, z)
	return Vector3.new((x - 0.5) * maze.S - maze.half, maze.floorY, (z - 0.5) * maze.S - maze.half)
end

function WardEyes:CanPlace(x, z)
	local maze = self.maze
	if not x or x < 1 or z < 1 or x > maze.n or z > maze.n then return false end
	if self.objectives:IsBlocked(x, z) then return false end        -- a sanctuary
	local relic = self.objectives.relicAt[MazeLayout.key(x, z)]
	if relic and not relic.collected then return false end         -- a relic or false relic
	for _, ward in self.list do
		if ward.x == x and ward.z == z then return false end
	end
	return true
end

-- The eye: a pale ball with a glowing purple iris and a black pupil, which (on players' computers,
-- WardView) bobs and peers around. Nothing about it is solid or blocks sight.
local function buildEye(parent, id, at)
	local model = Instance.new("Model")
	model.Name = "Ward" .. id
	local function part(name, shape, size, color, material)
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = shape
		p.Size = size
		p.Color = color
		p.Material = material
		p.Anchored = true
		p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
		p.CastShadow = false
		p.Parent = model
		return p
	end
	local eye = part("Eye", Enum.PartType.Ball, Vector3.one * 2.2, Color3.fromRGB(225, 215, 205), Enum.Material.SmoothPlastic)
	eye.CFrame = CFrame.new(at)
	local iris = part("Iris", Enum.PartType.Cylinder, Vector3.new(0.3, 1.3, 1.3), IRIS, Enum.Material.Neon)
	iris.CFrame = eye.CFrame * CFrame.new(0, 0, -0.98) * CFrame.Angles(0, math.rad(90), 0)
	local pupil = part("Pupil", Enum.PartType.Cylinder, Vector3.new(0.32, 0.6, 0.6), Color3.new(0, 0, 0), Enum.Material.SmoothPlastic)
	pupil.CFrame = eye.CFrame * CFrame.new(0, 0, -1.02) * CFrame.Angles(0, math.rad(90), 0)
	local light = Instance.new("PointLight")
	light.Color = IRIS
	light.Range = 10
	light.Brightness = 1.5
	light.Parent = eye
	model.PrimaryPart = eye
	MazeBuilder.buildProgressBar(model, eye, IRIS, 2.5)   -- (filled by players' computers while it's being destroyed)
	model.Parent = parent
	CollectionService:AddTag(model, "WardEye")
	return model, eye
end

function WardEyes:Add(x, z)
	if not self:CanPlace(x, z) then return nil end
	if #self.list >= Config.WARDS_MAX then self:remove(self.list[1]) end   -- the oldest fades
	self.count += 1
	local id = 200 + self.count
	local center = cellCenter(self.maze, x, z)
	local eyeAt = center + Vector3.new(0, Config.WARD_HEIGHT, 0)
	local model, eye = buildEye(self.maze.model, id, eyeAt)
	model:SetAttribute("Id", id)
	model:SetAttribute("Center", center)
	local info = Instance.new("Configuration")
	info.Name = "Ward" .. id
	info:SetAttribute("Id", id)
	info:SetAttribute("Center", center)
	info:SetAttribute("Eye", eyeAt)
	info:SetAttribute("Discovered", false)
	info.Parent = self.folder
	local ward = { id = id, x = x, z = z, center = center, model = model, eye = eye, info = info, progress = 0 }
	table.insert(self.list, ward)
	return ward
end

function WardEyes:remove(ward)
	local i = table.find(self.list, ward)
	if i then table.remove(self.list, i) end
	ward.model:Destroy()
	ward.info:Destroy()
end

-- A clear line at eye height from `from` to `to` (flat), within `range`
function WardEyes:clearLine(from, to, range)
	local eye = Vector3.new(from.X, self.maze.floorY + EYE_HEIGHT, from.Z)
	local offset = Vector3.new(to.X, eye.Y, to.Z) - eye
	if offset.Magnitude > range then return false end
	return offset.Magnitude < 0.6 or workspace:Raycast(eye, offset - offset.Unit * 0.5, self.rayParams) == nil
end

function WardEyes:Sees(position)
	for _, ward in self.list do
		if self:clearLine(ward.center, position, Config.WARD_VISION_RADIUS + 2) then return true end
	end
	return false
end

function WardEyes:byId(id)
	for _, ward in self.list do
		if ward.id == id then return ward end
	end
	return nil
end

local function rootOf(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and humanoid and humanoid.Health > 0 then return root end
	return nil
end

function WardEyes:inReach(root, ward)
	local flat = (root.Position - ward.center) * Vector3.new(1, 0, 1)
	return flat.Magnitude <= Config.WARD_REACH and self:clearLine(root.Position, ward.center, Config.WARD_REACH + 1)
end

function WardEyes:StartDestroying(player, id)
	local ward = typeof(id) == "number" and self:byId(id)
	local root = rootOf(player)
	if not (ward and root) or ward.collector or not self:inReach(root, ward) then return end
	ward.collector = player
	ward.progress = 0
	ward.info:SetAttribute("Discovered", true)
	ward.info:SetAttribute("CollectSince", workspace:GetServerTimeNow())
	ward.info:SetAttribute("Collector", player.UserId)
	if self.callbacks.onDestroying then self.callbacks.onDestroying(ward) end
end

-- survivors: alive, in the match, not held by a monster
function WardEyes:Update(survivors)
	local now = os.clock()
	local dt = math.min(now - self.lastUpdate, 0.5)
	self.lastUpdate = now
	local roots = {}
	for _, player in survivors do
		local root = rootOf(player)
		if root then
			roots[player] = root
			for _, ward in self.list do
				if not ward.info:GetAttribute("Discovered") and self.objectives:CanSee(root.Position, root.CFrame.LookVector, ward) then
					ward.info:SetAttribute("Discovered", true)
				end
			end
		end
	end
	for _, ward in table.clone(self.list) do
		local player = ward.collector
		if not player then continue end
		local root = roots[player]
		if root and self:inReach(root, ward) then
			ward.progress += dt
			if ward.progress >= Config.WARD_DESTROY_TIME then
				self.destroyedAt[MazeLayout.key(ward.x, ward.z)] = os.clock()
				self:remove(ward)
				if self.callbacks.onDestroyed then self.callbacks.onDestroyed(ward, player) end
			end
		else
			ward.collector = nil
			ward.progress = 0
			ward.info:SetAttribute("CollectSince", nil)
			ward.info:SetAttribute("Collector", nil)
		end
	end
end

return WardEyes
