-- When you click a FALSE RELIC (a Maze Master's trap): a red border round the screen and the words
-- "FALSE RELIC", fading out while you're revealed to the monsters (Config.FALSE_RELIC_REVEAL_TIME).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Net = require(ReplicatedStorage:WaitForChild("Net"))
local player = Players.LocalPlayer

local RED = Color3.fromRGB(220, 30, 30)
local BORDER = 70   -- pixels the red glow reaches in from each edge

local gui = Instance.new("ScreenGui")
gui.Name = "FalseRelicAlert"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 5
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

-- four edges, each a red gradient fading toward the middle of the screen
local edges = {}
local function edge(anchor, position, size, rotation)
	local f = Instance.new("Frame")
	f.AnchorPoint, f.Position, f.Size = anchor, position, size
	f.BackgroundColor3 = RED
	f.BorderSizePixel = 0
	local g = Instance.new("UIGradient")
	g.Rotation = rotation
	g.Transparency = NumberSequence.new(0, 1)   -- solid at the edge, clear inward
	g.Parent = f
	f.Parent = gui
	table.insert(edges, f)
end
edge(Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.new(1, 0, 0, BORDER), 90)     -- top
edge(Vector2.new(0, 1), UDim2.fromScale(0, 1), UDim2.new(1, 0, 0, BORDER), -90)    -- bottom
edge(Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.new(0, BORDER, 1, 0), 0)      -- left
edge(Vector2.new(1, 0), UDim2.fromScale(1, 0), UDim2.new(0, BORDER, 1, 0), 180)    -- right

local label = Instance.new("TextLabel")
label.AnchorPoint = Vector2.new(0.5, 0.5)
label.Position = UDim2.fromScale(0.5, 0.32)
label.Size = UDim2.fromOffset(600, 70)
label.BackgroundTransparency = 1
label.Font = Enum.Font.GothamBlack
label.TextSize = 48
label.TextColor3 = RED
label.Text = "FALSE RELIC"
label.Parent = gui
local stroke = Instance.new("UIStroke")
stroke.Color = Color3.new(0, 0, 0)
stroke.Thickness = 2
stroke.Parent = label

local shownAt = 0
Net.event("FalseRelicSprung").OnClientEvent:Connect(function()
	local me = os.clock()
	shownAt = me
	gui.Enabled = true
	local fade = TweenInfo.new(Config.FALSE_RELIC_REVEAL_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _, f in edges do
		f.BackgroundTransparency = 0
		TweenService:Create(f, fade, { BackgroundTransparency = 1 }):Play()
	end
	label.TextTransparency = 0
	stroke.Transparency = 0
	TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
	TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
	task.delay(Config.FALSE_RELIC_REVEAL_TIME, function()
		if shownAt == me then gui.Enabled = false end
	end)
end)
