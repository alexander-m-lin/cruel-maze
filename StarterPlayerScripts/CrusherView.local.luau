-- The CRUSHING WALLS' warning, on this player's computer: while one rumbles (see Crushers on the
-- server), its two walls shake harder and harder and dust pours from their feet - but only if you
-- can see them (the Maze Master always can). The slabs' movement comes from the server; the
-- sounds are in SoundEffects.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local FogState = require(script.Parent:WaitForChild("FogState"))
local player = Players.LocalPlayer

local SHAKE_START, SHAKE_END = 0.05, 0.25   -- studs, building up over the warning
local SHAKE_SPEED = 30
local DUST_RATE = 45
local DUST_COLOR = Color3.fromRGB(200, 188, 160)

local crushers = {}   -- [id] = { slabs = {...}, panels = { { part, home, dust } }, seed }

local function makeDust(panel)
	-- an invisible strip along the foot of the wall, that dust puffs out of
	local strip = Instance.new("Part")
	strip.Name = "CrusherDust"
	strip.Anchored = true
	strip.CanCollide, strip.CanQuery, strip.CanTouch = false, false, false
	strip.Transparency = 1
	local size = panel.Size
	strip.Size = Vector3.new(size.X + 0.5, 0.2, size.Z + 0.5)
	strip.CFrame = panel.CFrame - Vector3.new(0, size.Y / 2 - 0.1, 0)
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Color = ColorSequence.new(DUST_COLOR)
	dust.LightEmission = 0.15
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 4) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.6, 0.55), NumberSequenceKeypoint.new(1, 1) })
	dust.Lifetime = NumberRange.new(0.8, 1.4)
	dust.Speed = NumberRange.new(2, 5)
	dust.SpreadAngle = Vector2.new(30, 30)
	dust.EmissionDirection = Enum.NormalId.Top
	dust.Rotation = NumberRange.new(0, 360)
	dust.RotSpeed = NumberRange.new(-40, 40)
	dust.Acceleration = Vector3.new(0, -1, 0)
	dust.Rate = 0
	dust.Parent = strip
	strip.Parent = workspace
	return strip, dust
end

local function clear()
	for _, c in crushers do
		for _, p in c.panels do
			if p.part.Parent then p.part.CFrame = p.home end
			p.strip:Destroy()
		end
	end
	table.clear(crushers)
end

local function watchMaze(maze)
	clear()
	for _, child in maze:GetChildren() do
		local id = child:GetAttribute("Id")
		if child.Name == "Crusher" and id then
			crushers[id] = crushers[id] or { slabs = {}, panels = {}, seed = math.random() * 100 }
			table.insert(crushers[id].slabs, child)
		end
		local cid = child:GetAttribute("CrusherId")
		if child.Name == "Wall" and cid then
			crushers[cid] = crushers[cid] or { slabs = {}, panels = {}, seed = math.random() * 100 }
			local strip, dust = makeDust(child)
			table.insert(crushers[cid].panels, { part = child, home = child.CFrame, strip = strip, dust = dust })
		end
	end
end

workspace.ChildAdded:Connect(function(child)
	if child.Name == "Maze" and child:IsA("Model") then
		task.wait()
		watchMaze(child)
	end
end)
task.spawn(function() watchMaze(workspace:WaitForChild("Maze")) end)

-- Can this player see the spot? (in view right now, or the Maze Master)
local function inView(position)
	if player:GetAttribute("Role") == Config.Roles.MazeMaster then return true end
	local tiles = FogState.tiles
	if not tiles then return false end
	local x = math.floor((position.X + FogState.half) / FogState.tileSize) + 1
	local z = math.floor((position.Z + FogState.half) / FogState.tileSize) + 1
	local tile = tiles[x] and tiles[x][z]
	return tile ~= nil and FogState.visible[tile] == true
end

RunService.RenderStepped:Connect(function()
	local now = workspace:GetServerTimeNow()
	local clock = os.clock()
	for _, c in crushers do
		local slab = c.slabs[1]
		local state = slab and slab.Parent and slab:GetAttribute("State")
		for _, p in c.panels do
			if not p.part.Parent then continue end
			local shake, rate = 0, 0
			if state == "warning" and inView(p.home.Position) then
				local warnAt, slamAt = slab:GetAttribute("WarnAt") or now, slab:GetAttribute("SlamAt") or now
				local build = math.clamp((now - warnAt) / math.max(0.1, slamAt - warnAt), 0, 1)
				shake = SHAKE_START + (SHAKE_END - SHAKE_START) * build
				rate = DUST_RATE * (0.4 + 0.6 * build)
			end
			if shake > 0 then
				local t = clock * SHAKE_SPEED
				p.part.CFrame = p.home + Vector3.new(math.noise(t, c.seed) * 2, math.noise(t, c.seed + 10) * 0.6, math.noise(t, c.seed + 20) * 2) * shake
				p.shaking = true
			elseif p.shaking then
				p.part.CFrame = p.home
				p.shaking = false
			end
			p.dust.Rate = rate
		end
	end
end)
