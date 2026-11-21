-- The MAZE MASTER's interface (only while you're the Maze Master). The camera pans over the maze
-- (IsometricCamera); this script adds:
--
--   a DARK MANA bar (only while Config.DARK_MANA_ENABLED) and five TOOL buttons along the bottom
--   (or keys 1-5):
--     Door           - click near a door to open or shut it
--     Ward           - click a cell to place a ward (a floating eye) there
--     Haunt          - click a survivor you can see to haunt them
--     False relic    - click a cell to place a false relic there
--     Crushing wall  - click near a crushing wall to set it off
--   Each button shows its cost and, while it recharges, how long is left.
--   Outlines in the world: with Door picked, every door (purple = ready, grey = resting or moving);
--   with Crushing wall picked, every crushing wall's cell. The one nearest the mouse is brighter.
--   With False relic or Ward picked, the cell under the mouse lights up: green = one can go
--   there, red = it can't (amber = it could, but you can't afford one or have none left).
--   With Haunt picked, every survivor you can see is outlined.
--
-- Clicks and taps both work (no hover needed). The server checks everything (MazeMaster) and
-- answers with a short message, shown above the bar.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Net = require(ReplicatedStorage:WaitForChild("Net"))
local FogState = require(script.Parent:WaitForChild("FogState"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local match = ReplicatedStorage:WaitForChild("Match")
local toolEvent = Net.event("MazeMasterTool")
local resultEvent = Net.event("MazeMasterResult")

local PICK_RANGE = 14                                   -- a click this close to a door or crusher picks it
local PURPLE = Color3.fromRGB(150, 70, 220)
local PURPLE_BRIGHT = Color3.fromRGB(205, 140, 255)
local GREY = Color3.fromRGB(110, 110, 120)

local TOOLS = {
	{ id = "Door", name = "Door", key = Enum.KeyCode.One },
	{ id = "Ward", name = "Ward", key = Enum.KeyCode.Two },
	{ id = "Haunt", name = "Haunt", key = Enum.KeyCode.Three },
	{ id = "FalseRelic", name = "False relic", key = Enum.KeyCode.Four },
	{ id = "Crusher", name = "Crushing wall", key = Enum.KeyCode.Five },
}
local selected = "Door"

---------------------------------------------------------------- the panel
local gui = Instance.new("ScreenGui")
gui.Name = "MazeMasterUI"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.Position = UDim2.new(0.5, 0, 1, -16)
panel.Size = UDim2.fromOffset(620, 104)
panel.BackgroundTransparency = 1
panel.Parent = gui

local message = Instance.new("TextLabel")
message.AnchorPoint = Vector2.new(0.5, 1)
message.Position = UDim2.new(0.5, 0, 0, -6)
message.Size = UDim2.new(1, 0, 0, 22)
message.BackgroundTransparency = 1
message.Font = Enum.Font.GothamMedium
message.TextSize = 15
message.TextColor3 = Color3.fromRGB(235, 225, 245)
message.TextStrokeTransparency = 0.4
message.Text = ""
message.Parent = panel

local barBack = Instance.new("Frame")
barBack.Size = UDim2.new(1, 0, 0, 22)
barBack.BackgroundColor3 = Color3.fromRGB(22, 16, 30)
barBack.BackgroundTransparency = 0.1
barBack.BorderSizePixel = 0
barBack.Parent = panel
Instance.new("UICorner", barBack).CornerRadius = UDim.new(0, 6)
local barFill = Instance.new("Frame")
barFill.Size = UDim2.fromScale(1, 1)
barFill.BackgroundColor3 = PURPLE
barFill.BorderSizePixel = 0
barFill.Parent = barBack
Instance.new("UICorner", barFill).CornerRadius = UDim.new(0, 6)
local barText = Instance.new("TextLabel")
barText.Size = UDim2.fromScale(1, 1)
barText.BackgroundTransparency = 1
barText.Font = Enum.Font.GothamBold
barText.TextSize = 14
barText.TextColor3 = Color3.new(1, 1, 1)
barText.ZIndex = 2
barText.Parent = barBack

local buttons = {}
for i, tool in TOOLS do
	local b = Instance.new("TextButton")
	b.Position = UDim2.new((i - 1) / #TOOLS, i == 1 and 0 or 4, 0, 30)
	b.Size = UDim2.new(1 / #TOOLS, -6, 0, 74)
	b.BackgroundColor3 = Color3.fromRGB(34, 26, 44)
	b.BackgroundTransparency = 0.1
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.Font = Enum.Font.GothamBold
	b.TextSize = 14
	b.TextColor3 = Color3.new(1, 1, 1)
	b.TextWrapped = true
	b.Parent = panel
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = PURPLE_BRIGHT
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = b
	local shade = Instance.new("Frame")              -- darkens the button while it recharges
	shade.Name = "Shade"
	shade.AnchorPoint = Vector2.new(0, 1)
	shade.Position = UDim2.fromScale(0, 1)
	shade.Size = UDim2.fromScale(1, 0)
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 0.45
	shade.BorderSizePixel = 0
	shade.ZIndex = 2
	shade.Parent = b
	Instance.new("UICorner", shade).CornerRadius = UDim.new(0, 8)
	b.Activated:Connect(function() selected = tool.id end)
	buttons[tool.id] = { button = b, stroke = stroke, shade = shade, tool = tool }
end

local messageUntil = 0
local function say(text)
	message.Text = text
	messageUntil = os.clock() + 2.5
end
resultEvent.OnClientEvent:Connect(function(ok, text)
	if not ok and text and text ~= "" then say(text) end
end)

---------------------------------------------------------------- the world
local function isMazeMaster()
	local state = match:GetAttribute("State")
	return player:GetAttribute("Role") == Config.Roles.MazeMaster
		and (state == Config.States.Countdown or state == Config.States.Playing)
end

-- the floor point under a position: from GetMouseLocation (viewport pixels), or - with
-- `guiInset` - from a touch's InputObject.Position (which is measured below the top bar)
local function floorPoint(screen, guiInset)
	local maze = workspace:FindFirstChild("Maze")
	local y = maze and maze:GetAttribute("FloorY") or 0
	local ray = guiInset and camera:ScreenPointToRay(screen.X, screen.Y) or camera:ViewportPointToRay(screen.X, screen.Y)
	if math.abs(ray.Direction.Y) < 1e-4 then return nil end
	local t = (y - ray.Origin.Y) / ray.Direction.Y
	return t > 0 and ray.Origin + ray.Direction * t or nil
end

local function doorsList()
	local list = {}
	local maze = workspace:FindFirstChild("Maze")
	if maze then
		for _, c in maze:GetChildren() do
			if c.Name == "Door" and c:GetAttribute("Id") then table.insert(list, c) end
		end
	end
	return list
end

-- crushers: [id] = centre on the floor (between its two slabs' home spots)
local function crushersList()
	local list = {}
	local maze = workspace:FindFirstChild("Maze")
	if maze then
		local sums = {}
		for _, c in maze:GetChildren() do
			local id, home = c:GetAttribute("Id"), c:GetAttribute("Home")
			if c.Name == "Crusher" and id and home then
				sums[id] = sums[id] or { p = Vector3.zero, n = 0, slab = c }
				sums[id].p += home.Position
				sums[id].n += 1
			end
		end
		local floorY = maze:GetAttribute("FloorY") or 0
		for id, sum in sums do
			local p = sum.p / sum.n
			list[id] = { center = Vector3.new(p.X, floorY, p.Z), slab = sum.slab }
		end
	end
	return list
end

local function nearestDoor(point)
	local best, bestDist
	for _, part in doorsList() do
		local at = (part:GetAttribute("ClosedCFrame") or part.CFrame).Position
		local d = (Vector3.new(at.X, 0, at.Z) - Vector3.new(point.X, 0, point.Z)).Magnitude
		if d < PICK_RANGE and (not bestDist or d < bestDist) then best, bestDist = part, d end
	end
	return best
end

local function nearestCrusher(point)
	local best, bestDist
	for id, c in crushersList() do
		local d = (Vector3.new(c.center.X, 0, c.center.Z) - Vector3.new(point.X, 0, point.Z)).Magnitude
		if d < PICK_RANGE and (not bestDist or d < bestDist) then best, bestDist = id, d end
	end
	return best
end

-- Survivors you can see right now (FogOfWar marks each "VisibleToMe"): [character] = UserId
local function visibleSurvivors()
	local list = {}
	for _, other in Players:GetPlayers() do
		local character = other.Character
		if character and other:GetAttribute("Role") == Config.Roles.Survivor and character:GetAttribute("VisibleToMe") then
			list[character] = other.UserId
		end
	end
	for _, bot in CollectionService:GetTagged("SurvivorBot") do
		if bot:GetAttribute("VisibleToMe") then list[bot] = bot:GetAttribute("BotUserId") end
	end
	return list
end

local function nearestSurvivor(point)
	local best, bestId, bestDist
	for character, userId in visibleSurvivors() do
		local p = character:GetPivot().Position
		local d = (Vector3.new(p.X, 0, p.Z) - Vector3.new(point.X, 0, point.Z)).Magnitude
		if d < PICK_RANGE and (not bestDist or d < bestDist) then best, bestId, bestDist = character, userId, d end
	end
	return best, bestId
end

local function use(screen, guiInset)
	local point = floorPoint(screen, guiInset)
	if not point then return end
	if selected == "Door" then
		local door = nearestDoor(point)
		if door then toolEvent:FireServer("Door", door:GetAttribute("Id")) else say("Click near a door") end
	elseif selected == "Crusher" then
		local id = nearestCrusher(point)
		if id then toolEvent:FireServer("Crusher", id) else say("Click near a crushing wall") end
	elseif selected == "FalseRelic" or selected == "Ward" then
		toolEvent:FireServer(selected, point)
	elseif selected == "Haunt" then
		local _, userId = nearestSurvivor(point)
		if userId then toolEvent:FireServer("Haunt", userId) else say("Click a survivor you can see") end
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if not isMazeMaster() then return end
	if not processed then
		for _, tool in TOOLS do
			if input.KeyCode == tool.key then selected = tool.id end
		end
	end
	if processed then return end   -- (clicks on the panel's own buttons)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		use(UserInputService:GetMouseLocation())
	elseif input.UserInputType == Enum.UserInputType.Touch then
		use(Vector2.new(input.Position.X, input.Position.Y), true)
	end
end)

-- Outlines: one SelectionBox per door ghost or crusher marker, reused
local outlines = {}      -- [object] = SelectionBox
local markers = {}       -- [crusher id] = a flat part marking its cell
local markerFolder = nil

local function outline(adornee, color, thick)
	local box = outlines[adornee]
	if not box then
		box = Instance.new("SelectionBox")
		box.Adornee = adornee
		box.SurfaceTransparency = 1
		box.Parent = gui
		outlines[adornee] = box
	end
	box.Color3 = color
	box.LineThickness = thick and 0.35 or 0.15
	box.Visible = true
	return box
end

local function crusherMarker(id, center)
	if not markerFolder or not markerFolder.Parent then
		markerFolder = Instance.new("Folder")
		markerFolder.Name = "MazeMasterMarkers"
		markerFolder.Parent = workspace
		table.clear(markers)
	end
	local m = markers[id]
	if not m then
		m = Instance.new("Part")
		m.Anchored = true
		m.CanCollide, m.CanQuery, m.CanTouch = false, false, false
		m.Transparency = 1
		m.Size = Vector3.new(14, 0.2, 14)
		m.Parent = markerFolder
		markers[id] = m
	end
	m.CFrame = CFrame.new(center + Vector3.new(0, 0.15, 0))
	return m
end

-- FALSE RELIC PLACEMENT: the same rule the server uses (Objectives:CanPlaceFalseRelic): 2-3 ways
-- out of the cell, not in or next to a sanctuary, not next to another relic. Ways out are found
-- with short rays from the cell's middle, so a shut door counts as a wall, as on the server.
local GREEN, RED, AMBER = Color3.fromRGB(80, 230, 120), Color3.fromRGB(235, 60, 50), Color3.fromRGB(240, 180, 60)
local wallRays = RaycastParams.new()
wallRays.FilterType = Enum.RaycastFilterType.Include
local placeMarker = nil

local function cellAt(point, maze)
	local S, n = maze:GetAttribute("CellSize"), maze:GetAttribute("Cells")
	local half = n * S / 2
	local x, z = math.floor((point.X + half) / S) + 1, math.floor((point.Z + half) / S) + 1
	if x < 1 or z < 1 or x > n or z > n then return nil end
	return x, z, Vector3.new((x - 0.5) * S - half, maze:GetAttribute("FloorY"), (z - 0.5) * S - half), S
end

local function canPlaceAt(center, S, maze)
	wallRays.FilterDescendantsInstances = { maze }
	local eye = center + Vector3.new(0, 3, 0)
	local open = 0
	for _, d in { Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis } do
		if not workspace:Raycast(eye, d * (S / 2 + 1), wallRays) then open += 1 end
	end
	if open < 2 or open > 3 then return false end
	local function near(p, reach)
		return math.max(math.abs(p.X - center.X), math.abs(p.Z - center.Z)) <= reach
	end
	local sanctuaries = match:FindFirstChild("Sanctuaries")
	for _, info in sanctuaries and sanctuaries:GetChildren() or {} do
		if near(info:GetAttribute("Center"), 1.5 * S + 0.1) then return false end
	end
	local relics = match:FindFirstChild("Relics")
	for _, info in relics and relics:GetChildren() or {} do
		if not info:GetAttribute("Collected") and near(info:GetAttribute("Center"), S + 0.1) then return false end
	end
	return true
end

-- WARD PLACEMENT: the server's rule (WardEyes:CanPlace): not in a sanctuary, not on a relic's
-- (or false relic's) cell, not where a ward already is
local function canPlaceWardAt(center, S)
	local function same(p, reach)
		return math.max(math.abs(p.X - center.X), math.abs(p.Z - center.Z)) <= reach
	end
	local sanctuaries = match:FindFirstChild("Sanctuaries")
	for _, info in sanctuaries and sanctuaries:GetChildren() or {} do
		if same(info:GetAttribute("Center"), S) then return false end   -- (a sanctuary is 2x2 cells round its centre)
	end
	for _, name in { "Relics", "WardEyes" } do
		local folder = match:FindFirstChild(name)
		for _, info in folder and folder:GetChildren() or {} do
			if not info:GetAttribute("Collected") and same(info:GetAttribute("Center"), S / 2 - 0.1) then return false end
		end
	end
	return true
end

local function showPlacement(point)
	local maze = workspace:FindFirstChild("Maze")
	local x, z, center, S
	if maze and point then x, z, center, S = cellAt(point, maze) end
	if not x then
		if placeMarker then placeMarker.Transparency = 1 end
		return
	end
	if not placeMarker or not placeMarker.Parent then
		placeMarker = Instance.new("Part")
		placeMarker.Name = "FalseRelicPlacement"
		placeMarker.Anchored = true
		placeMarker.CanCollide, placeMarker.CanQuery, placeMarker.CanTouch = false, false, false
		placeMarker.Material = Enum.Material.Neon
		placeMarker.CastShadow = false
		placeMarker.Parent = workspace
	end
	local affordable = (not Config.DARK_MANA_ENABLED or (player:GetAttribute("DarkMana") or 0) >= Config.MAZE_MASTER_TOOLS[selected].cost)
		and (selected ~= "FalseRelic" or (player:GetAttribute("FalseRelicsLeft") or 0) > 0)
	local ok
	if selected == "Ward" then ok = canPlaceWardAt(center, S) else ok = canPlaceAt(center, S, maze) end
	placeMarker.Color = not ok and RED or (affordable and GREEN or AMBER)
	placeMarker.Size = Vector3.new(S - 3, 0.2, S - 3)
	placeMarker.CFrame = CFrame.new(center + Vector3.new(0, 0.2, 0))
	placeMarker.Transparency = 0.55
end

RunService.RenderStepped:Connect(function()
	local active = isMazeMaster()
	gui.Enabled = active
	for _, box in outlines do box.Visible = false end
	if placeMarker then placeMarker.Transparency = 1 end
	if not active then
		if markerFolder then markerFolder:Destroy() markerFolder = nil end
		return
	end
	local now = workspace:GetServerTimeNow()

	-- the bar (dark mana switched off: no bar, and nothing costs anything)
	local manaOn = Config.DARK_MANA_ENABLED
	barBack.Visible = manaOn
	local mana = manaOn and (player:GetAttribute("DarkMana") or 0) or math.huge
	barFill.Size = UDim2.fromScale(manaOn and math.clamp(mana / Config.DARK_MANA_MAX, 0, 1) or 1, 1)
	barText.Text = manaOn and ("Dark mana  %d / %d"):format(mana, Config.DARK_MANA_MAX) or ""
	if os.clock() > messageUntil then message.Text = "" end

	-- the buttons
	for id, b in buttons do
		local def = Config.MAZE_MASTER_TOOLS[id]
		local readyAt = player:GetAttribute("ToolReady" .. id) or 0
		local left = math.max(0, readyAt - now)
		local extra = ""
		if id == "FalseRelic" then extra = ("\n%d left"):format(player:GetAttribute("FalseRelicsLeft") or 0) end
		b.button.Text = ("[%d] %s%s%s%s"):format(table.find(TOOLS, b.tool), b.tool.name,
			manaOn and ("\n%d mana"):format(def.cost) or "", extra,
			left > 0 and ("  ·  %ds"):format(math.ceil(left)) or "")
		b.shade.Size = UDim2.fromScale(1, math.clamp(left / def.cooldown, 0, 1))
		b.stroke.Transparency = selected == id and 0 or 1
		b.button.TextTransparency = mana < def.cost and 0.45 or 0
	end

	-- outlines for the picked tool, the one nearest the mouse brighter
	local point = floorPoint(UserInputService:GetMouseLocation())
	if selected == "Door" then
		local hover = point and nearestDoor(point)
		for _, part in doorsList() do
			local ghost = FogState.doorGhosts[part]
			if ghost then
				local resting = (part:GetAttribute("RestUntil") or 0) > now
				local moving = part:GetAttribute("State") == "warning" or part:GetAttribute("State") == "moving"
				outline(ghost, (resting or moving) and GREY or (part == hover and PURPLE_BRIGHT or PURPLE), part == hover)
			end
		end
	elseif selected == "FalseRelic" or selected == "Ward" then
		showPlacement(point)
	elseif selected == "Haunt" then
		local hover = point and nearestSurvivor(point)
		local ready = (player:GetAttribute("ToolReadyHaunt") or 0) <= now and mana >= Config.MAZE_MASTER_TOOLS.Haunt.cost
		for character in visibleSurvivors() do
			outline(character, not ready and GREY or (character == hover and PURPLE_BRIGHT or PURPLE), character == hover)
		end
	elseif selected == "Crusher" then
		local hover = point and nearestCrusher(point)
		for id, c in crushersList() do
			local marker = crusherMarker(id, c.center)
			local busy = c.slab:GetAttribute("State") ~= "idle"
			outline(marker, busy and GREY or (id == hover and PURPLE_BRIGHT or PURPLE), id == hover)
		end
	end
end)
