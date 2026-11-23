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
--              small square of flickering bright blue tiles in the middle of its cell, sliding cell
--              to cell ("From", "To", "MoveAt", "MoveTime") and laying a thinner line of the same
--              tiles from the old cell to the new one, which then fades. Shown wherever the fog
--              lets you see it (and to Kai himself everywhere, drawn above the fog); in
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

-- One circuit drawing: a small square of bright blue tiles in the middle of its cell, every tile
-- flickering on its own (its see-through-ness drifting smoothly but quickly). Each move to the next
-- cell lays a LINE of the same tiles, one tile wide, behind it from the old cell to the new one,
-- which lingers a moment after it arrives and fades. Every tile is two LAYERS: the tile, and a smaller,
-- paler one on top of it, each flickering on its own, so the two shimmer through each other. Every
-- indicator is drawn the same way.
local TILE = 1.1             -- studs: a tile's width
local PITCH = 1.35           -- studs from one tile to the next (the gaps show the tiles)
local SQUARE_TILES = 4       -- the square is this many tiles a side
local FLICKER_RATE = 6       -- how fast the tiles flicker (higher: quicker)
local TRAIL_HOLD = 0.5       -- seconds a line stays after the circuit arrives...
local TRAIL_FADE = 0.6       -- ...then fades over this
local SQUARE_HALF = ((SQUARE_TILES - 1) * PITCH + TILE) / 2   -- studs from the square's middle to its edge
-- the layers, bottom first: color, size (of TILE), how far above the floor, flicker speed (of
-- FLICKER_RATE), and how see-through at its brightest and dimmest
local LAYERS = {
	{ color = BLUE, scale = 1, lift = 0, rate = 1, clear = { 0.05, 0.75 } },
	{ color = BRIGHT, scale = 0.6, lift = 0.05, rate = 1.35, clear = { 0.1, 0.95 } },
}

local circuits = {}   -- [model] = { square = { tile }, trails = { trail }, lastMove }
                      --   tile = { parts (one a layer), seeds }; trail = { tiles = { tile + d }, from, dir, length, startAt, moveTime }

local function newTile(height)
	local tile = { parts = {}, seeds = {} }
	for i, layer in LAYERS do
		tile.parts[i] = part("CircuitTile", Vector3.new(TILE * layer.scale, height, TILE * layer.scale), layer.color, 1)
		tile.seeds[i] = math.random() * 1000
	end
	return tile
end

-- a tile layer's see-through-ness now: smooth noise, quick
local function flicker(tile, i, clock)
	local layer = LAYERS[i]
	local n = math.clamp(0.5 + math.noise(clock * FLICKER_RATE * layer.rate, tile.seeds[i]) * 1.6, 0, 1)
	return layer.clear[1] + (layer.clear[2] - layer.clear[1]) * n
end

-- a tile shown at `cf` (on the floor), `strength` 1 to 0 as it fades
local function showTile(tile, cf, clock, strength, lift)
	for i, p in tile.parts do
		p.CFrame = cf + lift + Vector3.yAxis * LAYERS[i].lift
		p.Transparency = 1 - (1 - flicker(tile, i, clock)) * strength
	end
end

local function hideTile(tile)
	for _, p in tile.parts do p.Transparency = 1 end
end

local function buildCircuit()
	local c = { square = {}, trails = {} }
	for i = 1, SQUARE_TILES * SQUARE_TILES do
		local tile = newTile(0.06)
		tile.ix, tile.iz = (i - 1) % SQUARE_TILES, (i - 1) // SQUARE_TILES
		c.square[i] = tile
	end
	return c
end

-- How far along a move it is (0-1) after `k` of its time: eased at the ends the server says ("Ease":
-- two moves round a corner run on through it, at the same speed)
local function ease(k, how)
	if how == "in" then return k * k end
	if how == "out" then return 1 - (1 - k) * (1 - k) end
	return k * k * (3 - 2 * k)
end

-- a line of tiles from `from` to `to` (floor points), drawn as the circuit travels along it. Tiles
-- start at `from` and stop a tile short of `to` (the next move's line starts there: no gap at a
-- corner, and no tile twice)
local function newTrail(from, to, startAt, moveTime, how)
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local length = flat.Magnitude
	if length < 0.5 then return nil end
	local trail = { tiles = {}, from = from, dir = flat.Unit, length = length, startAt = startAt, moveTime = moveTime, ease = how }
	local count = math.max(1, math.round(length / PITCH))
	for i = 1, count do
		local tile = newTile(0.05)
		tile.d = (i - 1) * length / count
		trail.tiles[i] = tile
	end
	return trail
end

local function destroyTiles(tiles, fade)
	for _, tile in tiles do
		for _, p in tile.parts do
			if fade then
				TweenService:Create(p, TweenInfo.new(0.3), { Transparency = 1 }):Play()
				Debris:AddItem(p, 0.35)
			else
				p:Destroy()
			end
		end
	end
end

local function circuitPosition(model, now)
	local from, to = model:GetAttribute("From"), model:GetAttribute("To")
	if not (from and to) then return nil end
	local t = model:GetAttribute("MoveTime") or 0
	local k = t > 0 and math.clamp((now - (model:GetAttribute("MoveAt") or now)) / t, 0, 1) or 1
	return from:Lerp(to, ease(k, model:GetAttribute("Ease")))
end

-- Kai himself, while encrypted, sees all his circuits (his and the copies) wherever they are, fog or
-- not: drawn just above the fog and the walls, and shifted back toward the camera by as much as
-- they're raised, so on his screen each still sits on the floor of its cell
local ABOVE_FOG = 2   -- studs above the wall tops

RunService.RenderStepped:Connect(function()
	local now = workspace:GetServerTimeNow()
	local clock = os.clock()
	local y = floorY() + 0.1
	local mine = (player:GetAttribute("EncryptedUntil") or 0) > now
	local lift = Vector3.zero
	if mine then
		local raise = wallTop() + ABOVE_FOG - y
		local d = Config.CAMERA_DIRECTION
		lift = Vector3.new(d.X, 0, d.Z) * (raise / d.Y) + Vector3.yAxis * raise
	end
	local seen = {}
	for _, model in CollectionService:GetTagged("CircuitIndicator") do
		seen[model] = true
		local c = circuits[model]
		if not c then
			c = buildCircuit()
			circuits[model] = c
		end
		-- a new move: a new line, from where it set off to the next cell
		local moveAt = model:GetAttribute("MoveAt")
		if moveAt and moveAt ~= c.lastMove then
			c.lastMove = moveAt
			local from, to = model:GetAttribute("From"), model:GetAttribute("To")
			local trail = from and to and newTrail(from, to, moveAt, model:GetAttribute("MoveTime") or 0, model:GetAttribute("Ease"))
			if trail then table.insert(c.trails, trail) end
		end
		local at = circuitPosition(model, now)
		local endsAt, warn = model:GetAttribute("EndsAt") or math.huge, model:GetAttribute("WarnTime") or 1
		local shown = at ~= nil and (mine or model:GetAttribute("FogState") ~= "hidden" and model:GetAttribute("FogState") ~= nil)
		-- the last seconds: flickering on and off, all alike
		if endsAt - now < warn and math.floor(clock * 12) % 2 == 0 then shown = false end

		-- the square
		local origin = at and Vector3.new(at.X, y + 0.03, at.Z)
		local offset = (SQUARE_TILES - 1) / 2
		for _, tile in c.square do
			if shown then
				showTile(tile, CFrame.new(origin + Vector3.new((tile.ix - offset) * PITCH, 0, (tile.iz - offset) * PITCH)), clock, 1, lift)
			else
				hideTile(tile)
			end
		end

		-- the lines: drawn up to where the circuit's got to (none under its square), then lingering and fading
		for i = #c.trails, 1, -1 do
			local trail = c.trails[i]
			local elapsed = now - trail.startAt
			local k = trail.moveTime > 0 and math.clamp(elapsed / trail.moveTime, 0, 1) or 1
			k = ease(k, trail.ease)   -- (the same easing as the square's slide)
			local fade = math.clamp((elapsed - trail.moveTime - TRAIL_HOLD) / TRAIL_FADE, 0, 1)
			if fade >= 1 then
				destroyTiles(trail.tiles)
				table.remove(c.trails, i)
				continue
			end
			local look = CFrame.lookAt(Vector3.zero, trail.dir)
			for _, tile in trail.tiles do
				local p = trail.from + trail.dir * tile.d
				local under = origin and math.abs(p.X - origin.X) < SQUARE_HALF and math.abs(p.Z - origin.Z) < SQUARE_HALF
				if shown and tile.d <= k * trail.length + 0.01 and not under then
					showTile(tile, CFrame.new(p.X, y, p.Z) * look, clock, 1 - fade, lift)
				else
					hideTile(tile)
				end
			end
		end
	end
	for model, c in circuits do
		if not seen[model] then
			destroyTiles(c.square, true)
			for _, trail in c.trails do destroyTiles(trail.tiles, true) end
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
