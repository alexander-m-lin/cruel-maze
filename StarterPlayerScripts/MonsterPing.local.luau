-- Sonar-style "ping" showing where a nearby monster is when you can't see it.
-- Every few seconds, for each monster within range that the fog is hiding, a red ring spreads
-- out across the floor at its position. The closer it is, the bigger and stronger the pulse.
--
-- How the ring is drawn: we take points on a circle lying on the floor (in the 3D world), work out
-- where each lands on screen with camera:WorldToViewportPoint, and join them with short line
-- segments. That gives exactly the squashed ellipse a flat ring looks like from the isometric
-- camera. It's drawn in a ScreenGui, so it shows on top of walls and fog.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local PING_EVERY    = 3      -- seconds between pings
local PING_RANGE    = 70     -- only ping monsters within this many studs (through walls)
local PING_LIFETIME = 1.6    -- seconds each ping lasts
local SEGMENTS      = 48     -- line segments per ring (more = smoother)
local COLOR = Color3.fromRGB(255, 60, 60)

local screen = Instance.new("ScreenGui")
screen.Name = "MonsterPings"
screen.IgnoreGuiInset = true      -- so screen coordinates match the camera's viewport
screen.ResetOnSpawn = false
screen.Parent = player:WaitForChild("PlayerGui")

local function makeSegments(count)
	local segs = {}
	for i = 1, count do
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BorderSizePixel = 0
		f.BackgroundColor3 = COLOR
		f.Parent = screen
		segs[i] = f
	end
	return segs
end

-- Where a world point lands on screen
local function toScreen(worldPos)
	local p, onScreen = camera:WorldToViewportPoint(worldPos)
	return Vector2.new(p.X, p.Y), onScreen
end

-- Draw a flat ring lying on the floor, centred on `center`
local function drawRing(segs, center, radius, thicknessPx, transparency)
	local prev = toScreen(center + Vector3.new(radius, 0, 0))
	for i = 1, #segs do
		local angle = i / #segs * math.pi * 2
		local nextPt = toScreen(center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))
		local d = nextPt - prev
		local seg = segs[i]
		seg.Position = UDim2.fromOffset((prev.X + nextPt.X) / 2, (prev.Y + nextPt.Y) / 2)
		seg.Size = UDim2.fromOffset(d.Magnitude + 1.5, thicknessPx)   -- +1.5 so segments overlap with no gaps
		seg.Rotation = math.deg(math.atan2(d.Y, d.X))
		seg.BackgroundTransparency = transparency
		prev = nextPt
	end
end

local function ping(groundPos, closeness)
	local ring = makeSegments(SEGMENTS)
	local dot = makeSegments(16)

	local endRadius = 4 + 7 * closeness          -- how far the ring spreads (studs)
	local thickness = 0.4 + 0.6 * closeness      -- ring width (studs)
	local start = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = (os.clock() - start) / PING_LIFETIME
		if t >= 1 then
			conn:Disconnect()
			for _, f in ring do f:Destroy() end
			for _, f in dot do f:Destroy() end
			return
		end
		-- pixels per stud here, for turning stud thicknesses into pixels
		local a = toScreen(groundPos)
		local pps = (toScreen(groundPos + camera.CFrame.RightVector) - a).Magnitude

		local eased = 1 - (1 - t) ^ 2                -- fast at first, then slows (ease-out)
		drawRing(ring, groundPos, 1 + (endRadius - 1) * eased, thickness * pps, 0.1 + 0.9 * eased)
		drawRing(dot, groundPos, 0.35, 0.7 * pps, 0.1 + 0.9 * t)   -- a small filled blob in the middle
	end)
end

while true do
	task.wait(PING_EVERY)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local maze = workspace:FindFirstChild("Maze")
	if root and maze then
		local floorY = maze:GetAttribute("FloorY") or (root.Position.Y - 3)
		for _, monster in CollectionService:GetTagged("Monster") do
			if monster:GetAttribute("VisibleToMe") ~= true then   -- set by FogOfWar
				local p = monster:GetPivot().Position
				local flat = Vector3.new(p.X - root.Position.X, 0, p.Z - root.Position.Z).Magnitude
				if flat <= PING_RANGE then
					ping(Vector3.new(p.X, floorY + 0.1, p.Z), 1 - flat / PING_RANGE)
				end
			end
		end
	end
end
