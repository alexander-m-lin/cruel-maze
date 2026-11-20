-- The on-screen HUD:
--   top:     the countdown / time left in the match
--   below:   relics collected and your lives
--   below:   messages (match results, relic found, caught, choosing a spawn room...)
-- Follows the match through attributes on ReplicatedStorage.Match and on your player
-- (see ServerStorage.Match and ServerStorage.Objectives).
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = game:GetService("Players").LocalPlayer

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Net = require(ReplicatedStorage:WaitForChild("Net"))
local States = Config.States

-- Things with a progress bar (see MazeBuilder.buildProgressBar): their info folder in
-- ReplicatedStorage.Match, their model's name in the maze, and how long they take
local BAR_KINDS = {
	{ folder = "Relics", prefix = "Relic", time = Config.RELIC_COLLECT_TIME },
	{ folder = "WardEyes", prefix = "Ward", time = Config.WARD_DESTROY_TIME },
}

local gui = script.Parent
local timerLabel = gui:WaitForChild("TimerLabel")
local announceLabel = gui:WaitForChild("AnnounceLabel")
local match = ReplicatedStorage:WaitForChild("Match")

-- A second line under the timer, in the same style
local statusLabel = gui:FindFirstChild("StatusLabel") or timerLabel:Clone()
statusLabel.Name = "StatusLabel"
statusLabel.Size = UDim2.fromOffset(300, 36)
statusLabel.Position = UDim2.new(0.5, 0, 0, 76)
statusLabel.TextSize = 20
statusLabel.Visible = false
statusLabel.Parent = gui
announceLabel.Position = UDim2.new(0.5, 0, 0, 120)

-- Short local messages, newest wins (e.g. "You were caught!", "Ana found a relic!")
local flashText, flashUntil = nil, 0
local function flash(text, seconds)
	flashText, flashUntil = text, os.clock() + (seconds or 3)
end

Net.event("Caught").OnClientEvent:Connect(function(livesLeft)
	if livesLeft and livesLeft <= 0 then
		flash("Caught! You're out of lives - watching your team.", 4)
	else
		flash(("Caught! %d %s left."):format(livesLeft or 0, livesLeft == 1 and "life" or "lives"), 2.5)
	end
end)
Net.event("Notice").OnClientEvent:Connect(function(text)
	flash(text, 3)
end)

local function formatTime(seconds)
	seconds = math.max(0, math.ceil(seconds))
	return ("%d:%02d"):format(seconds // 60, seconds % 60)
end

RunService.RenderStepped:Connect(function()
	local state = match:GetAttribute("State")
	local endsAt = match:GetAttribute("EndsAt")
	local now = workspace:GetServerTimeNow()

	-- Top: what's happening right now
	if state == States.Countdown and endsAt then
		timerLabel.Text = ("Starting in %d"):format(math.max(1, math.ceil(endsAt - now)))
	elseif state == States.Playing and endsAt then
		timerLabel.Text = formatTime(endsAt - now)
	elseif state == States.Results then
		timerLabel.Text = "Match over"
	elseif state == States.Waiting then
		timerLabel.Text = "Lobby"
	end

	-- Second line: relics and lives, during a match
	local inMatch = state == States.Countdown or state == States.Playing
	statusLabel.Visible = inMatch
	if inMatch then
		local relics = ("Relics %d/%d"):format(
			match:GetAttribute("RelicsCollected") or 0, match:GetAttribute("RelicsNeeded") or Config.RELICS_NEEDED)
		local role = player:GetAttribute("Role")
		if role == Config.Roles.Survivor then
			local lives = player:GetAttribute("Lives") or 0
			statusLabel.Text = ("%s   ·   Lives %s"):format(relics, player:GetAttribute("Out") and "out" or string.rep("♥", lives))
		else
			statusLabel.Text = ("%s   ·   %s"):format(relics, role == Config.Roles.MazeMaster and "Maze Master" or "Monster")
		end
	end

	-- Messages: a recent local flash, else your own situation, else the server's message
	local text = match:GetAttribute("Message") or ""
	if player:GetAttribute("Respawning") then
		local by = player:GetAttribute("RespawnBy")
		text = ("Choose a spawn room on the map  (%ds)"):format(by and math.max(0, math.ceil(by - now)) or 0)
	elseif player:GetAttribute("Out") and state == States.Playing then
		text = "You're out of lives - watching your team."
	end
	if os.clock() < flashUntil then text = flashText end
	announceLabel.Text = text
	announceLabel.Visible = text ~= ""

	-- Progress bars, for collecting a relic or destroying a ward: the server says when it started
	-- (CollectSince); the bar is filled here every frame so it moves smoothly
	local maze = workspace:FindFirstChild("Maze")
	for _, kind in BAR_KINDS do
		local folder = match:FindFirstChild(kind.folder)
		if not (folder and maze) then continue end
		for _, info in folder:GetChildren() do
			local model = maze:FindFirstChild(kind.prefix .. tostring(info:GetAttribute("Id")))
			local bar = model and model:FindFirstChild("Progress")
			local fill = bar and bar:FindFirstChild("Fill", true)
			if not fill then continue end
			local since = info:GetAttribute("CollectSince")
			bar.Enabled = since ~= nil and not info:GetAttribute("Collected")
			if bar.Enabled then
				fill.Size = UDim2.fromScale(math.clamp((now - since) / kind.time, 0, 1), 1)
			end
		end
	end
end)
