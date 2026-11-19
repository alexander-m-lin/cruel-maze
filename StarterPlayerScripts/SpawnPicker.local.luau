-- When you're caught (and have lives left), shows a small map of the maze with a button on each
-- spawn room your team has captured. Click one, or press its number key, to respawn there.
-- If you don't choose in time, the server brings you back in your last room.
--
-- The map is turned 45° to match the isometric camera, so "up" on the map is "up" on screen.
-- The camera looks from the -X/-Z corner, so on screen:
--   right = world (-1, 0, +1) direction,   up = world (+1, 0, +1) direction

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage:WaitForChild("Net"))
local chooseSpawn = Net.event("ChooseSpawn")
local match = ReplicatedStorage:WaitForChild("Match")

local player = Players.LocalPlayer

local MAP_SIZE = 320          -- pixels, corner to corner of the diamond
local BUTTON_SIZE = 40
local CAPTURED_COLOR = Color3.fromRGB(70, 150, 160)
local SELECTED_COLOR = Color3.fromRGB(255, 220, 120)

local screen = Instance.new("ScreenGui")
screen.Name = "SpawnPicker"
screen.ResetOnSpawn = false
screen.DisplayOrder = 10
screen.Enabled = false
screen.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.55)
panel.Size = UDim2.fromOffset(MAP_SIZE + 60, MAP_SIZE + 90)
panel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
panel.BackgroundTransparency = 0.25
panel.Parent = screen
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, 0, 0, 40)
title.Position = UDim2.fromOffset(0, 8)
title.Font = Enum.Font.GothamBold
title.TextSize = 20
title.TextColor3 = Color3.new(1, 1, 1)
title.Text = "Choose where to respawn"
title.Parent = panel

local map = Instance.new("Frame")             -- the area the diamond sits in
map.BackgroundTransparency = 1
map.AnchorPoint = Vector2.new(0.5, 0)
map.Position = UDim2.new(0.5, 0, 0, 56)
map.Size = UDim2.fromOffset(MAP_SIZE, MAP_SIZE)
map.Parent = panel

local outline = Instance.new("Frame")         -- the maze's outline: a square turned 45°
outline.AnchorPoint = Vector2.new(0.5, 0.5)
outline.Position = UDim2.fromScale(0.5, 0.5)
outline.Size = UDim2.fromOffset(MAP_SIZE / math.sqrt(2), MAP_SIZE / math.sqrt(2))
outline.Rotation = 45
outline.BackgroundColor3 = Color3.fromRGB(60, 62, 70)
outline.BackgroundTransparency = 0.3
outline.Parent = map
local stroke = Instance.new("UIStroke", outline)
stroke.Color = Color3.fromRGB(140, 150, 130)
stroke.Thickness = 2

-- Where a world position appears on the map (pixels from the map's top-left)
local function toMap(worldPos)
	local maze = workspace:FindFirstChild("Maze")
	local half = maze and maze:GetAttribute("Cells") * maze:GetAttribute("CellSize") / 2 or 150
	local u = (-worldPos.X + worldPos.Z) / (2 * half)    -- -1..1, left to right
	local v = (worldPos.X + worldPos.Z) / (2 * half)     -- -1..1, bottom to top
	return Vector2.new(MAP_SIZE / 2 + u * MAP_SIZE / 2, MAP_SIZE / 2 - v * MAP_SIZE / 2)
end

local buttons = {}
local function choose(roomId)
	if not player:GetAttribute("Respawning") then return end
	chooseSpawn:FireServer(roomId)
	title.Text = "Respawning..."
end

local function rebuild()
	for _, b in buttons do b:Destroy() end
	table.clear(buttons)
	local rooms = match:FindFirstChild("SpawnRooms")
	if not rooms then return end
	local list = rooms:GetChildren()
	table.sort(list, function(a, b) return a:GetAttribute("Id") < b:GetAttribute("Id") end)
	for _, info in list do
		if not info:GetAttribute("Captured") then continue end   -- only rooms your team has found
		local id = info:GetAttribute("Id")
		local b = Instance.new("TextButton")
		b.AnchorPoint = Vector2.new(0.5, 0.5)
		b.Position = UDim2.fromOffset(toMap(info:GetAttribute("Center")).X, toMap(info:GetAttribute("Center")).Y)
		b.Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE)
		b.BackgroundColor3 = CAPTURED_COLOR
		b.Font = Enum.Font.GothamBold
		b.TextSize = 18
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Text = tostring(id)
		b.ZIndex = 3
		b.Parent = map
		Instance.new("UICorner", b).CornerRadius = UDim.new(1, 0)
		local ring = Instance.new("UIStroke", b)
		ring.Thickness = 3
		ring.Color = SELECTED_COLOR
		ring.Enabled = player:GetAttribute("SpawnRoom") == id   -- your last room: the default
		b.Activated:Connect(function() choose(id) end)
		buttons[id] = b
	end
end

local function update()
	local show = player:GetAttribute("Respawning") == true
	if show and not screen.Enabled then
		title.Text = "Choose where to respawn"
		rebuild()
	end
	screen.Enabled = show
end
player:GetAttributeChangedSignal("Respawning"):Connect(update)
update()

-- Number keys pick a room too
local NUMBER_KEYS = {
	[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3, [Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6,
}
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not screen.Enabled then return end
	local id = NUMBER_KEYS[input.KeyCode]
	if id and buttons[id] then choose(id) end
end)
