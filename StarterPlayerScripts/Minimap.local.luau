-- The minimap: a small map in the top-right corner showing what your team knows.
--
--   never seen        - dark
--   seen before       - dim (walls a little lighter than floor)
--   in view right now - bright (yours and your teammates' sight, and the areas around spotted relics)
--   teal              - sanctuaries your team has captured
--   dots              - you (white), teammates (cyan), relics your team has spotted and not yet
--                       collected (gold), enemies while your team can see them (red)
-- Teams: survivors, or the monster side (monsters and the Maze Master). On the monster side every
-- monster is a teammate, survivors are the enemies, and the Maze Master sees every relic.
--
-- It's turned to match the camera (the top of the map is the top of your screen), like the spawn
-- sanctuary picker. Press M to hide or show it.
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
local SANCTUARY_SEEN    = { 48, 112, 120, 250 }     -- a sanctuary your team has captured...
local SANCTUARY_VIEW    = { 80, 178, 190, 255 }     -- ...and while it's in view
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
local pixelX, pixelZ = {}, {} -- [pixel index] = the world position it shows
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
			local index = j * PIXELS + i
			pixelTile[index] = row and row[tz] or false
			pixelX[index], pixelZ[index] = x, z
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

	-- captured sanctuaries: the block of cells between each one's corners (Min, Max)
	local sanctuaries = {}
	local folder = match:FindFirstChild("Sanctuaries")
	if folder then
		for _, info in folder:GetChildren() do
			local lo, hi = info:GetAttribute("Min"), info:GetAttribute("Max")
			if info:GetAttribute("Captured") and lo and hi then table.insert(sanctuaries, { lo, hi }) end
		end
	end
	local function inSanctuary(index)
		local x, z = pixelX[index], pixelZ[index]
		for _, b in sanctuaries do
			if x > b[1].X and x < b[2].X and z > b[1].Z and z < b[2].Z then return true end
		end
		return false
	end

	for index = 0, PIXELS * PIXELS - 1 do
		local tile = pixelTile[index]
		if not tile then
			buffer.writeu32(buf, index * 4, 0)              -- outside the maze: see-through
		elseif not tile.onWall and #sanctuaries > 0 and inSanctuary(index) then
			put(index, visible[tile] and SANCTUARY_VIEW or SANCTUARY_SEEN)
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
	local myRole = player:GetAttribute("Role")
	local Roles = Config.Roles
	local monsterSide = myRole == Roles.Monster or myRole == Roles.MazeMaster
	-- relics your team has spotted and not collected yet (the Maze Master knows them all)
	local relics = match:FindFirstChild("Relics")
	if relics then
		for _, info in relics:GetChildren() do
			local known = (myRole == Roles.MazeMaster) or (monsterSide and info:GetAttribute("MonsterDiscovered"))
				or (not monsterSide and info:GetAttribute("Discovered"))
			if known and not info:GetAttribute("Collected") then
				dot(info:GetAttribute("Center"), DOT_RELIC, 8, half, true)
			end
		end
	end
	-- monsters: teammates on the monster side (except your own body: that's you), else enemies
	-- shown while your team can see them (the fog script decides)
	for _, monster in CollectionService:GetTagged("Monster") do
		if monsterSide then
			if monster:GetAttribute("OwnerUserId") ~= player.UserId then
				dot(monster:GetPivot().Position, DOT_ALLY, 10, half)
			end
		elseif monster:GetAttribute("VisibleToMe") then
			dot(monster:GetPivot().Position, DOT_MONSTER, 10, half)
		end
	end
	-- survivor bots: teammates for survivors; for the monster side, enemies while seen
	for _, bot in CollectionService:GetTagged("SurvivorBot") do
		local root = aliveRoot(bot)
		if root and (not monsterSide or bot:GetAttribute("VisibleToMe")) then
			dot(root.Position, monsterSide and DOT_MONSTER or DOT_ALLY, 8, half)
		end
	end
	-- survivors: teammates for survivors; for the monster side, enemies while seen
	for _, other in Players:GetPlayers() do
		if other == player or other:GetAttribute("Role") ~= Roles.Survivor then continue end
		local root = aliveRoot(other.Character)
		if not root then continue end
		if not monsterSide then
			dot(root.Position, DOT_ALLY, 8, half)
		elseif other.Character:GetAttribute("VisibleToMe") then
			dot(root.Position, DOT_MONSTER, 9, half)
		end
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
