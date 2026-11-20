-- FALSE RELICS, as the monster side sees them: the server tells monsters and the Maze Master (and
-- nobody else) which relics are false, and here each one's skull glows red, so they can tell them
-- from real ones at a glance. Survivors never get the list.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Net = require(ReplicatedStorage:WaitForChild("Net"))
local player = Players.LocalPlayer

local RED = Color3.fromRGB(255, 40, 30)

local falseIds = {}     -- [id] = true
local marked = {}       -- [relic model] = its Highlight

Net.event("FalseRelics").OnClientEvent:Connect(function(ids)
	table.clear(falseIds)
	for _, id in ids do falseIds[id] = true end
end)

local function monsterSide()
	local role = player:GetAttribute("Role")
	return role == Config.Roles.Monster or role == Config.Roles.MazeMaster
end

RunService.Heartbeat:Connect(function()
	local maze = workspace:FindFirstChild("Maze")
	local show = monsterSide()
	for id in falseIds do
		local model = maze and maze:FindFirstChild("Relic" .. id)
		if model and show and not marked[model] then
			local glow = Instance.new("Highlight")
			glow.FillColor = RED
			glow.OutlineColor = RED
			glow.FillTransparency = 0.35
			glow.OutlineTransparency = 0
			glow.DepthMode = Enum.HighlightDepthMode.Occluded
			glow.Adornee = model:FindFirstChild("Gem") or model
			glow.Parent = model
			local light = Instance.new("PointLight")
			light.Name = "FalseGlow"
			light.Color = RED
			light.Range = 14
			light.Brightness = 3
			light.Parent = glow.Adornee
			marked[model] = glow
		end
	end
	for model, glow in marked do
		if not model.Parent or not show then
			glow:Destroy()
			local light = model:FindFirstChild("FalseGlow", true)
			if light then light:Destroy() end
			marked[model] = nil
		end
	end
	if not maze then table.clear(falseIds) end
end)
