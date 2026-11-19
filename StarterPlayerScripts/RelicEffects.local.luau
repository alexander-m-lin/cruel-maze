-- The relic-collecting effect: whoever is collecting a relic reaches out a hand toward it, and a
-- beam of light runs from their hand to the relic. Also the prompt to collect one (at the end).
-- Runs on every player's computer, for every collector, so everyone sees it (the server says who
-- is collecting each relic in its "Collector" attribute; see Objectives). Everything made here
-- exists only on this computer.
--
-- The reaching arm uses an IKControl ("inverse kinematics"): Roblox bends the shoulder, elbow and
-- wrist so the hand points at the target, on top of whatever animation is playing.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local match = ReplicatedStorage:WaitForChild("Match")

local BEAM_COLOR = Color3.fromRGB(255, 214, 120)
local REACH_SPEED = 0.12      -- seconds the arm takes to swing up to the relic

local effects = {}   -- [relic info] = { character, ik, beam, light, parts... }

local function clear(info)
	local e = effects[info]
	if not e then return end
	for _, thing in e.cleanup do thing:Destroy() end
	effects[info] = nil
end

local function make(info, character, gem)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if not (humanoid and hand) then return nil end
	local cleanup = {}

	-- the arm: reach the hand toward the gem (R15 avatars; R6 arms can't bend, so they just glow)
	local upperArm = character:FindFirstChild("RightUpperArm")
	if upperArm then
		local ik = Instance.new("IKControl")
		ik.Name = "ReachForRelic"
		ik.Type = Enum.IKControlType.Position
		ik.ChainRoot = upperArm
		ik.EndEffector = hand
		ik.Target = gem
		ik.SmoothTime = REACH_SPEED
		ik.Weight = 1
		ik.Parent = humanoid
		table.insert(cleanup, ik)
	end

	-- the beam: from the palm to the gem
	local from = Instance.new("Attachment")
	from.Name = "RelicBeamStart"
	from.Position = Vector3.new(0, -hand.Size.Y / 2, 0)
	from.Parent = hand
	local to = Instance.new("Attachment")
	to.Name = "RelicBeamEnd"
	to.Parent = gem
	local beam = Instance.new("Beam")
	beam.Attachment0, beam.Attachment1 = from, to
	beam.Color = ColorSequence.new(BEAM_COLOR)
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Width0, beam.Width1 = 0.25, 0.7
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(0.5, 0.1), NumberSequenceKeypoint.new(1, 0.25) })
	beam.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	beam.TextureMode = Enum.TextureMode.Wrap
	beam.TextureLength = 1.5
	beam.TextureSpeed = 2.5
	beam.Segments = 12
	beam.Parent = gem
	local light = Instance.new("PointLight")
	light.Color = BEAM_COLOR
	light.Range = 8
	light.Brightness = 2
	light.Parent = hand
	for _, thing in { from, to, beam, light } do table.insert(cleanup, thing) end

	return { character = character, gem = gem, cleanup = cleanup }
end

RunService.Heartbeat:Connect(function()
	local relics = match:FindFirstChild("Relics")
	local maze = workspace:FindFirstChild("Maze")
	local wanted = {}
	if relics and maze then
		for _, info in relics:GetChildren() do
			local userId = info:GetAttribute("Collector")
			local collector = userId and Players:GetPlayerByUserId(userId)
			local character = collector and collector.Character
			local relicModel = maze:FindFirstChild("Relic" .. tostring(info:GetAttribute("Id")))
			local gem = relicModel and relicModel:FindFirstChild("Gem")
			if character and gem and not info:GetAttribute("Collected") then
				wanted[info] = true
				local e = effects[info]
				if e and (e.character ~= character or e.gem ~= gem) then
					clear(info)
					e = nil
				end
				if not e then effects[info] = make(info, character, gem) end
			end
		end
	end
	for info in effects do
		if not wanted[info] then clear(info) end
	end
end)

---------------------------------------------------------------- the collect prompt
-- Standing on a relic nobody is collecting shows a prompt above it: a mouse with its left button
-- lit. Left-click (or tap the prompt) to start collecting; the server checks you're really on it (Objectives).
local UserInputService = game:GetService("UserInputService")
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Net = require(ReplicatedStorage:WaitForChild("Net"))
local collectEvent = Net.event("CollectRelic")
local player = Players.LocalPlayer

-- The prompt is a little picture of a mouse with its left button lit up (built from UI shapes, no
-- image needed). On touch screens, where there's no mouse, it says "Tap" instead. Either way the
-- whole thing is a button you can tap.
local ICON_W, ICON_H = 30, 44           -- the mouse's size on screen (pixels)
local BODY_COLOR = Color3.fromRGB(28, 28, 38)
local EDGE_COLOR = Color3.fromRGB(230, 230, 225)

local prompt = Instance.new("BillboardGui")
prompt.Name = "RelicPrompt"
prompt.Size = UDim2.fromOffset(ICON_W + 8, ICON_H + 8)
prompt.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
prompt.AlwaysOnTop = true
prompt.Active = true                 -- so the button can be tapped
prompt.Enabled = false
prompt.ResetOnSpawn = false

local button = Instance.new("TextButton")
button.Size = UDim2.fromScale(1, 1)
button.BackgroundTransparency = 1
button.Text = ""
button.Parent = prompt

local function shape(parent, pos, size, color, corner)
	local f = Instance.new("Frame")
	f.Position, f.Size = pos, size
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	if corner then Instance.new("UICorner", f).CornerRadius = UDim.new(0, corner) end
	f.Parent = parent
	return f
end

-- the mouse: a rounded body (its outline is added last, on top of everything)
local mouse = shape(button, UDim2.fromOffset(4, 4), UDim2.fromOffset(ICON_W, ICON_H), BODY_COLOR, 13)
-- the left button, lit up: a gold copy of the whole body's rounded shape, cut down to its top-left
-- quarter (a clipping box shows only that part), so its curve matches the body's exactly
local BUTTON_H = math.floor(ICON_H * 0.42)
local quarter = Instance.new("Frame")
quarter.Size = UDim2.fromOffset(ICON_W / 2, BUTTON_H)
quarter.BackgroundTransparency = 1
quarter.ClipsDescendants = true
quarter.Parent = mouse
local lit = { shape(quarter, UDim2.fromOffset(0, 0), UDim2.fromOffset(ICON_W, ICON_H), BEAM_COLOR, 13) }
-- the seams: down the middle between the buttons, and across under them
shape(mouse, UDim2.fromOffset(ICON_W / 2 - 1, 0), UDim2.fromOffset(2, BUTTON_H), EDGE_COLOR)
shape(mouse, UDim2.fromOffset(0, BUTTON_H - 1), UDim2.fromOffset(ICON_W, 2), EDGE_COLOR)
-- the outline: a see-through copy of the body's shape drawn above the lit button, so the button
-- never covers the edge
local outline = shape(mouse, UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), BODY_COLOR, 13)
outline.BackgroundTransparency = 1
outline.ZIndex = 2
local edge = Instance.new("UIStroke")
edge.Color = EDGE_COLOR
edge.Thickness = 2
edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
edge.Parent = outline

local tapLabel = Instance.new("TextLabel")   -- shown instead of the mouse on touch screens
tapLabel.Size = UDim2.fromScale(1, 1)
tapLabel.BackgroundColor3 = BODY_COLOR
tapLabel.BackgroundTransparency = 0.15
tapLabel.TextColor3 = BEAM_COLOR
tapLabel.Font = Enum.Font.GothamBold
tapLabel.TextSize = 15
tapLabel.Text = "Tap"
tapLabel.Visible = false
tapLabel.Parent = button
Instance.new("UICorner", tapLabel).CornerRadius = UDim.new(0.5, 0)

prompt.Parent = player:WaitForChild("PlayerGui")

-- The relic you could start collecting right now, if any: you're a survivor in a match, standing
-- in its cell, and nobody is collecting it yet
local function relicInReach()
	if match:GetAttribute("State") ~= Config.States.Playing then return nil end
	if player:GetAttribute("Role") ~= Config.Roles.Survivor or player:GetAttribute("Seized") then return nil end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local maze = workspace:FindFirstChild("Maze")
	local relics = match:FindFirstChild("Relics")
	if not (root and humanoid and humanoid.Health > 0 and maze and relics) then return nil end
	local size = maze:GetAttribute("CellSize")
	local half = maze:GetAttribute("Cells") * size / 2
	local function cell(p) return math.floor((p.X + half) / size), math.floor((p.Z + half) / size) end
	local mx, mz = cell(root.Position)
	for _, info in relics:GetChildren() do
		if info:GetAttribute("Collected") or info:GetAttribute("CollectSince") then continue end
		local rx, rz = cell(info:GetAttribute("Center"))
		if rx == mx and rz == mz then
			local relicModel = maze:FindFirstChild("Relic" .. tostring(info:GetAttribute("Id")))
			local gem = relicModel and relicModel:FindFirstChild("Gem")
			if gem then return info, gem end
		end
	end
	return nil
end

local function tryCollect()
	local info = relicInReach()
	if info then collectEvent:FireServer(info:GetAttribute("Id")) end
end

RunService.Heartbeat:Connect(function()
	local _, gem = relicInReach()
	prompt.Enabled = gem ~= nil
	if gem then
		prompt.Adornee = gem
		local touchOnly = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
		mouse.Visible = not touchOnly
		tapLabel.Visible = touchOnly
		-- the lit button gently pulses, to catch the eye
		-- (brightness, not see-through: the button is built from overlapping pieces)
		local glow = BEAM_COLOR:Lerp(Color3.fromRGB(150, 110, 40), 0.5 + 0.5 * math.sin(os.clock() * 5))
		for _, f in lit do f.BackgroundColor3 = glow end
	end
end)

button.Activated:Connect(tryCollect)
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.UserInputType == Enum.UserInputType.MouseButton1 then tryCollect() end
end)
