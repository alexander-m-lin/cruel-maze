-- How heroes' abilities look and sound, on every player's computer (the server decides what
-- happens: Abilities). Everything made here exists only on this computer.
--
--   WHIP          - a lash (a curved Beam) from the hand to its tip, which flies out the way she
--                   faces, cracks, then holds while she's pulled to it (a wall or relic) or drags
--                   whoever it caught back as it comes in. The arm reaches along it (IKControl).
--   FLOURISH      - the arm goes up and the whip spins in a circle overhead, with a flash on the
--                   floor showing how far the stun reaches.
--   TREASURE HUNT - a pillar of golden light over the relic it found (survivors only).
--   STUNNED       - little stars circling over the head of anything stunned ("StunnedUntil").
-- Effects of someone you can't see (hidden by the fog) aren't drawn, so they give nothing away.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage:WaitForChild("Net"))
local Heroes = require(ReplicatedStorage:WaitForChild("Heroes"))
local Sounds = require(ReplicatedStorage:WaitForChild("Sounds"))
local Characters = require(ReplicatedStorage:WaitForChild("Characters"))

local fxEvent = Net.event("AbilityFx")
local SARA = Heroes.list.Sara.abilities

local WHIP_COLOR = Color3.fromRGB(92, 58, 34)
local GOLD = Color3.fromRGB(255, 205, 100)
local STAR = Color3.fromRGB(255, 230, 90)
local LASH_HEIGHT = 3       -- studs above the floor the lash flies at

local folder = Instance.new("Folder")
folder.Name = "HeroEffects"
folder.Parent = workspace

local function visible(character)
	return character and character:GetAttribute("FogState") ~= "hidden"
end

local function handOf(character)
	return character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
end

local function sound(name, at)
	local def = Sounds[name]
	if not def then return end
	local part = Instance.new("Part")
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
	part.Transparency = 1
	part.Size = Vector3.one * 0.2
	part.Position = at
	part.Parent = folder
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. def.id
	s.Volume = def.volume or 1
	if def.range then s.RollOffMaxDistance = def.range end
	s.Parent = part
	s:Play()
	Debris:AddItem(part, 4)
end

-- A whip: a beam from the hand to a small invisible tip part, which the caller moves.
-- Returns tip, cleanup. The arm reaches toward the tip while it lasts.
local function makeWhip(character)
	local hand = handOf(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not (hand and humanoid) then return nil end
	local tip = Instance.new("Part")
	tip.Name = "WhipTip"
	tip.Anchored, tip.CanCollide, tip.CanQuery, tip.CanTouch = true, false, false, false
	tip.Transparency = 1
	tip.Size = Vector3.one * 0.2
	tip.Position = hand.Position
	tip.Parent = folder
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, -hand.Size.Y / 2, 0)
	a0.Parent = hand
	local a1 = Instance.new("Attachment")
	a1.Parent = tip
	local beam = Instance.new("Beam")
	beam.Attachment0, beam.Attachment1 = a0, a1
	beam.Color = ColorSequence.new(WHIP_COLOR)
	beam.LightInfluence = 1
	beam.Width0, beam.Width1 = 0.22, 0.08
	beam.FaceCamera = true
	beam.Segments = 16
	beam.Parent = tip
	local ik
	local upperArm = character:FindFirstChild("RightUpperArm")
	if upperArm then
		ik = Instance.new("IKControl")
		ik.Type = Enum.IKControlType.Position
		ik.ChainRoot = upperArm
		ik.EndEffector = hand
		ik.Target = tip
		ik.SmoothTime = 0.05
		ik.Parent = humanoid
	end
	return tip, beam, function()
		tip:Destroy()
		a0:Destroy()
		if ik then ik:Destroy() end
	end
end

-- Move the tip from where it is to `to` over `seconds`, with the lash sagging a little in flight
local function fly(tip, beam, to, seconds, sag)
	local from = tip.Position
	local t0 = os.clock()
	while true do
		local k = math.min(1, (os.clock() - t0) / math.max(seconds, 0.01))
		tip.Position = from:Lerp(to, k)
		beam.CurveSize0, beam.CurveSize1 = sag * math.sin(k * math.pi), -sag * 0.5 * math.sin(k * math.pi)
		if k >= 1 then break end
		RunService.RenderStepped:Wait()
	end
end

---------------------------------------------------------------- Sara
local function whip(character, tipFloor, kind)
	if not visible(character) then return end
	local root = character:FindFirstChild("HumanoidRootPart")
	local tip, beam, cleanup = makeWhip(character)
	if not (tip and root) then return end
	local def = SARA.Primary
	local target = tipFloor + Vector3.new(0, LASH_HEIGHT, 0)
	local outTime = (target - tip.Position).Magnitude / def.speed
	fly(tip, beam, target, outTime, 1.5)
	if kind ~= "miss" then sound("WhipCrack", target) end
	if kind == "wall" or kind == "relic" then
		-- holds there while she's pulled along it
		local pull = ((target - root.Position) * Vector3.new(1, 0, 1)).Magnitude / def.pullSpeed
		local t0 = os.clock()
		while os.clock() - t0 < pull + 0.05 and tip.Parent do RunService.RenderStepped:Wait() end
		fly(tip, beam, handOf(character) and handOf(character).Position or root.Position, 0.1, 0)
	elseif kind == "ally" or kind == "monster" then
		-- drags whoever it caught back in
		local back = ((target - root.Position) * Vector3.new(1, 0, 1)).Magnitude / def.pullSpeed
		fly(tip, beam, root.Position + Vector3.new(0, 1, 0), back, 0.4)
	else
		sound("WhipCrack", target)
		fly(tip, beam, root.Position + Vector3.new(0, 1, 0), outTime * 0.6, -1)
	end
	cleanup()
end

local function flourish(character)
	if not visible(character) then return end
	local root = character:FindFirstChild("HumanoidRootPart")
	local tip, beam, cleanup = makeWhip(character)
	if not (tip and root) then return end
	local def = SARA.Ultimate
	sound("WhipSpin", root.Position)
	-- the floor flash: how far the stun reaches
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored, ring.CanCollide, ring.CanQuery, ring.CanTouch = true, false, false, false
	ring.Material = Enum.Material.Neon
	ring.Color = GOLD
	ring.Transparency = 0.4
	ring.Size = Vector3.new(0.2, 2, 2)
	ring.CFrame = CFrame.new(root.Position - Vector3.new(0, 2.8, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = folder
	TweenService:Create(ring, TweenInfo.new(def.spinTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.2, def.range * 2, def.range * 2), Transparency = 1 }):Play()
	Debris:AddItem(ring, def.spinTime + 0.1)
	-- the spin: 1.5 turns in a circle above the head
	local t0 = os.clock()
	while os.clock() - t0 < def.spinTime and root.Parent do
		local k = (os.clock() - t0) / def.spinTime
		local a = k * math.pi * 3
		tip.Position = root.Position + Vector3.new(math.cos(a) * 6, 4.5, math.sin(a) * 6)
		beam.CurveSize0, beam.CurveSize1 = 1.2, -0.6
		RunService.RenderStepped:Wait()
	end
	cleanup()
end

local function treasureFound(center)
	local pillar = Instance.new("Part")
	pillar.Shape = Enum.PartType.Cylinder
	pillar.Anchored, pillar.CanCollide, pillar.CanQuery, pillar.CanTouch = true, false, false, false
	pillar.Material = Enum.Material.Neon
	pillar.Color = GOLD
	pillar.Transparency = 0.35
	pillar.Size = Vector3.new(40, 3, 3)
	pillar.CFrame = CFrame.new(center + Vector3.new(0, 20, 0)) * CFrame.Angles(0, 0, math.rad(90))
	pillar.Parent = folder
	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Range = 16
	light.Brightness = 3
	light.Parent = pillar
	TweenService:Create(pillar, TweenInfo.new(3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
	Debris:AddItem(pillar, 3.1)
	sound("TreasureHunt", workspace.CurrentCamera.Focus.Position)
end

fxEvent.OnClientEvent:Connect(function(kind, userId, a, b)
	local character = Characters.of(userId)
	if kind == "Whip" and character then
		task.spawn(whip, character, a, b)
	elseif kind == "Flourish" and character then
		task.spawn(flourish, character)
	elseif kind == "TreasureHunt" then
		treasureFound(a)
	end
end)

---------------------------------------------------------------- stunned
local stars = {}   -- [model] = { parts }

local function stunnedThings()
	local list = {}
	local now = workspace:GetServerTimeNow()
	for _, model in CollectionService:GetTagged("Monster") do
		if (model:GetAttribute("StunnedUntil") or 0) > now and model:GetAttribute("VisibleToMe") ~= false then
			list[model] = true
		end
	end
	return list
end

RunService.RenderStepped:Connect(function()
	local want = stunnedThings()
	for model, parts in stars do
		if not want[model] or not model.Parent then
			for _, p in parts do p:Destroy() end
			stars[model] = nil
		end
	end
	local t = os.clock()
	for model in want do
		local parts = stars[model]
		if not parts then
			parts = {}
			for i = 1, 3 do
				local p = Instance.new("Part")
				p.Shape = Enum.PartType.Ball
				p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
				p.Material = Enum.Material.Neon
				p.Color = STAR
				p.Size = Vector3.one * 0.6
				p.CastShadow = false
				p.Parent = folder
				parts[i] = p
			end
			stars[model] = parts
		end
		local cf, size = model:GetBoundingBox()
		local top = cf.Position + Vector3.new(0, size.Y / 2 + 0.8, 0)
		for i, p in parts do
			local a = t * 5 + i * (2 * math.pi / 3)
			p.Position = top + Vector3.new(math.cos(a) * 1.6, math.sin(t * 7 + i) * 0.2, math.sin(a) * 1.6)
		end
	end
end)
