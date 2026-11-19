-- The minimap: a small map in the top-right corner showing what your team knows.
--
--   never seen        - dark
--   seen before       - dim (walls a little lighter than floor)
--   in view right now - bright (yours and your teammates' sight, and the areas around spotted relics)
--   dots              - you (white), teammates (cyan), relics your team has spotted and not yet
--                       collected (gold), the monster while your team can see it (red)
--
-- It's turned to match the camera (the top of the map is the top of your screen), like the spawn
-- room picker. Press M to hide or show it.
--
-- The fog picture comes from the FogOfWar script (through FogState). It's drawn into a small
-- image one pixel at a time (an EditableImage), refreshed several times a second.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local AssetService = game:GetService("AssetService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local FogState = require(script.Parent:WaitForChild("FogState"))

local player = Players.LocalPlayer
local match = ReplicatedStorage:WaitForChild("Match")

local PIXELS = 160            -- the fog picture's resolution (it's scaled to the map's size on screen)
local MAX_SIZE = 250          -- map size on screen (pixels), at most...
local SCREEN_SHARE = 0.3      -- ...and at most this share of the screen's shorter side
local REFRESH_EVERY = 0.1     -- seconds between fog redraws
local TOGGLE_KEY = Enum.KeyCode.M

-- Colours: { r, g, b, alpha } (0-255)
local NEVER_SEEN   = { 12, 12, 18, 235 }
local SEEN_FLOOR   = { 88, 86, 76, 245 }
local SEEN_WALL    = { 140, 148, 118, 255 }
local VIEW_FLOOR   = { 185, 180, 156, 255 }
local VIEW_WALL    = { 235, 240, 205, 255 }
local DOT_SELF     = Color3.fromRGB(255, 255, 255)
local DOT_ALLY     = Color3.fromRGB(80, 220, 235)
local DOT_RELIC    = Color3.fromRGB(255, 205, 80)
local DOT_MONSTER  = Color3.fromRGB(255, 50, 50)

---------------------------------------------------------------- the frame
local gui = Instance.new("ScreenGui")
gui.Name = "Minimap"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Name = "Map"
frame.AnchorPoint = Vector2.new(1, 0)
frame.Position = UDim2.new(1, -16, 0, 16)
frame.BackgroundTransparency = 1
frame.Visible = false
frame.Parent = gui

-- A thin outline around the maze's diamond, so its edge shows even where nothing's been seen
local outline = Instance.new("Frame")
outline.Name = "Outline"
outline.AnchorPoint = Vector2.new(0.5, 0.5)
outline.Position = UDim2.fromScale(0.5, 0.5)
outline.Size = UDim2.fromScale(1 / math.sqrt(2) / 1.04, 1 / math.sqrt(2) / 1.04)   -- (1.04 = MARGIN below)
outline.Rotation = 45
outline.BackgroundTransparency = 1
outline.ZIndex = 2
outline.Parent = frame
local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(150, 150, 140)
stroke.Thickness = 1.5
stroke.Transparency = 0.2
stroke.Parent = outline

local picture = Instance.new("ImageLabel")
picture.Name = "Fog"
picture.Size = UDim2.fromScale(1, 1)
picture.BackgroundTransparency = 1
picture.Parent = frame

local dotLayer = Instance.new("Frame")
dotLayer.Name = "Dots"
dotLayer.Size = UDim2.fromScale(1, 1)
dotLayer.BackgroundTransparency = 1
dotLayer.ZIndex = 2
dotLayer.Parent = frame

local function resize()
	local view = workspace.CurrentCamera.ViewportSize
	local size = math.floor(math.min(MAX_SIZE, math.min(view.X, view.Y) * SCREEN_SHARE))
	frame.Size = UDim2.fromOffset(size, size)
end
resize()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(resize)

local hidden = false
UserInputService.InputBegan:Connect(function(input, typing)
	if not typing and input.KeyCode == TOGGLE_KEY then hidden = not hidden end
end)

---------------------------------------------------------------- map <-> world
-- Same turn as the camera and the spawn picker: u runs left to right, v bottom to top, each
-- -1..1 across the maze (which makes the square maze a diamond).
local MARGIN = 1.04           -- a little space around the maze's corners
local function toMap(worldPos, half)
	local u = (-worldPos.X + worldPos.Z) / (2 * half) / MARGIN
	local v = (worldPos.X + worldPos.Z) / (2 * half) / MARGIN
	return (u + 1) / 2, (1 - v) / 2          -- 0..1 across the frame, left->right and top->bottom
end

---------------------------------------------------------------- the fog picture
local image = nil
local ok, err = pcall(function()
	image = AssetService:CreateEditableImage({ Size = Vector2.new(PIXELS, PIXELS) })
	picture.ImageContent = Content.fromObject(image)
end)
if not ok then
	warn("Minimap: can't draw the fog picture here (" .. tostring(err) .. "); showing dots only")
	image = nil
	picture.BackgroundTransparency = 0.3
	picture.BackgroundColor3 = Color3.fromRGB(12, 12, 18)
end

local buf = buffer.create(PIXELS * PIXELS * 4)
local pixelTile = {}          -- [pixel index] = the fog tile it shows, or false (outside the maze)
local builtFor = nil          -- the FogState.tiles table pixelTile was worked out for

-- Which tile each pixel shows, worked out once per maze
local function mapPixels()
	local tiles, count, size, half = FogState.tiles, FogState.count, FogState.tileSize, FogState.half
	for j = 0, PIXELS - 1 do
		for i = 0, PIXELS - 1 do
			local u = ((i + 0.5) / PIXELS * 2 - 1) * MARGIN
			local v = (1 - (j + 0.5) / PIXELS * 2) * MARGIN
			local x, z = half * (v - u), half * (u + v)          -- (the inverse of toMap)
			local tx = math.floor((x + half) / size) + 1
			local tz = math.floor((z + half) / size) + 1
			local row = tiles[tx]
			pixelTile[j * PIXELS + i] = row and row[tz] or false
		end
	end
	builtFor = tiles
end

local function put(index, c)
	local at = index * 4
	buffer.writeu8(buf, at, c[1])
	buffer.writeu8(buf, at + 1, c[2])
	buffer.writeu8(buf, at + 2, c[3])
	buffer.writeu8(buf, at + 3, c[4])
end

local function drawFog()
	if not image or not FogState.tiles then return end
	if builtFor ~= FogState.tiles then mapPixels() end
	local visible = FogState.visible
	for index = 0, PIXELS * PIXELS - 1 do
		local tile = pixelTile[index]
		if not tile then
			buffer.writeu32(buf, index * 4, 0)              -- outside the maze: see-through
		elseif not tile.explored then
			put(index, NEVER_SEEN)
		elseif visible[tile] then
			put(index, tile.onWall and VIEW_WALL or VIEW_FLOOR)
		else
			put(index, tile.onWall and SEEN_WALL or SEEN_FLOOR)
		end
	end
	image:WritePixelsBuffer(Vector2.zero, Vector2.new(PIXELS, PIXELS), buf)
end

---------------------------------------------------------------- dots
local dots = {}               -- reused each frame: [n] = Frame
local used = 0

local function dot(worldPos, color, size, half, square)
	used += 1
	local d = dots[used]
	if not d then
		d = Instance.new("Frame")
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.BorderSizePixel = 0
		d.ZIndex = 3
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = d
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.new(0, 0, 0)
		stroke.Thickness = 1
		stroke.Transparency = 0.3
		stroke.Parent = d
		d.Parent = dotLayer
		dots[used] = d
	end
	local x, y = toMap(worldPos, half)
	d.Position = UDim2.fromScale(x, y)
	d.Size = UDim2.fromOffset(size, size)
	d.BackgroundColor3 = color
	d.Rotation = square and 45 or 0
	d.UICorner.CornerRadius = UDim.new(square and 0 or 0.5, 0)
	d.Visible = true
	d.ZIndex = color == DOT_SELF and 4 or 3
end

local function aliveRoot(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then return character:FindFirstChild("HumanoidRootPart") end
	return nil
end

local function drawDots(half)
	used = 0
	-- relics your team has spotted and not collected yet
	local relics = match:FindFirstChild("Relics")
	if relics then
		for _, info in relics:GetChildren() do
			if info:GetAttribute("Discovered") and not info:GetAttribute("Collected") then
				dot(info:GetAttribute("Center"), DOT_RELIC, 8, half, true)
			end
		end
	end
	-- the monster, while your team can see it (the fog script decides)
	for _, monster in CollectionService:GetTagged("Monster") do
		if monster:GetAttribute("VisibleToMe") then
			dot(monster:GetPivot().Position, DOT_MONSTER, 10, half)
		end
	end
	-- teammates, then you on top
	local myRole = player:GetAttribute("Role")
	for _, other in Players:GetPlayers() do
		local root = other ~= player and myRole and other:GetAttribute("Role") == myRole and aliveRoot(other.Character)
		if root then dot(root.Position, DOT_ALLY, 8, half) end
	end
	local myRoot = aliveRoot(player.Character)
	if myRoot then dot(myRoot.Position, DOT_SELF, 9, half) end
	for n = used + 1, #dots do dots[n].Visible = false end
end

---------------------------------------------------------------- every frame
local lastDraw = 0
RunService.RenderStepped:Connect(function()
	local state = match:GetAttribute("State")
	local inMatch = state == Config.States.Countdown or state == Config.States.Playing
	local maze = workspace:FindFirstChild("Maze")
	local ready = inMatch and maze and FogState.maze == maze and FogState.tiles ~= nil
	frame.Visible = ready and not hidden
	if not frame.Visible then return end

	local now = os.clock()
	if now - lastDraw >= REFRESH_EVERY then
		lastDraw = now
		drawFog()
	end
	drawDots(FogState.half)
end)
