-- When the Maze Master HAUNTS you: a faint purple glow round the edges of the screen and a whisper,
-- for as long as it lasts ("HauntedUntil" on you, server time; Config.HAUNT_TIME). Subtle on
-- purpose: enough to notice and react (the monster side sees you, and what you see, meanwhile).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sounds = require(ReplicatedStorage:WaitForChild("Sounds"))
local player = Players.LocalPlayer

local PURPLE = Color3.fromRGB(150, 60, 220)
local BORDER = 90        -- pixels the glow reaches in from each edge
local STRENGTH = 0.55    -- how solid the glow is at the very edge (0..1)
local FADE = 0.4         -- seconds to fade in and out

local gui = Instance.new("ScreenGui")
gui.Name = "HauntAlert"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 4
gui.Parent = player:WaitForChild("PlayerGui")

local edges = {}
local function edge(anchor, position, size, rotation)
	local f = Instance.new("Frame")
	f.AnchorPoint, f.Position, f.Size = anchor, position, size
	f.BackgroundColor3 = PURPLE
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

local whisper = Instance.new("Sound")
whisper.Name = "HauntWhisper"
whisper.SoundId = "rbxassetid://" .. Sounds.HauntWhisper.id
whisper.Volume = Sounds.HauntWhisper.volume
whisper.Parent = SoundService

local level = 0
local wasHaunted = false
RunService.RenderStepped:Connect(function(dt)
	local haunted = (player:GetAttribute("HauntedUntil") or 0) > workspace:GetServerTimeNow()
	if haunted and not wasHaunted then whisper:Play() end
	wasHaunted = haunted
	local want = haunted and 1 or 0
	level = want > level and math.min(want, level + dt / FADE) or math.max(want, level - dt / FADE)
	-- a slow throb while it lasts
	local throb = 0.85 + 0.15 * math.sin(os.clock() * 6)
	for _, f in edges do f.BackgroundTransparency = 1 - STRENGTH * level * throb end
end)
