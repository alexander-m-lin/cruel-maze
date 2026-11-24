-- Fear Eater's fear, made easy to read (on each player's computer):
--   FEARED MARK  - every feared survivor ("FearedUntil", players and bots) gets a red glow round
--                  their head and red wisps rising off it, for anyone who can see them (the fog
--                  decides: a survivor hidden from you shows no mark). Survivors see it on
--                  themselves and their teammates too.
--   NIGHTMARE POINTERS - for a Fear Eater player: while Living Nightmare is ready, nearly ready
--                  (ARROW_LEAD seconds or less), or running, a wide red triangle round him points
--                  straight at each feared survivor, wherever they are (off screen too). They
--                  float just above the walls, so walls and fog never hide them.
--   DREAD RING  - every survivor under dread ("DreadUntil", players and bots) has a ring at their
--                  feet that starts full and wears away clockwise round the circle, from its
--                  bottom point on the screen, as the dread runs out (Instill Fear's dreadTime). Gone the moment they're
--                  feared or safe (the server clears "DreadUntil"). Shown like the feared mark.
--   DEVOUR TARGET - for a Fear Eater player, while Devour is ready (or a Minotaur's Tear Asunder:
--                  any auto-targeted Primary): a ring on the floor under the
--                  survivor a click would go for (DevourAim, the server's own choice; only
--                  survivors you can see count). Red for a feared survivor (a sure catch).
--   DEVOUR WARNING - the survivor Devour is coming for ("DevourTargetAt" on you, server time):
--                  a red flash round the screen edges and a snarl for the windup, time to run.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Movement = require(ReplicatedStorage:WaitForChild("Movement"))
local Heroes = require(ReplicatedStorage:WaitForChild("Heroes"))
local DevourAim = require(ReplicatedStorage:WaitForChild("DevourAim"))
local Sounds = require(ReplicatedStorage:WaitForChild("Sounds"))
local CollectionService = game:GetService("CollectionService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer

local RED = Color3.fromRGB(230, 30, 40)
local DARK_RED = Color3.fromRGB(120, 0, 10)

---------------------------------------------------------------- feared mark
local marks = {}   -- [character] = { highlight, emitter, light, attachment }

local function makeMark(head)
	local highlight = Instance.new("Highlight")
	highlight.Name = "FearMark"
	highlight.Adornee = head
	highlight.FillColor = RED
	highlight.FillTransparency = 0.25
	highlight.OutlineColor = Color3.fromRGB(255, 90, 90)
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = head

	local attachment = Instance.new("Attachment")
	attachment.Name = "FearMark"
	attachment.Position = Vector3.new(0, 0.6, 0)
	attachment.Parent = head
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Color = ColorSequence.new(RED, DARK_RED)
	emitter.LightEmission = 0.8
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 4) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(0.25, 0.35),
		NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.7, 1.1)
	emitter.Rate = 22
	emitter.Speed = NumberRange.new(2.5, 4)
	emitter.SpreadAngle = Vector2.new(25, 25)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.RotSpeed = NumberRange.new(-60, 60)
	emitter.Parent = attachment
	local light = Instance.new("PointLight")
	light.Color = RED
	light.Range = 9
	light.Brightness = 2.5
	light.Parent = attachment
	return { highlight = highlight, emitter = emitter, light = light, attachment = attachment }
end

local function dropMark(character)
	local mark = marks[character]
	if not mark then return end
	mark.highlight:Destroy()
	mark.attachment:Destroy()
	marks[character] = nil
end

local function updateMarks(feared)
	local now = os.clock()
	local wanted = {}
	for _, root in feared do
		local character = root.Parent
		local head = character and character:FindFirstChild("Head")
		if not head then continue end
		wanted[character] = true
		local mark = marks[character]
		if mark and mark.highlight.Adornee ~= head then dropMark(character) mark = nil end
		if not mark then
			mark = makeMark(head)
			marks[character] = mark
		end
		-- shown only while the fog shows the survivor to you (always for yourself)
		local shown = character == player.Character or character:GetAttribute("FogState") ~= "hidden"
		local pulse = 0.5 + 0.5 * math.sin(now * 6)
		mark.highlight.Enabled = shown
		mark.highlight.FillTransparency = 0.15 + 0.3 * pulse
		mark.emitter.Enabled = shown
		mark.light.Enabled = shown
		mark.light.Brightness = 1.5 + 2 * (1 - pulse)
	end
	for character in marks do
		if not wanted[character] or not character.Parent then dropMark(character) end
	end
end

---------------------------------------------------------------- dread ring
local DREAD_SEGMENTS = 40
local DREAD_RADIUS = 3            -- studs
local DREAD_COLOR = Color3.fromRGB(230, 30, 40)    -- (the same red as the feared mark)
local DREAD_TIME = Heroes.list.FearEater.abilities.Secondary.dreadTime

local dreadRings = {}   -- [character] = { model, segments = { part, ... } }

local function makeDreadRing()
	local model = Instance.new("Model")
	model.Name = "DreadRing"
	local segments = {}
	local length = 2 * math.pi * DREAD_RADIUS / DREAD_SEGMENTS + 0.05
	for i = 1, DREAD_SEGMENTS do
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Material = Enum.Material.Neon
		p.Color = DREAD_COLOR
		p.Transparency = 0.15
		p.Size = Vector3.new(length, 0.1, 0.35)
		p.Parent = model
		segments[i] = p
	end
	return { model = model, segments = segments }
end

-- survivors under dread right now: [character] = seconds left
local function dreaded()
	local now = workspace:GetServerTimeNow()
	local list = {}
	local function consider(holder, character)
		local left = (holder:GetAttribute("DreadUntil") or 0) - now
		if character and left > 0 then list[character] = left end
	end
	for _, other in Players:GetPlayers() do
		if other:GetAttribute("Role") == Config.Roles.Survivor then consider(other, other.Character) end
	end
	for _, bot in CollectionService:GetTagged("SurvivorBot") do consider(bot, bot) end   -- (a bot's attributes are on its body)
	return list
end

local function updateDreadRings()
	local maze = workspace:FindFirstChild("Maze")
	local floorY = maze and maze:GetAttribute("FloorY") or 0
	local list = maze and dreaded() or {}
	-- the screen's "down" and "right" across the floor
	local camera = workspace.CurrentCamera
	local down = -(camera.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit
	local right = (camera.CFrame.RightVector * Vector3.new(1, 0, 1)).Unit
	for character, left in list do
		local root = character:FindFirstChild("HumanoidRootPart")
		local shown = root ~= nil and (character == player.Character or character:GetAttribute("FogState") ~= "hidden")
		local ring = dreadRings[character]
		if not shown then
			if ring then ring.model.Parent = nil end
			continue
		end
		if not ring then
			ring = makeDreadRing()
			dreadRings[character] = ring
		end
		-- segment i sits (i - 0.5)/N of the way clockwise (on the screen) round the circle from its
		-- bottom point; the ones nearest the start of that sweep go first
		local remaining = math.clamp(left / DREAD_TIME, 0, 1)
		local center = Vector3.new(root.Position.X, floorY + 0.12, root.Position.Z)
		for i, part in ring.segments do
			local t = (i - 0.5) / DREAD_SEGMENTS
			if t < 1 - remaining then
				part.Transparency = 1
			else
				local angle = t * 2 * math.pi
				local dir = down * math.cos(angle) - right * math.sin(angle)
				local at = center + dir * DREAD_RADIUS
				local tangent = Vector3.new(-dir.Z, 0, dir.X)
				part.CFrame = CFrame.lookAt(at, at + tangent) * CFrame.Angles(0, math.pi / 2, 0)
				part.Transparency = 0.15
			end
		end
		ring.model.Parent = workspace.CurrentCamera
	end
	for character, ring in dreadRings do
		if not list[character] or not character.Parent then
			ring.model:Destroy()
			dreadRings[character] = nil
		end
	end
end

---------------------------------------------------------------- nightmare pointers
-- One flat red triangle per feared survivor, round him, pointing the way they are. They float
-- just above the walls (and the fog, which reaches a stud above them), so nothing hides them.
local ARROW_LEAD = 2          -- seconds before Living Nightmare is ready that the pointers appear
local POINTER_START = 7       -- studs from his middle to a pointer's base (clear of his body)
local POINTER_LENGTH = 8      -- base to tip
local POINTER_HALF_WIDTH = 6  -- (the base is twice this wide)
local POINTER_ABOVE = 1.3     -- studs above the top of the walls
local THICK = 0.2

local arrows = Instance.new("Model")
arrows.Name = "NightmarePointers"
local function wedge()
	local p = Instance.new("WedgePart")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Neon
	p.Color = RED
	p.Transparency = 0.1
	p.Parent = arrows
	return p
end
local pointers = {}   -- reused: { left, right } wedges each

-- A flat right triangle: its right angle at `corner`, one leg `along` (unit) for `length` studs,
-- the other `side` (unit, flat, perpendicular) for `width` studs. A WedgePart's right angle is at
-- its bottom back edge: local +Y runs up the back to the top, local -Z along the bottom to the
-- front; local X is its thickness (here: up).
local function placeHalf(part, corner, along, side, length, width)
	part.Size = Vector3.new(THICK, length, width)
	local center = corner + along * (length / 2) + side * (width / 2)
	local localZ = -side
	local localX = along:Cross(localZ)
	part.CFrame = CFrame.fromMatrix(center, localX, along, localZ)
end

local function nightmareSoon()
	if player:GetAttribute("Role") ~= Config.Roles.Monster or player:GetAttribute("Hero") ~= "FearEater" then return false end
	local now = workspace:GetServerTimeNow()
	local character = player.Character
	if (character and (character:GetAttribute("NightmareUntil") or 0) > now)
		or (player:GetAttribute("NightmareUntil") or 0) > now then
		return true
	end
	return (player:GetAttribute("AbilityReadyUltimate") or 0) - now <= ARROW_LEAD
end

local function updateArrow(feared)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local maze = workspace:FindFirstChild("Maze")
	local used = 0
	if root and maze and #feared > 0 and not player:GetAttribute("Seized") and nightmareSoon() then
		local y = (maze:GetAttribute("FloorY") or 0) + (maze:GetAttribute("WallHeight") or 7) + POINTER_ABOVE
		local base = Vector3.new(root.Position.X, y, root.Position.Z)
		local bob = 0.8 * math.sin(os.clock() * 5)      -- a gentle push outward, so they read as pointing
		for _, r in feared do
			local to = (r.Position - root.Position) * Vector3.new(1, 0, 1)
			if to.Magnitude < 1 then continue end
			used += 1
			local pointer = pointers[used]
			if not pointer then
				pointer = { wedge(), wedge() }
				pointers[used] = pointer
			end
			local f = to.Unit
			local s = f:Cross(Vector3.yAxis)
			local corner = base + f * (POINTER_START + bob)
			placeHalf(pointer[1], corner, f, s, POINTER_LENGTH, POINTER_HALF_WIDTH)
			placeHalf(pointer[2], corner, f, -s, POINTER_LENGTH, POINTER_HALF_WIDTH)
			pointer[1].Parent, pointer[2].Parent = arrows, arrows
		end
	end
	for n = used + 1, #pointers do                  -- spare ones put away
		pointers[n][1].Parent, pointers[n][2].Parent = nil, nil
	end
	arrows.Parent = used > 0 and workspace.CurrentCamera or nil
end

---------------------------------------------------------------- Devour target
local TARGET_BLUE = Color3.fromRGB(70, 170, 255)
local ring = Instance.new("Part")
ring.Name = "DevourTarget"
ring.Shape = Enum.PartType.Cylinder
ring.Anchored, ring.CanCollide, ring.CanQuery, ring.CanTouch, ring.CastShadow = true, false, false, false, false
ring.Material = Enum.Material.Neon
ring.Transparency = 0.25
ring.Size = Vector3.new(0.12, 7, 7)

local wallRays = RaycastParams.new()
wallRays.FilterType = Enum.RaycastFilterType.Include

local function updateTarget(feared)
	local hero = Heroes.get(player:GetAttribute("Hero"))
	local def = hero and hero.abilities.Primary
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local maze = workspace:FindFirstChild("Maze")
	if player:GetAttribute("Role") ~= Config.Roles.Monster or not def or not def.autoTarget or not root or not maze
		or (player:GetAttribute("AbilityReadyPrimary") or 0) > workspace:GetServerTimeNow()
		or player:GetAttribute("Killing") or player:GetAttribute("Lunging") then
		ring.Parent = nil
		return
	end
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	if look.Magnitude < 0.01 then ring.Parent = nil return end
	wallRays.FilterDescendantsInstances = { maze }
	local function blocked(a, b)
		local y = root.Position.Y
		local from, to = Vector3.new(a.X, y, a.Z), Vector3.new(b.X, y, b.Z)
		local hit = workspace:Raycast(from, to - from, wallRays)
		return hit ~= nil and hit.Instance.CanCollide
	end
	-- survivors you can see (the fog marks them; it hides anyone in a sanctuary)
	local isFeared = {}
	for _, r in feared do isFeared[r] = true end
	local candidates = {}
	local function consider(body, holder)
		local r = body and body:FindFirstChild("HumanoidRootPart")
		if not r or holder:GetAttribute("Seized") or body:GetAttribute("FogState") == "hidden" then return end
		table.insert(candidates, { root = r, feared = isFeared[r] == true, visible = true })
	end
	for _, other in Players:GetPlayers() do
		if other:GetAttribute("Role") == Config.Roles.Survivor then consider(other.Character, other) end
	end
	for _, bot in CollectionService:GetTagged("SurvivorBot") do consider(bot, bot) end
	local target, lockedOn = DevourAim.pick(root.Position, look.Unit, def, candidates, blocked)
	if not target then ring.Parent = nil return end
	local down = workspace:Raycast(target.Position, Vector3.new(0, -20, 0), wallRays)
	local y = (down and down.Position.Y or target.Position.Y - 3) + 0.08
	local pulse = 0.5 + 0.5 * math.sin(os.clock() * 8)
	local color = lockedOn and RED or TARGET_BLUE
	ring.Color = color
	ring.Size = Vector3.new(0.12, 6.5 + pulse, 6.5 + pulse)
	ring.CFrame = CFrame.new(target.Position.X, y, target.Position.Z) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Parent = workspace.CurrentCamera
end

---------------------------------------------------------------- Devour warning (you're its target)
local warnGui = Instance.new("ScreenGui")
warnGui.Name = "DevourWarning"
warnGui.ResetOnSpawn = false
warnGui.IgnoreGuiInset = true
warnGui.DisplayOrder = 6
warnGui.Parent = player:WaitForChild("PlayerGui")
local warnEdges = {}
local function warnEdge(anchor, position, size, rotation)
	local f = Instance.new("Frame")
	f.AnchorPoint, f.Position, f.Size = anchor, position, size
	f.BackgroundColor3 = Color3.fromRGB(220, 20, 30)
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	local g = Instance.new("UIGradient")
	g.Rotation = rotation
	g.Transparency = NumberSequence.new(0, 1)
	g.Parent = f
	f.Parent = warnGui
	table.insert(warnEdges, f)
end
warnEdge(Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.new(1, 0, 0, 120), 90)
warnEdge(Vector2.new(0, 1), UDim2.fromScale(0, 1), UDim2.new(1, 0, 0, 120), -90)
warnEdge(Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.new(0, 120, 1, 0), 0)
warnEdge(Vector2.new(1, 0), UDim2.fromScale(1, 0), UDim2.new(0, 120, 1, 0), 180)
local snarl = Instance.new("Sound")
snarl.SoundId = "rbxassetid://" .. Sounds.DevourWarning.id
snarl.Volume = Sounds.DevourWarning.volume
snarl.PlaybackSpeed = Sounds.DevourWarning.speed or 1
snarl.Parent = SoundService

player:GetAttributeChangedSignal("DevourTargetAt"):Connect(function()
	if player:GetAttribute("DevourTargetAt") then snarl:Play() end
end)

local function updateWarning()
	local at = player:GetAttribute("DevourTargetAt")
	local windup = player:GetAttribute("DevourWindup") or 0.3
	local t = at and workspace:GetServerTimeNow() - at or math.huge
	-- full for the windup, then fading over a moment
	local strength = t < windup and 1 or math.clamp(1 - (t - windup) / 0.4, 0, 1)
	for _, f in warnEdges do f.BackgroundTransparency = 1 - 0.75 * strength end
end

---------------------------------------------------------------- every frame
RunService.RenderStepped:Connect(function()
	local feared = Movement.fearedRoots()
	updateMarks(feared)
	updateDreadRings()
	updateArrow(feared)
	updateTarget(feared)
	updateWarning()
end)
