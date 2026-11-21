-- Your HERO'S ABILITIES: the controls and the ability bar (survivors and monsters with a hero,
-- during a match).
--   right mouse button - Primary     Q - Secondary     E - Ultimate
-- (on a touch screen or gamepad: the buttons on the bar, or the gamepad's shoulder buttons)
-- Each ability aims the way you face. The server checks and carries it out (Abilities); the bar
-- shows each one's key, name and cooldown (the "AbilityReady<Slot>" attributes it publishes).
--
-- HOLD TO AIM: if the hero's HeroVisuals module has an `aim[slot]` (e.g. Fear Eater's Devour), the
-- key shows a preview while held (aim.update(player, def), every frame) and the ability goes off
-- when it's let go (aim.hide() then). Others go off as the key goes down. (The on-screen buttons
-- always go off at once.)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Net = require(ReplicatedStorage:WaitForChild("Net"))
local Heroes = require(ReplicatedStorage:WaitForChild("Heroes"))

local player = Players.LocalPlayer
local match = ReplicatedStorage:WaitForChild("Match")
local useEvent = Net.event("UseAbility")
local resultEvent = Net.event("AbilityResult")

local INPUTS = {
	Primary = { Enum.UserInputType.MouseButton2, Enum.KeyCode.ButtonR1 },
	Secondary = { Enum.KeyCode.Q, Enum.KeyCode.ButtonL1 },
	Ultimate = { Enum.KeyCode.E, Enum.KeyCode.ButtonY },
}
local GOLD = Color3.fromRGB(235, 190, 90)

local function myHero()
	local role = player:GetAttribute("Role")
	if role ~= Config.Roles.Survivor and role ~= Config.Roles.Monster then return nil end
	if match:GetAttribute("State") ~= Config.States.Playing then return nil end
	return Heroes.get(player:GetAttribute("Hero"))
end

local heroVisuals = script.Parent:WaitForChild("HeroVisuals")

-- The hero's hold-to-aim preview for this slot, if it has one
local function aimerFor(hero, slot)
	local module = hero and heroVisuals:FindFirstChild(hero.id)
	local visuals = module and require(module)
	return visuals and visuals.aim and visuals.aim[slot] or nil
end

local function use(slot)
	local hero = myHero()
	if not (hero and hero.abilities[slot]) or hero.abilities[slot].soon then return end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	useEvent:FireServer(slot, root.CFrame.LookVector)
end

---------------------------------------------------------------- the bar
local gui = Instance.new("ScreenGui")
gui.Name = "AbilityBar"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local bar = Instance.new("Frame")
bar.AnchorPoint = Vector2.new(0.5, 1)
bar.Position = UDim2.new(0.5, 0, 1, -16)
bar.Size = UDim2.fromOffset(3 * 104 + 2 * 8, 84)
bar.BackgroundTransparency = 1
bar.Parent = gui
local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Padding = UDim.new(0, 8)
layout.Parent = bar

local message = Instance.new("TextLabel")
message.AnchorPoint = Vector2.new(0.5, 1)
message.Position = UDim2.new(0.5, 0, 0, -6)
message.Size = UDim2.fromOffset(400, 20)
message.BackgroundTransparency = 1
message.Font = Enum.Font.GothamMedium
message.TextSize = 14
message.TextColor3 = Color3.fromRGB(240, 230, 210)
message.TextStrokeTransparency = 0.4
message.Text = ""
message.Parent = bar
local messageUntil = 0
resultEvent.OnClientEvent:Connect(function(_, text)
	message.Text = text
	messageUntil = os.clock() + 2
end)

local buttons = {}
for _, slot in Heroes.SLOTS do
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(104, 84)
	b.BackgroundColor3 = Color3.fromRGB(36, 30, 24)
	b.BackgroundTransparency = 0.1
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.Font = Enum.Font.GothamBold
	b.TextSize = 14
	b.TextColor3 = Color3.new(1, 1, 1)
	b.TextWrapped = true
	b.Parent = bar
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = GOLD
	stroke.Thickness = slot == "Ultimate" and 2 or 1
	stroke.Parent = b
	local shade = Instance.new("Frame")            -- drains as it recharges
	shade.AnchorPoint = Vector2.new(0, 1)
	shade.Position = UDim2.fromScale(0, 1)
	shade.Size = UDim2.fromScale(1, 0)
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 0.45
	shade.BorderSizePixel = 0
	shade.ZIndex = 2
	shade.Parent = b
	Instance.new("UICorner", shade).CornerRadius = UDim.new(0, 8)
	b.Activated:Connect(function() use(slot) end)
	buttons[slot] = { button = b, shade = shade }
end

RunService.RenderStepped:Connect(function()
	local hero = myHero()
	gui.Enabled = hero ~= nil
	if not hero then return end
	if os.clock() > messageUntil then message.Text = "" end
	local now = workspace:GetServerTimeNow()
	for slot, b in buttons do
		local def = hero.abilities[slot]
		b.button.Visible = def ~= nil
		if not def then continue end
		if def.soon then                           -- not built yet
			b.button.Text = ("[%s]\n%s\n(soon)"):format(Heroes.KEYS[slot], def.name)
			b.shade.Size = UDim2.fromScale(1, 1)
			continue
		end
		local left = math.max(0, (player:GetAttribute("AbilityReady" .. slot) or 0) - now)
		b.button.Text = ("[%s]\n%s%s"):format(Heroes.KEYS[slot], def.name, left > 0 and ("\n%ds"):format(math.ceil(left)) or "")
		b.shade.Size = UDim2.fromScale(1, math.clamp(left / def.cooldown, 0, 1))
	end
end)

---------------------------------------------------------------- the keys
local aiming = {}   -- [slot] = the aimer while its key is held
for slot, inputs in INPUTS do
	ContextActionService:BindAction("Ability" .. slot, function(_, state)
		if state == Enum.UserInputState.Begin then
			local hero = myHero()
			if not hero then return Enum.ContextActionResult.Pass end
			local def = hero.abilities[slot]
			local aimer = def and aimerFor(hero, slot)
			if aimer then
				aiming[slot] = { aimer = aimer, def = def }
			else
				use(slot)
			end
			return Enum.ContextActionResult.Sink
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			local held = aiming[slot]
			if not held then return Enum.ContextActionResult.Pass end
			aiming[slot] = nil
			held.aimer.hide()
			if state == Enum.UserInputState.End and myHero() then use(slot) end
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, table.unpack(inputs))
end

-- previews follow you while their keys are held (and go away if the match ends meanwhile)
RunService.RenderStepped:Connect(function()
	for slot, held in aiming do
		if myHero() then
			held.aimer.update(player, held.def)
		else
			held.aimer.hide()
			aiming[slot] = nil
		end
	end
end)
