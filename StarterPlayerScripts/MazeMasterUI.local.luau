-- The MAZE MASTER's interface (only while you're the Maze Master). The camera pans over the maze
-- (IsometricCamera); this script adds:
--
--   TARGETS in the world, always outlined: every door and every crushing wall. Purple = ready to
--   use, grey = not yet (recharging, or the door/wall is busy). Click one to use it on that: a door
--   opens or shuts, a crushing wall slams.
--   Hovering one brightens it and shows, by the mouse, the ability's name in a box when it's ready,
--   or a clock filling up (with the seconds left) while it recharges.
--   Two PLACEMENT buttons along the bottom (or keys 1-2): Ward and False relic. Pick one, then click
--   a cell: it lights up green where one can go, red where it can't (amber: it could, but none
--   are left / no mana). Right-click, Esc or the button again cancels. Placing ends placement.
--   A DARK MANA bar (only while Config.DARK_MANA_ENABLED).
--
-- Clicks and taps both work (a tap picks the target nearest it). The server checks everything
-- (MazeMaster) and answers with a short message, shown above the buttons.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
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

-- the abilities used by clicking a target, and their names on the hover box
local TARGET_TOOLS = { Door = "Door", Crusher = "Crushing wall" }
-- the placement abilities, which have buttons
local TOOLS = {
	{ id = "Ward", name = "Ward", key = Enum.KeyCode.One },
	{ id = "FalseRelic", name = "False relic", key = Enum.KeyCode.Two },
}
local placing = nil          -- "Ward" / "FalseRelic" while placing one, else nil (clicks use targets)

---------------------------------------------------------------- the panel
local gui = Instance.new("ScreenGui")
gui.Name = "MazeMasterUI"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.Position = UDim2.new(0.5, 0, 1, -16)
panel.Size = UDim2.fromOffset(300, 104)
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
	b.Activated:Connect(function() placing = placing ~= tool.id and tool.id or nil end)
	buttons[tool.id] = { button = b, stroke = stroke, shade = shade, tool = tool }
end

-- THE HOVER TIP: by the mouse, over a target. Ready: the ability's name in a box. Recharging: a
-- clock that fills clockwise from 12 as it recharges, with the seconds left in the middle.
gui.IgnoreGuiInset = true          -- (so it lines up with GetMouseLocation)
local tip = Instance.new("Frame")
tip.BackgroundTransparency = 1
tip.Size = UDim2.fromOffset(1, 1)
tip.Visible = false
tip.Parent = gui

local nameBox = Instance.new("TextLabel")
nameBox.AutomaticSize = Enum.AutomaticSize.XY
nameBox.Size = UDim2.fromOffset(0, 0)
nameBox.BackgroundColor3 = Color3.fromRGB(22, 16, 30)
nameBox.BackgroundTransparency = 0.1
nameBox.BorderSizePixel = 0
nameBox.Font = Enum.Font.GothamBold
nameBox.TextSize = 15
nameBox.TextColor3 = Color3.new(1, 1, 1)
nameBox.Parent = tip
do
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 10), UDim.new(0, 10)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 6), UDim.new(0, 6)
	pad.Parent = nameBox
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = PURPLE_BRIGHT
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = nameBox
end

local CLOCK_SIZE = 46
local clock = Instance.new("Frame")
clock.Size = UDim2.fromOffset(CLOCK_SIZE, CLOCK_SIZE)
clock.BackgroundColor3 = Color3.fromRGB(22, 16, 30)
clock.BackgroundTransparency = 0.15
clock.BorderSizePixel = 0
clock.Parent = tip
Instance.new("UICorner", clock).CornerRadius = UDim.new(0.5, 0)
do
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = GREY
	stroke.Parent = clock
end
-- The fill: each half of the clock is a clipped half of a purple disc whose gradient is opaque on
-- one side of a line through the middle; turning the gradient sweeps that line round.
local clockHalves = {}
for _, side in { "right", "left" } do
	local clip = Instance.new("Frame")
	clip.BackgroundTransparency = 1
	clip.ClipsDescendants = true
	clip.Size = UDim2.new(0.5, 0, 1, 0)
	clip.Position = side == "right" and UDim2.fromScale(0.5, 0) or UDim2.fromScale(0, 0)
	clip.Parent = clock
	local disc = Instance.new("Frame")
	disc.Size = UDim2.fromOffset(CLOCK_SIZE, CLOCK_SIZE)
	disc.Position = side == "right" and UDim2.fromOffset(-CLOCK_SIZE / 2, 0) or UDim2.fromOffset(0, 0)
	disc.BackgroundColor3 = PURPLE
	disc.BorderSizePixel = 0
	disc.Parent = clip
	Instance.new("UICorner", disc).CornerRadius = UDim.new(0.5, 0)
	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(0.501, 1), NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = disc
	clockHalves[side] = gradient
end
local clockText = Instance.new("TextLabel")
clockText.Size = UDim2.fromScale(1, 1)
clockText.BackgroundTransparency = 1
clockText.Font = Enum.Font.GothamBold
clockText.TextSize = 16
clockText.TextColor3 = Color3.new(1, 1, 1)
clockText.TextStrokeTransparency = 0.3
clockText.ZIndex = 3
clockText.Parent = clock

-- filled: 0..1 of the way round, clockwise from 12 o'clock
local function setClock(filled)
	local angle = math.clamp(filled, 0, 1) * 360
	clockHalves.right.Rotation = math.clamp(angle, 0, 180)
	clockHalves.left.Rotation = math.clamp(angle, 180, 360)
end

local function showTip(screen, name, left, total)
	tip.Visible = true
	tip.Position = UDim2.fromOffset(screen.X + 18, screen.Y + 14)
	if left <= 0 then
		nameBox.Visible, clock.Visible = true, false
		nameBox.Text = name
	else
		nameBox.Visible, clock.Visible = false, true
		setClock(total > 0 and 1 - left / total or 1)
		clockText.Text = tostring(math.ceil(left))
	end
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
				sums[id] = sums[id] or { p = Vector3.zero, n = 0, slab = c, slabs = {} }
				sums[id].p += home.Position
				sums[id].n += 1
				table.insert(sums[id].slabs, c)
			end
		end
		local floorY = maze:GetAttribute("FloorY") or 0
		for id, sum in sums do
			local p = sum.p / sum.n
			list[id] = { center = Vector3.new(p.X, floorY, p.Z), slab = sum.slab, slabs = sum.slabs }
		end
	end
	return list
end

-- Outlines: one SelectionBox per door ghost or crushing-wall slab, reused
local outlines = {}      -- [object] = SelectionBox

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

-- FALSE RELIC PLACEMENT: the same rule the server uses (Objectives:CanPlaceFalseRelic): 2-3 ways
-- out of the cell, not in or next to a sanctuary, not next to another relic. Ways out are found
-- with short rays from the cell's middle, so a shut door counts as a wall, as on the server.
local GREEN, RED, AMBER = Color3.fromRGB(80, 230, 120), Color3.fromRGB(235, 60, 50), Color3.fromRGB(240, 180, 60)
local wallRays = RaycastParams.new()
wallRays.FilterType = Enum.RaycastFilterType.Include
local placeMarker = nil

-- Is this point in a sanctuary (or within `margin` studs of one)? From its corners (Min, Max).
local function inSanctuary(p, margin)
	local folder = match:FindFirstChild("Sanctuaries")
	for _, info in folder and folder:GetChildren() or {} do
		local lo, hi = info:GetAttribute("Min"), info:GetAttribute("Max")
		if lo and hi and p.X > lo.X - margin and p.X < hi.X + margin and p.Z > lo.Z - margin and p.Z < hi.Z + margin then
			return true
		end
	end
	return false
end

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
	if inSanctuary(center, S + 0.1) then return false end      -- in or next to one
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
	if inSanctuary(center, 0) then return false end
	for _, name in { "Relics", "WardEyes" } do
		local folder = match:FindFirstChild(name)
		for _, info in folder and folder:GetChildren() or {} do
			if not info:GetAttribute("Collected") and same(info:GetAttribute("Center"), S / 2 - 0.1) then return false end
		end
	end
	return true
end

-- -> whether a placement there would be allowed (and the marker is drawn)
local function showPlacement(point)
	local maze = workspace:FindFirstChild("Maze")
	local x, z, center, S
	if maze and point then x, z, center, S = cellAt(point, maze) end
	if not x then
		if placeMarker then placeMarker.Transparency = 1 end
		return false
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
	local affordable = (not Config.DARK_MANA_ENABLED or (player:GetAttribute("DarkMana") or 0) >= Config.MAZE_MASTER_TOOLS[placing].cost)
		and (placing ~= "FalseRelic" or (player:GetAttribute("FalseRelicsLeft") or 0) > 0)
	local ok
	if placing == "Ward" then ok = canPlaceWardAt(center, S) else ok = canPlaceAt(center, S, maze) end
	placeMarker.Color = not ok and RED or (affordable and GREEN or AMBER)
	placeMarker.Size = Vector3.new(S - 3, 0.2, S - 3)
	placeMarker.CFrame = CFrame.new(center + Vector3.new(0, 0.2, 0))
	placeMarker.Transparency = 0.55
	return ok and affordable
end

---------------------------------------------------------------- targets
-- Everything you can click to use an ability on, with whether it's ready:
-- { tool, adornees (to outline), at (floor point), use = args for the server, left, total, busy, name }
local function targetsNow(now)
	local list = {}
	local function toolLeft(id)
		return math.max(0, (player:GetAttribute("ToolReady" .. id) or 0) - now), Config.MAZE_MASTER_TOOLS[id].cooldown
	end
	-- doors: the tool's cooldown, and each door's own rest after being changed
	local doorLeft, doorTotal = toolLeft("Door")
	for _, part in doorsList() do
		local ghost = FogState.doorGhosts[part]
		if not ghost then continue end
		local left, total = doorLeft, doorTotal
		local rest = math.max(0, (part:GetAttribute("RestUntil") or 0) - now)
		if rest > left then left, total = rest, Config.MAZE_MASTER_DOOR_COOLDOWN end
		local state = part:GetAttribute("State")
		table.insert(list, { tool = "Door", adornees = { ghost }, at = (part:GetAttribute("ClosedCFrame") or part.CFrame).Position,
			use = { "Door", part:GetAttribute("Id") }, left = left, total = total,
			busy = state == "warning" or state == "moving",
			name = part:GetAttribute("Open") and "Shut door" or "Open door" })
	end
	-- crushing walls: the tool's cooldown, and each wall's own rest after being set off
	local crushLeft, crushTotal = toolLeft("Crusher")
	for id, c in crushersList() do
		local left, total = crushLeft, crushTotal
		local rest = math.max(0, (c.slab:GetAttribute("RestUntil") or 0) - now)
		if rest > left then left, total = rest, Config.MAZE_MASTER_CRUSHER_COOLDOWN end
		table.insert(list, { tool = "Crusher", adornees = c.slabs, at = c.center,
			use = { "Crusher", id }, left = left, total = total,
			busy = c.slab:GetAttribute("State") ~= "idle", name = TARGET_TOOLS.Crusher })
	end
	return list
end

-- the target nearest a floor point (within PICK_RANGE)
local function targetAt(list, point)
	local best, bestDist
	for _, t in list do
		local d = (Vector3.new(t.at.X, 0, t.at.Z) - Vector3.new(point.X, 0, point.Z)).Magnitude
		if d < PICK_RANGE and (not bestDist or d < bestDist) then best, bestDist = t, d end
	end
	return best
end

local function use(screen, guiInset)
	local point = floorPoint(screen, guiInset)
	if not point then return end
	if placing then
		if showPlacement(point) then
			toolEvent:FireServer(placing, point)
			placing = nil
		else
			say(placing == "Ward" and "A ward can't go there" or "A false relic can't go there")
		end
		return
	end
	local target = targetAt(targetsNow(workspace:GetServerTimeNow()), point)
	if target then toolEvent:FireServer(table.unpack(target.use)) end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if not isMazeMaster() then return end
	if not processed then
		for _, tool in TOOLS do
			if input.KeyCode == tool.key then placing = placing ~= tool.id and tool.id or nil end
		end
		if input.KeyCode == Enum.KeyCode.Escape or input.UserInputType == Enum.UserInputType.MouseButton2 then placing = nil end
	end
	if processed then return end   -- (clicks on the panel's own buttons)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		use(UserInputService:GetMouseLocation())
	elseif input.UserInputType == Enum.UserInputType.Touch then
		use(Vector2.new(input.Position.X, input.Position.Y), true)
	end
end)

RunService.RenderStepped:Connect(function()
	local active = isMazeMaster()
	gui.Enabled = active
	for adornee, box in outlines do
		box.Visible = false
		if not adornee.Parent then box:Destroy() outlines[adornee] = nil end   -- gone (an old match, a body)
	end
	if placeMarker then placeMarker.Transparency = 1 end
	if not active then return end
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
		b.shade.Size = UDim2.fromScale(1, def.cooldown > 0 and math.clamp(left / def.cooldown, 0, 1) or 0)
		b.stroke.Transparency = placing == id and 0 or 1
		b.button.TextTransparency = mana < def.cost and 0.45 or 0
	end

	-- placing a ward or false relic: just the cell under the mouse
	local mouse = UserInputService:GetMouseLocation()
	local point = floorPoint(mouse)
	tip.Visible = false
	if placing then
		showPlacement(point)
		return
	end
	-- otherwise every target outlined (purple = ready, grey = not), the one under the mouse brighter
	local list = targetsNow(now)
	local hover = point and targetAt(list, point)
	for _, t in list do
		local ready = t.left <= 0 and not t.busy and mana >= Config.MAZE_MASTER_TOOLS[t.tool].cost
		for _, adornee in t.adornees do
			outline(adornee, not ready and GREY or (t == hover and PURPLE_BRIGHT or PURPLE), t == hover)
		end
	end
	if hover then
		showTip(mouse, hover.name, hover.left, hover.total)
		nameBox.TextTransparency = hover.busy and 0.45 or 0
	end
end)
