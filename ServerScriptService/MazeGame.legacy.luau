-- Runs the maze rounds: build a maze, time each player's run,
-- and when someone reaches the finish, announce it and build a new maze.

local Players = game:GetService("Players")
local MazeBuilder = require(game:GetService("ServerStorage").MazeBuilder)

local PLAYER_SPEED = 24   -- player walk speed in studs per second (Roblox default is 16)

-- A StringValue the clients watch to show announcements
local announcement = Instance.new("StringValue")
announcement.Name = "Announcement"
announcement.Parent = game:GetService("ReplicatedStorage")

local startPos, roundOver

local function startRun(player)
	-- Clients read this attribute to show a live timer
	player:SetAttribute("RunStart", workspace:GetServerTimeNow())
end

local function sendToStart(player)
	local character = player.Character
	if character then
		character:PivotTo(CFrame.new(startPos + Vector3.new(math.random(-2, 2), 0, math.random(-2, 2))))
	end
	startRun(player)
end

local function onFinishTouched(hit)
	if roundOver then return end
	local player = Players:GetPlayerFromCharacter(hit.Parent)
	if not player then return end
	roundOver = true

	local runTime = workspace:GetServerTimeNow() - (player:GetAttribute("RunStart") or 0)
	runTime = math.floor(runTime * 10) / 10

	local stats = player.leaderstats
	stats.Wins.Value += 1
	if stats.Best.Value == 0 or runTime < stats.Best.Value then
		stats.Best.Value = runTime
	end

	announcement.Value = ("%s escaped in %.1fs! New maze in 5..."):format(player.DisplayName, runTime)
	task.wait(5)
	announcement.Value = ""
	newRound()
end

function newRound()
	local _, start, finish = MazeBuilder.build()
	startPos = start
	finish.Touched:Connect(onFinishTouched)
	for _, player in Players:GetPlayers() do
		sendToStart(player)
	end
	roundOver = false
end

Players.PlayerAdded:Connect(function(player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	stats.Parent = player

	local wins = Instance.new("IntValue")
	wins.Name = "Wins"
	wins.Parent = stats

	local best = Instance.new("NumberValue")
	best.Name = "Best"   -- fastest escape in seconds (0 = none yet)
	best.Parent = stats

	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Humanoid").WalkSpeed = PLAYER_SPEED
		startRun(player)  -- resetting your character restarts your timer
	end)
end)

newRound()
