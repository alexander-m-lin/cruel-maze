-- THE SANDBOX PANEL: buttons down the left of the screen in the dev Sandbox match (see
-- ServerStorage.Sandbox). Developers only; the server checks every request (Match's sandboxAction).
--
--   Place (click a button, then click the floor; right-click or Esc cancels):
--     Bot, Dummy (a bot held in place), Feared dummy, AI monster, Ward, False relic
--   At once: Fear all, Freeze AI, Ready (your cooldowns), Lives, Clear (bots and AI monsters),
--            Hero (a survivor: switch to the next survivor hero, e.g. Sara -> Kai)
-- The server's answer shows under the buttons.
-- At the top, a TRACKER: where you are (studs, and the maze cell) and how fast you're moving
-- (across the floor, smoothed a little), next to the walk speed the movement rules allow you now.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
while player:GetAttribute("Dev") ~= true do player:GetAttributeChangedSignal("Dev"):Wait() end

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Net = require(ReplicatedStorage:WaitForChild("Net"))
local devEvent = Net.event("DevMatch")
local match = ReplicatedStorage:WaitForChild("Match")

local PLACE = {
	{ id = "bot", name = "Bot" },
	{ id = "dummy", name = "Dummy" },
	{ id = "fearedDummy", name = "Feared dummy" },
	{ id = "monster", name = "AI monster" },
	{ id = "ward", name = "Ward" },
	{ id = "falseRelic", name = "False relic" },
}
local NOW = {
	{ id = "fearAll", name = "Fear all" },
	{ id = "freeze", name = "Freeze AI" },
	{ id = "ready", name = "Ready" },
	{ id = "lives", name = "Lives" },
	{ id = "clear", name = "Clear" },
	{ id = "hero", name = "Hero" },
}
local ACTIVE = Color3.fromRGB(120, 60, 170)
local IDLE = Color3.fromRGB(40, 40, 46)

local gui = Instance.new("ScreenGui")
gui.Name = "SandboxPanel"
gui.ResetOnSpawn = false
gui.DisplayOrder = 10
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local column = Instance.new("Frame")
column.AnchorPoint = Vector2.new(0, 0.5)
column.Position = UDim2.new(0, 12, 0.5, 0)
column.Size = UDim2.fromOffset(130, 0)
column.AutomaticSize = Enum.AutomaticSize.Y
column.BackgroundTransparency = 1
column.Parent = gui
local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 4)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = column

local order = 0
local function label(text, size)
	order += 1
	local l = Instance.new("TextLabel")
	l.LayoutOrder = order
	l.Size = UDim2.fromOffset(130, size or 18)
	l.BackgroundTransparency = 1
	l.TextColor3 = Color3.fromRGB(235, 225, 255)
	l.TextStrokeTransparency = 0.4
	l.Font = Enum.Font.GothamBold
	l.TextSize = 13
	l.TextWrapped = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.Parent = column
	return l
end
local function button(text)
	order += 1
	local b = Instance.new("TextButton")
	b.LayoutOrder = order
	b.Size = UDim2.fromOffset(130, 26)
	b.BackgroundColor3 = IDLE
	b.BackgroundTransparency = 0.15
	b.BorderSizePixel = 0
	b.TextColor3 = Color3.fromRGB(230, 230, 230)
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 13
	b.Text = text
	b.Parent = column
	return b
end

label("SANDBOX")
local tracker = label("", 46)
tracker.Font = Enum.Font.Code
tracker.TextSize = 12
tracker.Size = UDim2.fromOffset(180, 46)   -- (wider than the buttons, so a line fits)
local result = nil
local placing = nil       -- the PLACE entry being placed, or nil
local placeButtons = {}

-- a marker on the floor under the mouse while placing
local marker = Instance.new("Part")
marker.Name = "SandboxMarker"
marker.Shape = Enum.PartType.Cylinder
marker.Anchored, marker.CanCollide, marker.CanQuery, marker.CanTouch, marker.CastShadow = true, false, false, false, false
marker.Material = Enum.Material.Neon
marker.Color = ACTIVE
marker.Transparency = 0.35
marker.Size = Vector3.new(0.15, 5, 5)

local function floorPoint()
	local maze = workspace:FindFirstChild("Maze")
	if not maze then return nil end
	local y = maze:GetAttribute("FloorY") or 0
	local mouse = UserInputService:GetMouseLocation()
	local ray = workspace.CurrentCamera:ViewportPointToRay(mouse.X, mouse.Y)
	if math.abs(ray.Direction.Y) < 1e-3 then return nil end
	local t = (y - ray.Origin.Y) / ray.Direction.Y
	if t < 0 then return nil end
	return ray.Origin + ray.Direction * t
end

local function setPlacing(entry)
	placing = entry
	for id, b in placeButtons do b.BackgroundColor3 = (entry and entry.id == id) and ACTIVE or IDLE end
	if entry then
		result.Text = "Click the floor: " .. entry.name .. " (right-click / Esc cancels)"
		ContextActionService:BindActionAtPriority("SandboxPlace", function(_, inputState, input)
			if inputState ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Sink end
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				local at = floorPoint()
				if at then devEvent:FireServer("sandboxAction", placing.id, at) end
			end
			setPlacing(nil)
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value + 100,
			Enum.UserInputType.MouseButton1, Enum.UserInputType.MouseButton2, Enum.KeyCode.Escape)
	else
		ContextActionService:UnbindAction("SandboxPlace")
		marker.Parent = nil
	end
end

label("Place", 16)
for _, entry in PLACE do
	local b = button(entry.name)
	placeButtons[entry.id] = b
	b.Activated:Connect(function() setPlacing(placing ~= entry and entry or nil) end)
end
label("Now", 16)
for _, entry in NOW do
	local b = button(entry.name)
	b.Activated:Connect(function()
		setPlacing(nil)
		devEvent:FireServer("sandboxAction", entry.id)
	end)
end
result = label("", 34)

devEvent.OnClientEvent:Connect(function(kind, ok, message)
	if kind ~= "sandboxResult" then return end
	result.Text = (ok and "" or "No: ") .. tostring(message or "")
end)

-- the tracker
local shownSpeed = 0
local function updateTracker(dt)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local maze = workspace:FindFirstChild("Maze")
	if not (root and humanoid and maze) then
		tracker.Text = "Position -\nSpeed -"
		return
	end
	local p = root.Position
	local n, size = maze:GetAttribute("Cells") or 1, maze:GetAttribute("CellSize") or 20
	local half = n * size / 2
	local cx = math.clamp(math.floor((p.X + half) / size) + 1, 1, n)
	local cz = math.clamp(math.floor((p.Z + half) / size) + 1, 1, n)
	local speed = (root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude
	shownSpeed += (speed - shownSpeed) * math.min(1, dt * 8)
	tracker.Text = ("Pos  %6.1f, %6.1f\nCell %d, %d\nSpeed %4.1f  walk %4.1f"):format(p.X, p.Z, cx, cz, shownSpeed, humanoid.WalkSpeed)
end

RunService.RenderStepped:Connect(function(dt)
	local on = match:GetAttribute("Sandbox") == true and match:GetAttribute("State") == Config.States.Playing
	if on then updateTracker(dt) end
	gui.Enabled = on
	if not on and placing then setPlacing(nil) end
	if placing then
		local at = floorPoint()
		if at then
			marker.CFrame = CFrame.new(at + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2)
			marker.Parent = workspace.CurrentCamera
		end
	end
end)
