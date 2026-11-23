-- THE LOBBY screen, shown between matches (while the match state is Waiting; see Match):
--   - who's here, and the role each of them would like
--   - your preferred role: Any, Survivor, Monster or Maze Master (you get it if a slot is free;
--     contested slots go to one of those who asked, at random)
--   - your survivor hero, if you're a survivor: Any, or one of them (Heroes.survivorIds). Survivors'
--     heroes are all different; if two want the same one, one of them gets it, at random
--   - Start: anyone can start the match. Empty slots are filled with bots.
-- Everything is a button you can click or tap.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Net = require(ReplicatedStorage:WaitForChild("Net"))
local Heroes = require(ReplicatedStorage:WaitForChild("Heroes"))
local lobbyEvent = Net.event("Lobby")
local match = ReplicatedStorage:WaitForChild("Match")
local player = Players.LocalPlayer

local PURPLE = Color3.fromRGB(150, 70, 220)
local PANEL = Color3.fromRGB(24, 20, 32)
local BUTTON = Color3.fromRGB(44, 36, 58)
local TEXT = Color3.fromRGB(235, 230, 245)
local DIM = Color3.fromRGB(160, 150, 175)

local CHOICES = {   -- { attribute value (nil = any), label }
	{ nil, "Any" },
	{ Config.Roles.Survivor, "Survivor" },
	{ Config.Roles.Monster, "Monster" },
	{ Config.Roles.MazeMaster, "Maze Master" },
}
local LABEL = { [Config.Roles.Survivor] = "Survivor", [Config.Roles.Monster] = "Monster", [Config.Roles.MazeMaster] = "Maze Master" }

local gui = Instance.new("ScreenGui")
gui.Name = "Lobby"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 8
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local backdrop = Instance.new("Frame")
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = Color3.fromRGB(6, 5, 10)
backdrop.BackgroundTransparency = 0.25
backdrop.BorderSizePixel = 0
backdrop.Parent = gui

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.new(0, 460, 0, 550)
panel.BackgroundColor3 = PANEL
panel.BorderSizePixel = 0
panel.Parent = backdrop
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)
local sizeLimit = Instance.new("UISizeConstraint")    -- fits on a phone too
sizeLimit.MaxSize = Vector2.new(460, 550)
sizeLimit.Parent = panel
local padding = Instance.new("UIPadding")
for _, side in { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" } do padding[side] = UDim.new(0, 18) end
padding.Parent = panel

local function label(text, size, color, y, height, font)
	local l = Instance.new("TextLabel")
	l.Position = UDim2.new(0, 0, 0, y)
	l.Size = UDim2.new(1, 0, 0, height)
	l.BackgroundTransparency = 1
	l.Font = font or Enum.Font.GothamMedium
	l.TextSize = size
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.Parent = panel
	return l
end

local function button(text, parent)
	local b = Instance.new("TextButton")
	b.BackgroundColor3 = BUTTON
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.Font = Enum.Font.GothamBold
	b.TextSize = 14
	b.TextColor3 = TEXT
	b.Text = text
	b.Parent = parent
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = PURPLE
	stroke.Thickness = 2
	stroke.Transparency = 1
	stroke.Parent = b
	return b, stroke
end

label("CRUEL MAZE", 28, TEXT, 0, 34, Enum.Font.GothamBlack).TextXAlignment = Enum.TextXAlignment.Center
label("Lobby", 14, DIM, 34, 18).TextXAlignment = Enum.TextXAlignment.Center

local playersTitle = label("Players", 15, TEXT, 66, 20, Enum.Font.GothamBold)
local list = Instance.new("ScrollingFrame")
list.Position = UDim2.new(0, 0, 0, 90)
list.Size = UDim2.new(1, 0, 0, 170)
list.BackgroundColor3 = Color3.fromRGB(16, 13, 22)
list.BorderSizePixel = 0
list.ScrollBarThickness = 4
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new()
list.Parent = panel
Instance.new("UICorner", list).CornerRadius = UDim.new(0, 8)
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 2)
layout.Parent = list
local listPad = Instance.new("UIPadding")
listPad.PaddingLeft, listPad.PaddingRight, listPad.PaddingTop = UDim.new(0, 10), UDim.new(0, 10), UDim.new(0, 6)
listPad.Parent = list

label("Your preferred role", 15, TEXT, 272, 20, Enum.Font.GothamBold)
local choiceRow = Instance.new("Frame")
choiceRow.Position = UDim2.new(0, 0, 0, 296)
choiceRow.Size = UDim2.new(1, 0, 0, 40)
choiceRow.BackgroundTransparency = 1
choiceRow.Parent = panel
local choiceButtons = {}
for i, choice in CHOICES do
	local b, stroke = button(choice[2], choiceRow)
	b.Position = UDim2.new((i - 1) / #CHOICES, i == 1 and 0 or 3, 0, 0)
	b.Size = UDim2.new(1 / #CHOICES, -4, 1, 0)
	b.TextSize = 13
	b.Activated:Connect(function() lobbyEvent:FireServer("prefer", choice[1]) end)
	choiceButtons[i] = { stroke = stroke, role = choice[1] }
end
label("You get it if a slot is free. Empty slots are filled with bots.", 12, DIM, 342, 16)

label("Your survivor", 15, TEXT, 370, 20, Enum.Font.GothamBold)
local heroRow = Instance.new("Frame")
heroRow.Position = UDim2.new(0, 0, 0, 394)
heroRow.Size = UDim2.new(1, 0, 0, 40)
heroRow.BackgroundTransparency = 1
heroRow.Parent = panel
local HERO_CHOICES = { { nil, "Any" } }
for _, id in Heroes.survivorIds() do
	local hero = Heroes.get(id)
	table.insert(HERO_CHOICES, { id, ("%s (%s)"):format(hero.name, hero.title) })
end
local heroButtons = {}
for i, choice in HERO_CHOICES do
	local b, stroke = button(choice[2], heroRow)
	b.Position = UDim2.new((i - 1) / #HERO_CHOICES, i == 1 and 0 or 3, 0, 0)
	b.Size = UDim2.new(1 / #HERO_CHOICES, -4, 1, 0)
	b.TextSize = 13
	b.Activated:Connect(function() lobbyEvent:FireServer("preferHero", choice[1]) end)
	heroButtons[i] = { stroke = stroke, hero = choice[1] }
end

local start = button("Start match", panel)
start.Position = UDim2.new(0, 0, 1, -58)
start.Size = UDim2.new(1, 0, 0, 52)
start.BackgroundColor3 = PURPLE
start.TextSize = 20
start.Activated:Connect(function() lobbyEvent:FireServer("start") end)

---------------------------------------------------------------- keeping it up to date
local rows = {}
local function refresh()
	local inLobby = match:GetAttribute("State") == Config.States.Waiting
	gui.Enabled = inLobby
	if not inLobby then return end
	local players = Players:GetPlayers()
	playersTitle.Text = ("Players (%d / %d)"):format(#players, Config.ROLE_SLOTS.Survivor + Config.ROLE_SLOTS.Monster + Config.ROLE_SLOTS.MazeMaster)
	for i, other in players do
		local row = rows[i]
		if not row then
			row = Instance.new("TextLabel")
			row.Size = UDim2.new(1, 0, 0, 22)
			row.BackgroundTransparency = 1
			row.Font = Enum.Font.GothamMedium
			row.TextSize = 14
			row.TextXAlignment = Enum.TextXAlignment.Left
			row.RichText = true
			row.Parent = list
			rows[i] = row
		end
		local wants = LABEL[other:GetAttribute("PreferredRole")] or "Any role"
		row.Text = ('%s%s  <font color="#a096af">%s</font>'):format(other.DisplayName, other == player and " (you)" or "", wants)
		row.TextColor3 = TEXT
		row.Visible = true
	end
	for i = #players + 1, #rows do rows[i].Visible = false end
	local mine = player:GetAttribute("PreferredRole")
	for _, c in choiceButtons do c.stroke.Transparency = c.role == mine and 0 or 1 end
	local myHero = player:GetAttribute("PreferredHero")
	for _, c in heroButtons do c.stroke.Transparency = c.hero == myHero and 0 or 1 end
	local enough = #players >= Config.MIN_PLAYERS
	start.Text = enough and "Start match" or ("Waiting for %d more..."):format(Config.MIN_PLAYERS - #players)
	start.AutoButtonColor = enough
end

match:GetAttributeChangedSignal("State"):Connect(refresh)
task.spawn(function()
	while true do    -- (names and preferences change now and then; cheap to just look again)
		refresh()
		task.wait(0.5)
	end
end)
