-- Developer buttons for testing roles. Only for developers: in Studio, or the experience's owner (the server checks).
--
--   "Role: ..."  - click to cycle the role you want next match: Random, Survivor, Monster, Maze Master
--   "New match"  - end this match now and start another (with your picked role)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Only for developers (in Studio, or the experience's owner; the server decides, see Dev)
local localPlayer = Players.LocalPlayer
while localPlayer:GetAttribute("Dev") ~= true do localPlayer:GetAttributeChangedSignal("Dev"):Wait() end

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Net = require(ReplicatedStorage:WaitForChild("Net"))
local devEvent = Net.event("DevMatch")
local player = Players.LocalPlayer

local CYCLE = { false, Config.Roles.Survivor, Config.Roles.Monster, Config.Roles.MazeMaster }
local NAMES = { [Config.Roles.Survivor] = "Survivor", [Config.Roles.Monster] = "Monster", [Config.Roles.MazeMaster] = "Maze Master" }

local gui = Instance.new("ScreenGui")
gui.Name = "DevMatch"
gui.ResetOnSpawn = false
gui.DisplayOrder = 10
gui.Parent = player:WaitForChild("PlayerGui")

local function button(text, x)
	local b = Instance.new("TextButton")
	b.AnchorPoint = Vector2.new(0, 1)
	b.Position = UDim2.new(0, x, 1, -12)
	b.Size = UDim2.fromOffset(120, 26)
	b.BackgroundColor3 = Color3.fromRGB(40, 40, 46)
	b.BackgroundTransparency = 0.15
	b.BorderSizePixel = 0
	b.TextColor3 = Color3.fromRGB(230, 230, 230)
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 13
	b.Text = text
	b.Parent = gui
	return b
end

local roleButton = button("", 88)       -- (the Doors button sits at x = 12)
local restartButton = button("New match", 214)

local function refresh()
	local wanted = player:GetAttribute("DevRole")
	roleButton.Text = "Role: " .. (wanted and NAMES[wanted] or "Random")
end
player:GetAttributeChangedSignal("DevRole"):Connect(refresh)
refresh()

roleButton.Activated:Connect(function()
	local current = player:GetAttribute("DevRole") or false
	local i = table.find(CYCLE, current) or 1
	local nextRole = CYCLE[i % #CYCLE + 1]
	devEvent:FireServer("role", nextRole or nil)
end)
restartButton.Activated:Connect(function() devEvent:FireServer("restart") end)
