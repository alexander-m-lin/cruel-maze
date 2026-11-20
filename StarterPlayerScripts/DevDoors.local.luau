-- A developer panel for the maze's doors. Only for developers: in Studio, or the experience's owner (the server checks).
--
--   "Doors" button (bottom left) - show or hide the panel
--   G                            - open or shut the door nearest the mouse
--   panel                        - switch the door AI on or off, open or shut every door, or
--                                  any one door (each button shows its number, kind and state)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Only for developers (in Studio, or the experience's owner; the server decides, see Dev)
local localPlayer = Players.LocalPlayer
while localPlayer:GetAttribute("Dev") ~= true do localPlayer:GetAttributeChangedSignal("Dev"):Wait() end

local Net = require(ReplicatedStorage:WaitForChild("Net"))
local devEvent = Net.event("DevDoors")
local match = ReplicatedStorage:WaitForChild("Match")
local player = Players.LocalPlayer
local mouse = player:GetMouse()

local PICK_RANGE = 14   -- G picks a door within this many studs of the point under the mouse

local gui = Instance.new("ScreenGui")
gui.Name = "DevDoors"
gui.ResetOnSpawn = false
gui.DisplayOrder = 10
gui.Parent = player:WaitForChild("PlayerGui")

local function button(text, parent, size)
	local b = Instance.new("TextButton")
	b.Size = size or UDim2.new(1, 0, 0, 22)
	b.BackgroundColor3 = Color3.fromRGB(40, 40, 46)
	b.BackgroundTransparency = 0.15
	b.BorderSizePixel = 0
	b.TextColor3 = Color3.fromRGB(230, 230, 230)
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 13
	b.Text = text
	b.AutoButtonColor = true
	b.Parent = parent
	return b
end

local toggle = button("Doors", gui, UDim2.fromOffset(70, 26))
toggle.AnchorPoint = Vector2.new(0, 1)
toggle.Position = UDim2.new(0, 12, 1, -12)

local panel = Instance.new("ScrollingFrame")
panel.AnchorPoint = Vector2.new(0, 1)
panel.Position = UDim2.new(0, 12, 1, -44)
panel.Size = UDim2.fromOffset(190, 340)
panel.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
panel.BackgroundTransparency = 0.2
panel.BorderSizePixel = 0
panel.ScrollBarThickness = 6
panel.AutomaticCanvasSize = Enum.AutomaticSize.Y
panel.CanvasSize = UDim2.new()
panel.Visible = false
panel.Parent = gui
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 3)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = panel
local pad = Instance.new("UIPadding")
for _, side in { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" } do pad[side] = UDim.new(0, 6) end
pad.Parent = panel

toggle.Activated:Connect(function() panel.Visible = not panel.Visible end)

local aiButton = button("", panel)
aiButton.LayoutOrder = 1
aiButton.Activated:Connect(function()
	devEvent:FireServer("ai", match:GetAttribute("DoorAI") == false)
end)
local openAll = button("Open all", panel)
openAll.LayoutOrder = 2
openAll.Activated:Connect(function() devEvent:FireServer("all", true) end)
local shutAll = button("Shut all", panel)
shutAll.LayoutOrder = 3
shutAll.Activated:Connect(function() devEvent:FireServer("all", false) end)

local doorButtons = {}   -- [door part] = button

local function doors()
	local maze = workspace:FindFirstChild("Maze")
	local list = {}
	if maze then
		for _, child in maze:GetChildren() do
			if child.Name == "Door" and child:GetAttribute("Id") then table.insert(list, child) end
		end
	end
	return list
end

-- G: the door nearest the point under the mouse
UserInputService.InputBegan:Connect(function(input, typing)
	if typing or input.KeyCode ~= Enum.KeyCode.G then return end
	local hit = mouse.Hit.Position
	local best, bestDist
	for _, part in doors() do
		local at = (part:GetAttribute("ClosedCFrame") or part.CFrame).Position
		local d = (Vector3.new(at.X, 0, at.Z) - Vector3.new(hit.X, 0, hit.Z)).Magnitude
		if d < PICK_RANGE and (not bestDist or d < bestDist) then best, bestDist = part, d end
	end
	if best then devEvent:FireServer("toggle", best:GetAttribute("Id")) end
end)

RunService.Heartbeat:Connect(function()
	if not panel.Visible then return end
	aiButton.Text = match:GetAttribute("DoorAI") == false and "AI: off (click for on)" or "AI: on (click for off)"
	local current = {}
	for _, part in doors() do
		current[part] = true
		local b = doorButtons[part]
		if not b then
			b = button("", panel)
			b.TextXAlignment = Enum.TextXAlignment.Left
			b.LayoutOrder = 10 + part:GetAttribute("Id")
			b.Activated:Connect(function() devEvent:FireServer("toggle", part:GetAttribute("Id")) end)
			doorButtons[part] = b
		end
		local state = part:GetAttribute("State") or "?"
		local open = part:GetAttribute("Open")
		if state == "warning" or state == "moving" then state = open and "opening" or "closing" end
		b.Text = ("  #%d  %s  -  %s"):format(part:GetAttribute("Id"), part:GetAttribute("Kind") or "", state)
	end
	for part, b in doorButtons do
		if not current[part] then b:Destroy() doorButtons[part] = nil end
	end
end)
