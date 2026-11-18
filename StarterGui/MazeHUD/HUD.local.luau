-- The on-screen HUD: the match countdown, your run timer, and messages from the server.
-- Follows the match through the attributes on ReplicatedStorage.Match (see ServerStorage.Match).
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = game:GetService("Players").LocalPlayer

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Net = require(ReplicatedStorage:WaitForChild("Net"))
local States = Config.States

local gui = script.Parent
local timerLabel = gui:WaitForChild("TimerLabel")
local announceLabel = gui:WaitForChild("AnnounceLabel")
local match = ReplicatedStorage:WaitForChild("Match")

local flashText, flashUntil = nil, 0   -- a short local message (e.g. "You were caught!")

Net.event("Caught").OnClientEvent:Connect(function()
	flashText, flashUntil = "You were caught! Back to the start.", os.clock() + 2.5
end)

RunService.RenderStepped:Connect(function()
	local state = match:GetAttribute("State")
	local endsAt = match:GetAttribute("EndsAt")
	local now = workspace:GetServerTimeNow()

	-- Top label: what's happening right now
	if state == States.Countdown and endsAt then
		timerLabel.Text = ("Starting in %d"):format(math.max(1, math.ceil(endsAt - now)))
	elseif state == States.Playing and player:GetAttribute("RunStart") then
		timerLabel.Text = ("Time: %.1fs"):format(now - player:GetAttribute("RunStart"))
	elseif state == States.Waiting then
		timerLabel.Text = "Waiting"
	end

	-- Announcement: a local flash wins over the server's message
	local text = (os.clock() < flashUntil) and flashText or match:GetAttribute("Message") or ""
	announceLabel.Text = text
	announceLabel.Visible = text ~= ""
end)
