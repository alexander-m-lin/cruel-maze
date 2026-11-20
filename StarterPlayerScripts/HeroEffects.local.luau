-- How heroes' abilities look and sound, on every player's computer (the server decides what
-- happens: Abilities). Everything made here exists only on this computer.
--
-- There are no hand-made animations: poses are built from IKControls (Roblox bends the arm or
-- turns the head toward a target part, on top of whatever animation is playing), so moving the
-- target part animates the body.
--
--   WHIP          - a quick wind-up (the hand drawn back over the shoulder), then the lash flies
--                   out the way she faces, rippling, with the head following its tip. It cracks
--                   where it lands (dust off a wall, sparks off a monster, a glint off a relic),
--                   then holds while she's pulled along it, or drags whoever it caught back in.
--   FLOURISH      - the hand circles over her head and the whip swings wide from it like a
--                   lasso, out to the stun's full range, faster and faster, over a faint disc showing its reach; a bright flash
--                   out to the edge as the stun goes out.
--   TREASURE HUNT - a hand to the brow, a gold pulse sweeping out from her, and a pillar of light
--                   over the relic it found (survivors only).
--   PULLED        - anyone being dragged (a whip) kicks up dust and scrapes along the floor.
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

local WHIP_DARK = Color3.fromRGB(58, 34, 18)     -- the lash: a dark body...
local WHIP_LIGHT = Color3.fromRGB(140, 92, 52)   -- ...with a lighter, worn leather top
local WHIP_WIDTH = 0.85                          -- studs at the handle (it tapers to about a third)
local GOLD = Color3.fromRGB(255, 205, 100)
local STAR = Color3.fromRGB(255, 230, 90)
local LASH_HEIGHT = 3       -- studs above the floor the lash flies at
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

local folder = Instance.new("Folder")
folder.Name = "HeroEffects"
folder.Parent = workspace

local function visible(character)
	return character and character:GetAttribute("FogState") ~= "hidden"
end

local function handOf(character)
	return character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
end

local function floorY()
	local maze = workspace:FindFirstChild("Maze")
	return maze and maze:GetAttribute("FloorY") or 0
end

-- Studio only: a "HeroFxSlow" number attribute on Workspace slows these effects down that many
-- times, for checking them frame by frame (the server's pulls don't slow down)
local function slow()
	return RunService:IsStudio() and workspace:GetAttribute("HeroFxSlow") or 1
end

local function anchoredPart(name, size)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.Transparency = 1
	p.CastShadow = false
	p.Size = size or Vector3.one * 0.2
	p.Parent = folder
	return p
end

local function sound(name, at, parent)
	local def = Sounds[name]
	if not def then return nil end
	local part = parent or anchoredPart("Sound")
	if not parent then
		part.Position = at
		Debris:AddItem(part, 4)
	end
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. def.id
	s.Volume = def.volume or 1
	s.Looped = def.looped == true
	if def.range then s.RollOffMaxDistance = def.range end
	if def.startAt then s.TimePosition = def.startAt end
	s.Parent = part
	s:Play()
	return s
end

-- A one-off burst of particles at a point: "dust", "sparks" or "glint"
local function burst(kind, at, direction)
	local part = anchoredPart("Burst")
	part.CFrame = CFrame.lookAt(at, at + (direction or Vector3.yAxis))
	local attachment = Instance.new("Attachment")
	attachment.Parent = part
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	e.SpreadAngle = Vector2.new(60, 60)
	if kind == "dust" then
		e.Texture = SMOKE
		e.Color = ColorSequence.new(Color3.fromRGB(150, 140, 120))
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 2.4) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(0.4, 0.8)
		e.Speed = NumberRange.new(4, 9)
		e.Drag = 4
	elseif kind == "sparks" then
		e.Texture = SPARKLE
		e.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120))
		e.LightEmission = 1
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
		e.Lifetime = NumberRange.new(0.2, 0.4)
		e.Speed = NumberRange.new(12, 22)
		e.SpreadAngle = Vector2.new(80, 80)
	else -- glint
		e.Texture = SPARKLE
		e.Color = ColorSequence.new(GOLD)
		e.LightEmission = 1
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) })
		e.Lifetime = NumberRange.new(0.3, 0.5)
		e.Speed = NumberRange.new(3, 6)
	end
	e.Parent = attachment
	e:Emit(kind == "dust" and 14 or 18)
	Debris:AddItem(part, 1.2)
end

---------------------------------------------------------------- the whip
-- A whip from her hand: a lash (two beams, dark body under a lighter top, tapering) to a small
-- tip part the caller moves, which leaves a short streak behind it. Her right arm reaches for
-- `armTarget` (by default the tip) and her head turns to the tip.
-- Returns whip = { tip, armTarget, setCurve(sag, ripple), cleanup() }.
local function makeWhip(character)
	local hand = handOf(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not (hand and humanoid) then return nil end
	local tip = anchoredPart("WhipTip")
	tip.Position = hand.Position
	local armTarget = anchoredPart("WhipArmTarget")
	armTarget.Position = hand.Position
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, -hand.Size.Y / 2, 0)
	a0.Parent = hand
	local a1 = Instance.new("Attachment")
	a1.Parent = tip
	local beams = {}
	for i, look in { { WHIP_DARK, 1, 0 }, { WHIP_LIGHT, 0.45, 0.15 } } do
		local beam = Instance.new("Beam")
		beam.Attachment0, beam.Attachment1 = a0, a1
		beam.Color = ColorSequence.new(look[1])
		beam.LightInfluence = 1
		beam.LightEmission = look[3]
		beam.Width0, beam.Width1 = WHIP_WIDTH * look[2], WHIP_WIDTH * look[2] * 0.35
		beam.FaceCamera = true
		beam.Segments = 24
		beam.ZOffset = i * 0.01                 -- the light top drawn over the dark body
		beam.Parent = tip
		beams[i] = beam
	end
	-- a short streak behind the tip as it flies
	local t0 = Instance.new("Attachment")
	t0.Position = Vector3.new(0, 0.25, 0)
	t0.Parent = tip
	local t1 = Instance.new("Attachment")
	t1.Position = Vector3.new(0, -0.25, 0)
	t1.Parent = tip
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = t0, t1
	trail.Color = ColorSequence.new(WHIP_LIGHT)
	trail.Transparency = NumberSequence.new(0.3, 1)
	trail.Lifetime = 0.12
	trail.FaceCamera = true
	trail.Parent = tip
	-- the pose
	local controls = {}
	local upperArm = character:FindFirstChild("RightUpperArm")
	if upperArm then
		local ik = Instance.new("IKControl")
		ik.Type = Enum.IKControlType.Position
		ik.ChainRoot = upperArm
		ik.EndEffector = hand
		ik.Target = armTarget
		ik.SmoothTime = 0.04
		ik.Parent = humanoid
		table.insert(controls, ik)
	end
	local head, torso = character:FindFirstChild("Head"), character:FindFirstChild("UpperTorso")
	if head and torso then
		local look = Instance.new("IKControl")
		look.Type = Enum.IKControlType.LookAt
		look.ChainRoot = torso
		look.EndEffector = head
		look.Target = tip
		look.Weight = 0.7
		look.SmoothTime = 0.08
		look.Parent = humanoid
		table.insert(controls, look)
	end
	local whip = { tip = tip, armTarget = armTarget, hand = hand, followTip = true, sag = 0, ripple = 0 }
	-- The lash's shape. A Beam bends toward the way each end's attachment points, and the hand
	-- end turns with the hand, so left alone the lash would leave the hand sideways or even
	-- backwards. Instead, every frame both ends are pointed along the line from hand to tip, then
	-- bent on purpose: `sag` studs downward (gravity) and `ripple` studs sideways (a wave).
	function whip.setCurve(sag, ripple)
		whip.sag, whip.ripple = sag, ripple
	end
	local shaping = RunService.RenderStepped:Connect(function()
		local from, to = a0.WorldPosition, a1.WorldPosition
		local span = to - from
		local length = span.Magnitude
		if length < 0.2 then return end
		local forward = span / length
		local down = -Vector3.yAxis
		down = down - forward * down:Dot(forward)
		down = down.Magnitude > 0.01 and down.Unit or Vector3.zero
		local side = forward:Cross(Vector3.yAxis)
		side = side.Magnitude > 0.01 and side.Unit or Vector3.zero
		local out = forward * length / 3                    -- the handles a third of the way along...
		local bend = down * whip.sag + side * whip.ripple   -- ...pushed down and sideways
		local handle0, handle1 = out + bend, out - bend * 0.5
		a0.WorldAxis = handle0.Unit
		a1.WorldAxis = handle1.Unit
		for _, beam in beams do beam.CurveSize0, beam.CurveSize1 = handle0.Magnitude, handle1.Magnitude end
	end)
	function whip.cleanup()
		shaping:Disconnect()
		tip:Destroy()
		armTarget:Destroy()
		a0:Destroy()
		for _, c in controls do c:Destroy() end
	end
	return whip
end

-- Move the tip from where it is to `to` over `seconds`. The lash sags in the middle and ripples
-- (`sag`, studs), and the arm follows the tip while whip.followTip is on.
local function fly(whip, to, seconds, sag, ripples)
	local from = whip.tip.Position
	local t0 = os.clock()
	seconds *= slow()
	while whip.tip.Parent do
		local k = math.min(1, (os.clock() - t0) / math.max(seconds, 0.01))
		local eased = 1 - (1 - k) ^ 2                 -- fast out, slowing as it arrives
		whip.tip.Position = from:Lerp(to, eased)
		local wave = math.sin(k * math.pi)
		whip.setCurve(sag * wave, math.sin(k * math.pi * (ripples or 3)) * 0.8 * wave)
		if whip.followTip then whip.armTarget.Position = whip.tip.Position end
		if k >= 1 then break end
		RunService.RenderStepped:Wait()
	end
end

local function hold(seconds)
	seconds *= slow()
	local t0 = os.clock()
	while os.clock() - t0 < seconds do RunService.RenderStepped:Wait() end
end

---------------------------------------------------------------- Sara
local function whip(character, tipFloor, kind)
	if not visible(character) then return end
	local root = character:FindFirstChild("HumanoidRootPart")
	local w = makeWhip(character)
	if not (w and root) then return end
	local def = SARA.Primary
	local target = tipFloor + Vector3.new(0, LASH_HEIGHT, 0)
	local aim = ((target - root.Position) * Vector3.new(1, 0, 1))
	aim = aim.Magnitude > 0.01 and aim.Unit or root.CFrame.LookVector
	-- the wind-up: the hand drawn back over the shoulder
	w.followTip = false
	w.armTarget.Position = root.Position - aim * 1.5 + Vector3.new(0, 3, 0) + root.CFrame.RightVector * 0.8
	hold(0.07)
	w.followTip = true
	-- the lash
	local outTime = (target - w.tip.Position).Magnitude / def.speed
	fly(w, target, outTime, 1.5, 3)
	if kind ~= "miss" then sound("WhipCrack", target) end
	if kind == "wall" then
		burst("dust", target - aim * 0.5, -aim)
	elseif kind == "monster" then
		burst("sparks", target, -aim)
	elseif kind == "relic" then
		burst("glint", target, Vector3.yAxis)
	end
	if kind == "wall" or kind == "relic" then
		-- holds there, taut, while she's pulled along it
		local pull = ((target - root.Position) * Vector3.new(1, 0, 1)).Magnitude / def.pullSpeed
		w.setCurve(0, 0)
		hold(pull + 0.05)
		local hand = handOf(character)
		fly(w, hand and hand.Position or root.Position, 0.12, 0.6, 1)
	elseif kind == "ally" or kind == "monster" then
		-- drags whoever it caught back in, the arm hauling back
		local back = ((target - root.Position) * Vector3.new(1, 0, 1)).Magnitude / def.pullSpeed
		w.followTip = false
		w.armTarget.Position = root.Position - aim * 1 + Vector3.new(0, 1.5, 0)
		fly(w, root.Position + aim * 2 + Vector3.new(0, 1, 0), back, 0.4, 2)
	else
		-- a miss: it cracks at full stretch and snaps back
		sound("WhipCrack", target)
		fly(w, root.Position + Vector3.new(0, 1, 0), outTime * 0.6, -1, 2)
	end
	w.cleanup()
end

local function floorRing(at, size, transparency)
	local ring = anchoredPart("Ring")
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = GOLD
	ring.Transparency = transparency
	ring.Size = Vector3.new(0.2, size, size)
	ring.CFrame = CFrame.new(Vector3.new(at.X, floorY() + 0.15, at.Z)) * CFrame.Angles(0, 0, math.rad(90))
	return ring
end

local function flourish(character)
	if not visible(character) then return end
	local who = Players:GetPlayerFromCharacter(character) or character   -- (a bot keeps its attributes on its body)
	local root = character:FindFirstChild("HumanoidRootPart")
	local w = makeWhip(character)
	if not (w and root) then return end
	local def = SARA.Ultimate
	sound("WhipSpin", root.Position)
	-- the hand circles over her head and the whip swings wide from it, a little behind (like a
	-- lasso), faster and faster; a faint disc shows the reach until the stun goes out
	w.followTip = false
	local warning = floorRing(root.Position, def.range * 2, 0.82)
	local t0 = os.clock()
	local angle = 0
	local flashed = false
	while root.Parent do
		local dt = RunService.RenderStepped:Wait()
		local elapsed = os.clock() - t0
		if elapsed >= def.castTime or who:GetAttribute("Seized") or character:GetAttribute("FogState") == "hidden" then break end
		local k = math.min(1, elapsed / def.castTime)
		angle += dt * (7 + 15 * k)
		local overhead = root.Position + Vector3.new(0, 3.2, 0)
		w.armTarget.Position = overhead + Vector3.new(math.cos(angle) * 1.1, 0.4, math.sin(angle) * 1.1)
		local lag = angle - 0.7
		-- it pays out to the ability's full range as the spin starts, so the tip traces the edge of
		-- the stun
		local reach = 4 + (def.range - 4) * math.min(1, elapsed / 0.3)
		w.tip.Position = overhead + Vector3.new(math.cos(lag) * reach, 1.2 + math.sin(angle * 2) * 0.3, math.sin(lag) * reach)
		w.setCurve(2.5, math.sin(angle * 3) * 0.8)        -- drooping, with a little wave
		warning.Position = Vector3.new(root.Position.X, warning.Position.Y, root.Position.Z)
		if not flashed and elapsed >= def.stunAt then
			flashed = true
			warning:Destroy()
			local flash = floorRing(root.Position, 4, 0.3)
			TweenService:Create(flash, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = Vector3.new(0.2, def.range * 2, def.range * 2), Transparency = 1 }):Play()
			Debris:AddItem(flash, 0.45)
			sound("WhipCrack", w.tip.Position)
			burst("sparks", w.tip.Position, Vector3.yAxis)
		elseif not flashed then
			warning.Transparency = 0.82 - 0.12 * math.abs(math.sin(os.clock() * 10))
		end
	end
	if warning.Parent then warning:Destroy() end
	w.cleanup()
end

-- Treasure hunt, as seen by her team: a hand to the brow and a gold pulse sweeping out from her,
-- and a pillar of light over the relic it found
local function treasureHunt(character, center)
	if character and visible(character) then
		task.spawn(function()
			local hand = handOf(character)
			local head = character:FindFirstChild("Head")
			local upperArm = character:FindFirstChild("RightUpperArm")
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local root = character:FindFirstChild("HumanoidRootPart")
			if not (hand and head and upperArm and humanoid and root) then return end
			local pulse = floorRing(root.Position, 2, 0.35)
			TweenService:Create(pulse, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = Vector3.new(0.2, 60, 60), Transparency = 1 }):Play()
			Debris:AddItem(pulse, 1)
			local target = anchoredPart("BrowTarget")
			local ik = Instance.new("IKControl")
			ik.Type = Enum.IKControlType.Position
			ik.ChainRoot = upperArm
			ik.EndEffector = hand
			ik.Target = target
			ik.SmoothTime = 0.1
			ik.Parent = humanoid
			local t0 = os.clock()
			while os.clock() - t0 < 1 and head.Parent do
				-- shading the eyes, peering left then right
				local sweep = math.sin((os.clock() - t0) * math.pi * 2) * 0.35
				target.CFrame = head.CFrame * CFrame.new(0.15 + sweep, 0.55, -0.75)
				RunService.RenderStepped:Wait()
			end
			ik:Destroy()
			target:Destroy()
		end)
	end
	local pillar = anchoredPart("Pillar")
	pillar.Shape = Enum.PartType.Cylinder
	pillar.Material = Enum.Material.Neon
	pillar.Color = GOLD
	pillar.Transparency = 0.35
	pillar.Size = Vector3.new(40, 3, 3)
	pillar.CFrame = CFrame.new(center + Vector3.new(0, 20, 0)) * CFrame.Angles(0, 0, math.rad(90))
	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Range = 16
	light.Brightness = 3
	light.Parent = pillar
	TweenService:Create(pillar, TweenInfo.new(3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
	Debris:AddItem(pillar, 3.1)
	burst("glint", center + Vector3.new(0, 3.5, 0), Vector3.yAxis)
	sound("TreasureHunt", workspace.CurrentCamera.Focus.Position)
end

fxEvent.OnClientEvent:Connect(function(kind, userId, a, b)
	local character = Characters.of(userId)
	if kind == "Whip" and character then
		task.spawn(whip, character, a, b)
	elseif kind == "Flourish" and character then
		task.spawn(flourish, character)
	elseif kind == "TreasureHunt" then
		treasureHunt(character, a)
	end
end)

---------------------------------------------------------------- pulled along the floor
-- Anyone being pulled ("PullAt" + "PullTime": on a player, a survivor bot's body, or a monster's
-- body) scrapes along with dust kicking up at their feet.
local dragging = {}   -- [thing] = { part, emitter, sound }
local heard = {}      -- [holder] = { at = its PullAt, clock = os.clock() when we first saw it }

local function pulledThings()
	local list = {}
	local clock = os.clock()
	-- timed from when we hear of a pull (they're short: by the server's clock a late one is over)
	local function check(holder, body)
		local at = holder:GetAttribute("PullAt")
		if not at then return end
		local h = heard[holder]
		if not h or h.at ~= at then
			h = { at = at, clock = clock }
			heard[holder] = h
		end
		if clock - h.clock < (holder:GetAttribute("PullTime") or 0) + 0.05 and body and visible(body) then
			list[holder] = body
		end
	end
	for holder in heard do
		if typeof(holder) == "Instance" and not holder.Parent then heard[holder] = nil end
	end
	-- monster bodies: an AI's carries its own pull; a monster player's pull is on the player, and
	-- their body (not their invisible character) is what you see
	local bodyOf = {}
	for _, model in CollectionService:GetTagged("Monster") do
		local owner = model:GetAttribute("OwnerUserId")
		if owner then bodyOf[owner] = model end
		if model:GetAttribute("VisibleToMe") ~= false then check(model, model) end
	end
	for _, player in Players:GetPlayers() do
		local body = bodyOf[player.UserId]
		if body then
			if body:GetAttribute("VisibleToMe") ~= false then check(player, body) end
		else
			check(player, player.Character)
		end
	end
	for _, bot in CollectionService:GetTagged("SurvivorBot") do check(bot, bot) end
	return list
end

RunService.RenderStepped:Connect(function()
	local want = pulledThings()
	for thing, d in dragging do
		if not want[thing] then
			d.emitter.Enabled = false
			if d.sound then d.sound:Stop() end
			Debris:AddItem(d.part, 1)
			dragging[thing] = nil
		end
	end
	for thing, body in want do
		local d = dragging[thing]
		if not d then
			local part = anchoredPart("Drag")
			local attachment = Instance.new("Attachment")
			attachment.Parent = part
			local e = Instance.new("ParticleEmitter")
			e.Texture = SMOKE
			e.Color = ColorSequence.new(Color3.fromRGB(150, 140, 120))
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 2) })
			e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
			e.Lifetime = NumberRange.new(0.4, 0.7)
			e.Speed = NumberRange.new(1, 3)
			e.SpreadAngle = Vector2.new(70, 70)
			e.Rate = 60
			e.Drag = 3
			e.Parent = attachment
			d = { part = part, emitter = e, sound = sound("DragScrape", nil, part) }
			dragging[thing] = d
		end
		local p = body:GetPivot().Position
		d.part.CFrame = CFrame.new(p.X, floorY() + 0.3, p.Z)
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
				local p = anchoredPart("Star", Vector3.one * 0.6)
				p.Shape = Enum.PartType.Ball
				p.Material = Enum.Material.Neon
				p.Color = STAR
				p.Transparency = 0
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
