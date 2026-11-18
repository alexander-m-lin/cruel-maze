-- Runs matches, one after another, as a "state machine": the match is always in exactly one
-- state, and moves to the next when that state's job is done.
--
--   Waiting   - fewer than Config.MIN_PLAYERS players; nothing happens until more arrive
--   Countdown - a new maze is built, everyone gets a role and is sent to the start, frozen,
--               while a short countdown runs; the monsters are placed but don't hunt yet
--   Playing   - go! The first survivor to reach the finish wins
--   Results   - the result is shown for a few seconds, then everything is cleared away
--
-- Players' computers follow along through attributes on ReplicatedStorage.Match:
--   State   - the current state (one of Config.States)
--   EndsAt  - server time when a timed state (Countdown, Results) ends, for on-screen countdowns
--   Message - text to show on screen ("" = none)
-- and each player's "Role" and "RunStart" attributes.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Config)
local Net = require(ReplicatedStorage.Net)
local MazeBuilder = require(ServerStorage.MazeBuilder)
local MonsterAI = require(ServerStorage.MonsterAI)

local States, Roles = Config.States, Config.Roles

local Match = {}

local status = Instance.new("Configuration")   -- just a container for the attributes above
status.Name = "Match"
status.Parent = ReplicatedStorage

local caughtEvent = Net.event("Caught")         -- tells a player they were caught

local state = nil
local maze = nil         -- this match's maze (see MazeBuilder.build)
local monsters = {}      -- this match's MonsterAI objects
local winner = nil       -- set when someone reaches the finish
local finishConn = nil

---------------------------------------------------------------- helpers
local function setState(newState, duration, message)
	state = newState
	status:SetAttribute("State", newState)
	status:SetAttribute("EndsAt", duration and workspace:GetServerTimeNow() + duration or nil)
	status:SetAttribute("Message", message or "")
end

local function survivors()
	local list = {}
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("Role") == Roles.Survivor then table.insert(list, player) end
	end
	return list
end

-- Walk speed for the current state: frozen during the countdown.
-- Also published as the player's "BaseSpeed" attribute: the Controls script on their computer
-- scales it down when they move a different way from where they're facing.
local function applySpeed(player)
	local speed = (state == States.Countdown) and 0 or Config.PLAYER_SPEED
	player:SetAttribute("BaseSpeed", speed)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = speed
	end
end

-- Each player gets their own spot around the start cell, so nobody spawns inside anybody else.
-- Spots sit on a circle around the cell's centre, facing out toward the rest of the maze.
local SPAWN_RADIUS = 5
local SPAWN_SLOTS = 6
local function spawnSpot(player)
	local list = Players:GetPlayers()
	table.sort(list, function(a, b) return a.UserId < b.UserId end)   -- same order on every call
	local index = (table.find(list, player) or 1) - 1
	local angle = (index % SPAWN_SLOTS) / SPAWN_SLOTS * math.pi * 2
	local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * SPAWN_RADIUS
	local at = maze.start + offset
	return CFrame.lookAt(at, at + Vector3.new(1, 0, 1))   -- face into the maze (+X/+Z from the start corner)
end

local function sendToStart(player)
	local character = player.Character
	if character and maze then
		character:PivotTo(spawnSpot(player))
	end
end

local function startRunTimer(player)
	player:SetAttribute("RunStart", workspace:GetServerTimeNow())   -- the HUD shows time since this
end

local function onCaught(player)
	caughtEvent:FireClient(player)
	-- Phase 0 rule, same as the prototype: you're knocked out and respawn at the start.
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then humanoid.Health = 0 end
end

local function onFinishTouched(hit)
	if state ~= States.Playing or winner then return end
	local player = Players:GetPlayerFromCharacter(hit.Parent)
	if player and player:GetAttribute("Role") == Roles.Survivor then
		winner = player
	end
end

local function cleanUp()
	for _, monster in monsters do monster:Destroy() end
	table.clear(monsters)
	if finishConn then finishConn:Disconnect() end
	finishConn = nil
	winner = nil
	for _, player in Players:GetPlayers() do
		player:SetAttribute("RunStart", nil)
	end
end

---------------------------------------------------------------- the states
local function runWaiting()
	setState(States.Waiting, nil, "Waiting for players...")
	while #Players:GetPlayers() < Config.MIN_PLAYERS do
		task.wait(0.5)
	end
end

local function runCountdown()
	maze = MazeBuilder.build()
	finishConn = maze.finish.Touched:Connect(onFinishTouched)

	for i = 1, Config.MONSTER_COUNT do
		local monster = MonsterAI.new(maze, { onCatch = onCaught })
		monster.active = false
		table.insert(monsters, monster)
	end

	setState(States.Countdown, Config.COUNTDOWN)
	for _, player in Players:GetPlayers() do
		player:SetAttribute("Role", Roles.Survivor)   -- Phase 0: everyone is a survivor
		player:SetAttribute("RunStart", nil)
		sendToStart(player)
		applySpeed(player)
	end
	task.wait(Config.COUNTDOWN)
end

-- Returns false if the match was abandoned (everyone left)
local function runPlaying()
	setState(States.Playing)
	for _, monster in monsters do monster.active = true end
	for _, player in Players:GetPlayers() do
		applySpeed(player)
		startRunTimer(player)
	end
	while not winner do
		if #Players:GetPlayers() < Config.MIN_PLAYERS then return false end
		task.wait(0.1)
	end
	return true
end

local function runResults()
	for _, monster in monsters do monster.active = false end
	local player = winner
	local runTime = workspace:GetServerTimeNow() - (player:GetAttribute("RunStart") or 0)
	runTime = math.floor(runTime * 10) / 10

	local stats = player:FindFirstChild("leaderstats")
	if stats then
		stats.Wins.Value += 1
		if stats.Best.Value == 0 or runTime < stats.Best.Value then
			stats.Best.Value = runTime
		end
	end

	setState(States.Results, Config.RESULTS_TIME,
		("%s escaped in %.1fs! New maze in %d..."):format(player.DisplayName, runTime, Config.RESULTS_TIME))
	task.wait(Config.RESULTS_TIME)
end

---------------------------------------------------------------- players
local function onPlayerAdded(player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	stats.Parent = player

	local wins = Instance.new("IntValue")
	wins.Name = "Wins"
	wins.Parent = stats

	local best = Instance.new("NumberValue")
	best.Name = "Best"   -- fastest escape in seconds (0 = none yet)
	best.Parent = stats

	-- Joining mid-match: you're a survivor straight away (Phase 0)
	if state == States.Countdown or state == States.Playing then
		player:SetAttribute("Role", Roles.Survivor)
	end

	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Humanoid")
		applySpeed(player)
		-- (re)spawning during a match: move from the shared spawn pad to your own spot
		if state == States.Countdown or state == States.Playing then
			task.defer(sendToStart, player)
		end
		-- respawning (e.g. after being caught) restarts your run timer, as in the prototype
		if state == States.Playing then startRunTimer(player) end
	end)
end

---------------------------------------------------------------- main loop
function Match.run()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do onPlayerAdded(player) end

	-- The monsters think every frame while a match is on
	RunService.Heartbeat:Connect(function(dt)
		if #monsters == 0 then return end
		local targets = survivors()
		for _, monster in monsters do monster:Step(dt, targets) end
	end)

	while true do
		runWaiting()
		runCountdown()
		if runPlaying() then
			runResults()
		end
		cleanUp()
	end
end

return Match
