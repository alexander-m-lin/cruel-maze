-- Fear Eater's INSTILL FEAR, on the survivor's screen:
--   DREAD  ("DreadUntil" on you, server time): a dark edge closing in and a countdown -
--          "Reach a sanctuary or a teammate" - with a whisper as it starts.
--   FEARED ("FearedUntil"): you didn't make it. A pulsing dark red edge and "FEARED" while it
--          lasts (the monster side sees you, and you're slowed).
--   Made it in time: "Safe" for a moment.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sounds = require(ReplicatedStorage:WaitForChild("Sounds"))
local player = Players.LocalPlayer

local DREAD_COLOR = Color3.fromRGB(20, 10, 30)
local FEAR_COLOR = Color3.fromRGB(120, 10, 20)
local BORDER = 140       -- pixels the edge reaches in
local FADE = 0.3

local gui = Instance.new("ScreenGui")
gui.Name = "FearAlert"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 5
gui.Parent = player:WaitForChild("PlayerGui")

local edges = {}
local function edge(anchor, position, size, rotation)
	local f = Instance.new("Frame")
	f.AnchorPoint, f.Position, f.Size = anchor, position, size
	f.BackgroundColor3 = DREAD_COLOR
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	local g = Instance.new("UIGradient")
	g.Rotation = rotation
	g.Transparency = NumberSequence.new(0, 1)
	g.Parent = f
	f.Parent = gui
	table.insert(edges, f)
end
edge(Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.new(1, 0, 0, BORDER), 90)
edge(Vector2.new(0, 1), UDim2.fromScale(0, 1), UDim2.new(1, 0, 0, BORDER), -90)
edge(Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.new(0, BORDER, 1, 0), 0)
edge(Vector2.new(1, 0), UDim2.fromScale(1, 0), UDim2.new(0, BORDER, 1, 0), 180)

local label = Instance.new("TextLabel")
label.AnchorPoint = Vector2.new(0.5, 0)
label.Position = UDim2.new(0.5, 0, 0, 230)
label.Size = UDim2.fromOffset(520, 60)
label.BackgroundTransparency = 1
label.Font = Enum.Font.GothamBlack
label.TextSize = 26
label.TextColor3 = Color3.fromRGB(235, 225, 255)
label.TextStrokeTransparency = 0.3
label.TextWrapped = true
label.Text = ""
label.Parent = gui

local whisper = Instance.new("Sound")
whisper.Name = "DreadWhisper"
whisper.SoundId = "rbxassetid://" .. Sounds.HauntWhisper.id
whisper.Volume = Sounds.HauntWhisper.volume
whisper.PlaybackSpeed = 0.8      -- lower than a haunt's
whisper.Parent = SoundService

local level = 0
local was = nil                  -- "dread" / "feared" / nil
local safeUntil = 0
RunService.RenderStepped:Connect(function(dt)
	local now = workspace:GetServerTimeNow()
	local dreadLeft = (player:GetAttribute("DreadUntil") or 0) - now
	local fearLeft = (player:GetAttribute("FearedUntil") or 0) - now
	local state = (dreadLeft > 0 and "dread") or (fearLeft > 0 and "feared") or nil
	if state == "dread" and was ~= "dread" then whisper:Play() end
	if was == "dread" and state == nil then safeUntil = os.clock() + 1.5 end   -- made it
	was = state

	local want = state and 1 or 0
	level = want > level and math.min(want, level + dt / FADE) or math.max(want, level - dt / FADE)
	local color = state == "feared" and FEAR_COLOR or DREAD_COLOR
	local strength = state == "feared" and (0.6 + 0.2 * math.sin(os.clock() * 8)) or 0.75
	for _, f in edges do
		f.BackgroundColor3 = color
		f.BackgroundTransparency = 1 - strength * level
	end
	if state == "dread" then
		label.Text = ("DREAD  %.1f\nReach a sanctuary or a teammate"):format(dreadLeft)
		label.TextColor3 = Color3.fromRGB(235, 225, 255)
	elseif state == "feared" then
		label.Text = "FEARED\nThe monsters can see you"
		label.TextColor3 = Color3.fromRGB(255, 120, 120)
	elseif os.clock() < safeUntil then
		label.Text = "Safe"
		label.TextColor3 = Color3.fromRGB(170, 240, 190)
	else
		label.Text = ""
	end
end)
