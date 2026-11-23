-- How KAI's abilities look and sound, on every player's computer (the server decides what happens:
-- HeroAbilities.Kai, Encrypt). Everything made here exists only on this computer.
--
--   SCANNER  - (survivors only: his team) a blue cone on the floor, the way it's fixed. While it
--              casts, a sweep line runs out to its edge; once it sees, the cone glows and its arc
--              pulses until it ends. (The seeing itself is the fog's: FogOfWar.)
--   EMP      - (everyone) a bright blue circle round where he cast it, for the whole disruption.
--              Its edge floats just above the walls, so walls and fog never hide it (the Maze
--              Master sees exactly where it went off); a faint disc on the floor fills it. It
--              charges up, flashes outward as it goes off, crackles while it lasts, and fades.
--              Every jammed door and crushing wall and every disabled ward ("JammedUntil" /
--              "DisabledUntil") spits blue sparks meanwhile.
--   ENCRYPT  - a burst of blue as he dissolves (and again as he comes back). Every CIRCUIT
--              INDICATOR (tagged "CircuitIndicator": his and the copies, all drawn the same) is a
--              square of glowing blue circuit traces on the floor of its cell, sliding cell to cell
--              ("From", "To", "MoveAt", "MoveTime"), shown wherever the fog lets you see it; in
--              its last "WarnTime" seconds every one flickers alike. To his own team he stays in
--              view, see-through and outlined blue.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Net = require(ReplicatedStorage:WaitForChild("Net"))
local Sounds = require(ReplicatedStorage:WaitForChild("Sounds"))
local Characters = require(ReplicatedStorage:WaitForChild("Characters"))
local Heroes = require(ReplicatedStorage:WaitForChild("Heroes"))

local player = Players.LocalPlayer
local fxEvent = Net.event("AbilityFx")

local BLUE = Color3.fromRGB(60, 170, 255)
local BRIGHT = Color3.fromRGB(170, 230, 255)
local EDGE = Color3.fromRGB(20, 110, 255)      -- (neon brightens: a deep blue reads as bright blue)
local DEEP = Color3.fromRGB(20, 70, 160)
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local EDGE_ABOVE = 1.3       -- studs above the walls the EMP's edge floats (as the nightmare pointers)
local EDGE_SEGMENTS = 64
local SCAN_CAST = math.max(0.05, Heroes.list.Kai.abilities.Primary.castTime)

local folder = Instance.new("Folder")
folder.Name = "KaiEffects"
folder.Parent = workspace

local function maze() return workspace:FindFirstChild("Maze") end
local function floorY()
	local m = maze()
	return m and m:GetAttribute("FloorY") or 0
end
local function wallTop()
	local m = maze()
	return floorY() + (m and m:GetAttribute("WallHeight") or 7)
end
local function onSurvivorSide()
	return player:GetAttribute("Role") == Config.Roles.Survivor
end

local function part(name, size, color, transparency, class)
	local p = Instance.new(class or "Part")
	p.Name = name
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Neon
	p.Color = color or BLUE
	p.Transparency = transparency or 0
	p.Size = size or Vector3.one * 0.2
	p.Parent = folder
	return p
end

local function sound(name, at)
	local def = Sounds[name]
	if not def then return end
	local holder = part("Sound", Vector3.one * 0.2, BLUE, 1)
	holder.Position = at
	Debris:AddItem(holder, 4)
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. def.id
	s.Volume = def.volume or 1
	s.PlaybackSpeed = def.speed or 1
	if def.range then s.RollOffMaxDistance = def.range end
	s.Parent = holder
	s:Play()
end

-- blue sparks bursting from a point
local function sparks(at, count, speed)
	local p = part("Sparks", Vector3.one * 0.2, BLUE, 1)
	p.Position = at
	local a = Instance.new("Attachment")
	a.Parent = p
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	e.Texture = SPARKLE
	e.Color = ColorSequence.new(BRIGHT, BLUE)
	e.LightEmission = 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) })
	e.Lifetime = NumberRange.new(0.15, 0.4)
	e.Speed = NumberRange.new(speed or 8, (speed or 8) * 2)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Parent = a
	e:Emit(count or 12)
	Debris:AddItem(p, 0.6)
end

-- A flat right triangle (two of these make any triangle): right angle at `corner`, one leg `along`
-- (unit) `length` long, the other `side` (unit, perpendicular) `width` long. (As FearMarks' pointers.)
local function placeHalf(p, corner, along, side, length, width)
	p.Size = Vector3.new(0.05, math.max(length, 0.05), math.max(width, 0.05))
	local localZ = -side
	p.CFrame = CFrame.fromMatrix(corner + along * (length / 2) + side * (width / 2), along:Cross(localZ), along, localZ)
end

-- A flat triangle from the apex `a` to the chord b..c (isosceles: a is as far from b as from c)
local function triangle(list, a, b, c, color, transparency)
	local m = (b + c) / 2
	local up = a - m
	local length = up.Magnitude
	for _, endPoint in { b, c } do
		local side = endPoint - m
		local w = part("ScanFill", nil, color, transparency, "WedgePart")
		placeHalf(w, m, up.Unit, side.Unit, length, side.Magnitude)
		table.insert(list, w)
	end
end

-- A thin glowing bar from a to b (flat)
local function bar(a, b, thickness, color, transparency)
	local p = part("Bar", nil, color, transparency)
	local span = b - a
	p.Size = Vector3.new(thickness, 0.06, math.max(span.Magnitude, 0.05))
	p.CFrame = CFrame.lookAt((a + b) / 2, b)
	return p
end

---------------------------------------------------------------- Scanner
local function scanner(holder)
	if not onSurvivorSide() then return end
	local from, dir = holder:GetAttribute("ScanFrom"), holder:GetAttribute("ScanDir")
	local seesAt, endsAt = holder:GetAttribute("ScanAt"), holder:GetAttribute("ScanUntil")
	if not (from and dir and seesAt and endsAt) then return end
	local range = holder:GetAttribute("ScanRange") or 70
	local half = math.rad((holder:GetAttribute("ScanCone") or 90) / 2)
	local y = floorY() + 0.12
	local apex = Vector3.new(from.X, y, from.Z)
	local heading = math.atan2(dir.Z, dir.X)
	local function arcPoint(a) return apex + Vector3.new(math.cos(a), 0, math.sin(a)) * range end
	local pieces, fill, arc = {}, {}, {}
	local STEPS = 8
	for i = 0, STEPS - 1 do
		local a1 = heading - half + 2 * half * i / STEPS
		local a2 = heading - half + 2 * half * (i + 1) / STEPS
		triangle(fill, apex, arcPoint(a1), arcPoint(a2), BLUE, 0.9)
		table.insert(arc, bar(arcPoint(a1), arcPoint(a2), 0.5, EDGE, 0.2))
	end
	local edges = { bar(apex, arcPoint(heading - half), 0.35, EDGE, 0.3), bar(apex, arcPoint(heading + half), 0.35, EDGE, 0.3) }
	for _, list in { fill, arc, edges } do for _, p in list do table.insert(pieces, p) end end
	local sweep = part("ScanSweep", nil, BRIGHT, 0.1)
	table.insert(pieces, sweep)
	sound("ScanSweep", apex)
	while true do
		local now = workspace:GetServerTimeNow()
		if now >= endsAt or holder:GetAttribute("ScanUntil") ~= endsAt then break end
		if now < seesAt then
			-- casting: a sweep line runs out across the cone to its edge
			local k = 1 - math.clamp((seesAt - now) / SCAN_CAST, 0, 1)
			local r = range * k
			local w = 2 * r * math.tan(half)
			sweep.Size = Vector3.new(math.max(w, 0.1), 0.06, 0.6)
			sweep.CFrame = CFrame.lookAt(apex + dir * r, apex + dir * (r + 1))
			for _, p in fill do p.Transparency = 0.93 end
			for _, p in arc do p.Transparency = 0.6 end
		else
			-- seeing: the cone glows, its arc pulsing
			sweep.Transparency = 1
			local pulse = 0.5 + 0.5 * math.sin(os.clock() * 9)
			local fade = math.clamp((endsAt - now) / 0.4, 0, 1)
			for _, p in fill do p.Transparency = 1 - (0.16 + 0.06 * pulse) * fade end
			for _, p in arc do p.Transparency = 1 - (0.95 - 0.35 * pulse) * fade end
			for _, p in edges do p.Transparency = 1 - 0.7 * fade end
		end
		RunService.RenderStepped:Wait()
	end
	for _, p in pieces do p:Destroy() end
end

---------------------------------------------------------------- EMP
local function emp(center, radius, pulseAt, endsAt)
	local floor = floorY()
	local top = wallTop() + EDGE_ABOVE
	local disc = part("EMPDisc", Vector3.new(0.1, 1, 1), EDGE, 0.93)
	disc.Shape = Enum.PartType.Cylinder
	local edge = {}
	for i = 1, EDGE_SEGMENTS do
		local a1, a2 = (i - 1) / EDGE_SEGMENTS * math.pi * 2, i / EDGE_SEGMENTS * math.pi * 2
		local p1 = Vector3.new(center.X + math.cos(a1) * radius, top, center.Z + math.sin(a1) * radius)
		local p2 = Vector3.new(center.X + math.cos(a2) * radius, top, center.Z + math.sin(a2) * radius)
		edge[i] = bar(p1, p2, 0.9, EDGE, 0.4)
	end
	local base = Vector3.new(center.X, floor + 0.1, center.Z)
	sound("EMPCharge", base)
	local pulsed = false
	while true do
		local now = workspace:GetServerTimeNow()
		if now >= endsAt + 0.5 then break end
		local size
		if now < pulseAt then
			-- charging: the disc fills out from the middle, the edge flickering on
			local k = 1 - math.clamp((pulseAt - now) / 0.5, 0, 1)
			size = radius * 2 * k
			for _, p in edge do p.Transparency = 0.75 - 0.35 * k + (math.random() < 0.3 and 0.2 or 0) end
		else
			if not pulsed then
				pulsed = true
				sound("EMPPulse", base)
				local flash = part("EMPFlash", Vector3.new(0.2, 4, 4), BRIGHT, 0.1)
				flash.Shape = Enum.PartType.Cylinder
				flash.CFrame = CFrame.new(Vector3.new(center.X, top, center.Z)) * CFrame.Angles(0, 0, math.pi / 2)
				TweenService:Create(flash, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Size = Vector3.new(0.2, radius * 2, radius * 2), Transparency = 1 }):Play()
				Debris:AddItem(flash, 0.5)
				for _ = 1, 10 do
					local a = math.random() * math.pi * 2
					sparks(Vector3.new(center.X + math.cos(a) * radius, top, center.Z + math.sin(a) * radius), 10, 10)
				end
			end
			-- crackling for the whole disruption, then fading
			local fade = math.clamp((endsAt + 0.5 - now) / 0.5, 0, 1)
			size = radius * 2
			for _, p in edge do p.Transparency = 1 - (0.75 + 0.25 * math.random()) * fade end
			disc.Transparency = 1 - 0.07 * fade
			if math.random() < 0.15 then
				local a = math.random() * math.pi * 2
				sparks(Vector3.new(center.X + math.cos(a) * radius, top, center.Z + math.sin(a) * radius), 6, 6)
			end
		end
		disc.Size = Vector3.new(0.1, math.max(size, 0.5), math.max(size, 0.5))
		disc.CFrame = CFrame.new(base) * CFrame.Angles(0, 0, math.pi / 2)
		RunService.RenderStepped:Wait()
	end
	disc:Destroy()
	for _, p in edge do p:Destroy() end
end

-- jammed doors and crushing walls, disabled wards: sparks
task.spawn(function()
	while true do
		task.wait(0.2)
		local m = maze()
		if not m then continue end
		local now = workspace:GetServerTimeNow()
		for _, d in m:GetChildren() do
			if (d.Name == "Door" or d.Name == "Crusher") and d:IsA("BasePart") and (d:GetAttribute("JammedUntil") or 0) > now then
				local s = d.Size
				local offset = Vector3.new((math.random() - 0.5) * s.X, (math.random() - 0.2) * s.Y, (math.random() - 0.5) * s.Z)
				sparks(d.Position + offset, 6, 6)
			end
		end
		for _, ward in CollectionService:GetTagged("WardEye") do
			local eye = ward:FindFirstChild("Eye")
			if eye and (ward:GetAttribute("DisabledUntil") or 0) > now and ward:GetAttribute("FogState") ~= "hidden" then
				sparks(eye.Position, 5, 4)
			end
		end
	end
end)

-- disabled wards look dead: the iris dark, the light out (while it lasts)
RunService.RenderStepped:Connect(function()
	local now = workspace:GetServerTimeNow()
	for _, ward in CollectionService:GetTagged("WardEye") do
		local off = (ward:GetAttribute("DisabledUntil") or 0) > now
		local iris = ward:FindFirstChild("Iris")
		if iris then iris.Color = off and Color3.fromRGB(40, 50, 70) or Color3.fromRGB(170, 60, 235) end
	end
end)

---------------------------------------------------------------- Encrypt
local function dissolveBurst(at)
	sparks(at, 24, 10)
	sound("EncryptIn", at)
	local ring = part("EncryptRing", Vector3.new(0.1, 2, 2), BLUE, 0.2)
	ring.Shape = Enum.PartType.Cylinder
	ring.CFrame = CFrame.new(Vector3.new(at.X, floorY() + 0.12, at.Z)) * CFrame.Angles(0, 0, math.pi / 2)
	TweenService:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.1, 14, 14), Transparency = 1 }):Play()
	Debris:AddItem(ring, 0.6)
end

-- One circuit drawing: a dim square with traces and chips, all identical (the same pattern)
local TRACES = {   -- in units of the square's half-size: { x1, z1, x2, z2 }
	{ -0.9, -0.5, 0.2, -0.5 }, { 0.2, -0.5, 0.2, 0.3 }, { 0.2, 0.3, 0.9, 0.3 },
	{ -0.6, 0.8, -0.6, -0.1 }, { -0.6, -0.1, -0.1, -0.1 }, { -0.9, 0.5, -0.6, 0.5 },
	{ 0.6, -0.9, 0.6, -0.2 }, { 0.6, 0.6, 0.6, 0.9 }, { -0.2, 0.6, 0.6, 0.6 },
}
local CHIPS = { { 0.2, -0.5 }, { -0.6, -0.1 }, { 0.6, 0.6 }, { 0.6, -0.2 }, { -0.2, 0.6 } }
local HALF = 6   -- studs: half the square's width

local circuits = {}   -- [model] = { parts, traces = {...}, chips = {...}, plate }

local function buildCircuit()
	local c = { parts = {}, traces = {}, chips = {} }
	c.plate = part("CircuitPlate", Vector3.new(HALF * 2, 0.05, HALF * 2), DEEP, 0.7)
	table.insert(c.parts, c.plate)
	for i, t in TRACES do
		local p = part("Trace", Vector3.new(0.35, 0.06, 1), BLUE, 0.2)
		c.traces[i] = { part = p, t = t }
		table.insert(c.parts, p)
	end
	for i, ch in CHIPS do
		local p = part("Chip", Vector3.new(1, 0.1, 1), BRIGHT, 0.1)
		c.chips[i] = { part = p, at = ch }
		table.insert(c.parts, p)
	end
	return c
end

local function circuitPosition(model, now)
	local from, to = model:GetAttribute("From"), model:GetAttribute("To")
	if not (from and to) then return nil end
	local t = model:GetAttribute("MoveTime") or 0
	local k = t > 0 and math.clamp((now - (model:GetAttribute("MoveAt") or now)) / t, 0, 1) or 1
	k = k * k * (3 - 2 * k)
	return from:Lerp(to, k)
end

RunService.RenderStepped:Connect(function()
	local now = workspace:GetServerTimeNow()
	local clock = os.clock()
	local y = floorY() + 0.1
	local seen = {}
	for _, model in CollectionService:GetTagged("CircuitIndicator") do
		seen[model] = true
		local c = circuits[model]
		if not c then
			c = buildCircuit()
			circuits[model] = c
		end
		local at = circuitPosition(model, now)
		local endsAt, warn = model:GetAttribute("EndsAt") or math.huge, model:GetAttribute("WarnTime") or 1
		local shown = at ~= nil and model:GetAttribute("FogState") ~= "hidden" and model:GetAttribute("FogState") ~= nil
		-- the last seconds: flickering, all alike
		local warning = endsAt - now < warn
		if warning and math.floor(clock * 12) % 2 == 0 then shown = false end
		if not shown then
			for _, p in c.parts do p.Transparency = 1 end
			continue
		end
		local origin = Vector3.new(at.X, y, at.Z)
		c.plate.CFrame = CFrame.new(origin)
		c.plate.Transparency = 0.7
		c.plate.Color = warning and BLUE or DEEP
		for i, tr in c.traces do
			local t = tr.t
			local a = origin + Vector3.new(t[1], 0, t[2]) * HALF + Vector3.yAxis * 0.03
			local b = origin + Vector3.new(t[3], 0, t[4]) * HALF + Vector3.yAxis * 0.03
			tr.part.Size = Vector3.new(0.35, 0.06, (b - a).Magnitude + 0.35)
			tr.part.CFrame = CFrame.lookAt((a + b) / 2, b)
			-- a pulse of light running along the traces
			tr.part.Transparency = 0.15 + 0.6 * (0.5 + 0.5 * math.sin(clock * 6 - i * 0.8))
		end
		for i, ch in c.chips do
			ch.part.CFrame = CFrame.new(origin + Vector3.new(ch.at[1], 0, ch.at[2]) * HALF + Vector3.yAxis * 0.05)
			ch.part.Transparency = 0.1 + 0.3 * (0.5 + 0.5 * math.sin(clock * 4 + i))
		end
	end
	for model, c in circuits do
		if not seen[model] then
			for _, p in c.parts do
				TweenService:Create(p, TweenInfo.new(0.3), { Transparency = 1 }):Play()
				Debris:AddItem(p, 0.35)
			end
			circuits[model] = nil
		end
	end
end)

-- Kai to his own team, while encrypted: see-through, outlined blue
local ghosts = {}   -- [character] = highlight
RunService.RenderStepped:Connect(function()
	local now = workspace:GetServerTimeNow()
	local want = {}
	if onSurvivorSide() then
		for _, other in Players:GetPlayers() do
			local character = other.Character
			if character and (other:GetAttribute("EncryptedUntil") or 0) > now then want[character] = true end
		end
	end
	for character in want do
		if not ghosts[character] then
			local h = Instance.new("Highlight")
			h.Name = "EncryptGhost"
			h.FillColor = BLUE
			h.FillTransparency = 0.55
			h.OutlineColor = BRIGHT
			h.DepthMode = Enum.HighlightDepthMode.Occluded
			h.Adornee = character
			h.Parent = folder
			ghosts[character] = h
		end
		for _, d in character:GetDescendants() do
			if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then d.LocalTransparencyModifier = 0.55 end
		end
	end
	for character, h in ghosts do
		if not want[character] then
			h:Destroy()
			ghosts[character] = nil
			if character:GetAttribute("FogState") ~= "hidden" then
				for _, d in character:GetDescendants() do
					if d:IsA("BasePart") then d.LocalTransparencyModifier = 0 end
				end
			end
		end
	end
end)

-- Coming back: a burst where he is, for anyone who can see him now
local watching = {}
local function watch(other)
	if watching[other] then return end
	watching[other] = true
	other:GetAttributeChangedSignal("EncryptedUntil"):Connect(function()
		if other:GetAttribute("EncryptedUntil") then return end
		task.wait(0.1)                                   -- (the fog shows him again first)
		local character = other.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and character:GetAttribute("FogState") ~= "hidden" then dissolveBurst(root.Position) end
	end)
end
for _, other in Players:GetPlayers() do watch(other) end
Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(function(other) watching[other] = nil end)

---------------------------------------------------------------- the server's word
fxEvent.OnClientEvent:Connect(function(kind, userId, a, b, c, d)
	if kind == "Scanner" then
		local holder = Players:GetPlayerByUserId(userId)
		if holder then task.spawn(scanner, holder) end
	elseif kind == "EMP" then
		task.spawn(emp, a, b, c, d)
	elseif kind == "Encrypt" then
		local character = Characters.of(userId)
		if onSurvivorSide() or (character and character:GetAttribute("FogState") ~= "hidden") then dissolveBurst(a) end
	end
end)
