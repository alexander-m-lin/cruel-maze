-- Runs matches, one after another, as a "state machine": the match is always in exactly one
-- state, and moves to the next when that state's job is done.
--
--   Waiting   - fewer than Config.MIN_PLAYERS players; nothing happens until more arrive
--   Countdown - a new maze is built, everyone gets a role, lives and a character in the start
--               room, frozen, while a short countdown runs; the monsters don't hunt yet
--   Playing   - survivors have Config.MATCH_TIME seconds to collect Config.RELICS_NEEDED relics.
--               Caught survivors lose a life and pick a captured spawn room to come back in;
--               with no lives left they're out.
--   Results   - the result is shown for a few seconds, then everything is cleared away
--
-- How a match ends:
--   survivors win  - enough relics collected
--   monsters win   - time runs out, or every survivor is out of lives
--
-- Players' computers follow along through attributes on ReplicatedStorage.Match:
--   State   - the current state (one of Config.States)
--   EndsAt  - server time when the current state ends (countdown, match timer, results)
--   Message - text to show on screen ("" = none)
--   RelicsCollected / RelicsNeeded / RelicsTotal, and a SpawnRooms folder (see Objectives)
--   Winner  - during Results: the role that won (Config.Roles.Survivor or .Monster)
-- and on each player:
--   Role, Lives, Out (no lives left), Respawning (choosing a spawn room), RespawnBy (deadline),
--   SpawnRoom (the room they'll come back in), BaseSpeed (see Controls), Seized (held by a
--   monster that's killing them: their controls stop)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Config)
local Net = require(ReplicatedStorage.Net)
local MazeBuilder = require(ServerStorage.MazeBuilder)
local MonsterAI = require(ServerStorage.MonsterAI)
local Objectives = require(ServerStorage.Objectives)

local States, Roles = Config.States, Config.Roles

local KILL = MonsterAI.KILL
local MIN_RESPAWN_DELAY = KILL.DONE + 0.5  -- seconds after being caught before you can come back

local Match = {}

local status = Instance.new("Configuration")   -- just a container for the attributes above
status.Name = "Match"
status.Parent = ReplicatedStorage

local caughtEvent = Net.event("Caught")              -- server -> player: you were caught (lives left)
local chooseSpawnEvent = Net.event("ChooseSpawn")    -- player -> server: respawn me in this room
local noticeEvent = Net.event("Notice")              -- server -> everyone: a short message (relic found...)
local collectEvent = Net.event("CollectRelic")       -- player -> server: I clicked to collect this relic

local state = nil
local maze = nil         -- this match's maze (see MazeBuilder.build)
local objectives = nil   -- this match's relics and spawn rooms (see Objectives)
local monsters = {}      -- this match's MonsterAI objects
local caughtAt = {}      -- [player] = os.clock() when they were last caught

-- Characters only appear when this script says so (so caught players can choose where to respawn)
Players.CharacterAutoLoads = false

---------------------------------------------------------------- helpers
local function setState(newState, duration, message)
	state = newState
	status:SetAttribute("State", newState)
	status:SetAttribute("EndsAt", duration and workspace:GetServerTimeNow() + duration or nil)
	status:SetAttribute("Message", message or "")
end

local function aliveCharacter(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 and character:FindFirstChild("HumanoidRootPart") then
		return character
	end
	return nil
end

-- Survivors still in the match (not out of lives)
local function survivorsInMatch()
	local list = {}
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("Role") == Roles.Survivor and not player:GetAttribute("Out") then
			table.insert(list, player)
		end
	end
	return list
end

-- Survivors the monsters may hunt right now: alive, not being killed, and not inside a protected room
local function huntable()
	local list = {}
	for _, player in survivorsInMatch() do
		local character = not player:GetAttribute("Seized") and aliveCharacter(player)
		if character and not (objectives and objectives:IsSafe(character.HumanoidRootPart.Position)) then
			table.insert(list, player)
		end
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

-- Each player gets their own spot in a spawn room, so nobody spawns inside anybody else.
-- Spots sit on a circle around the room's centre, facing outward.
local SPAWN_RADIUS = 5
local SPAWN_SLOTS = 6
local function spawnSpot(player, room)
	local list = Players:GetPlayers()
	table.sort(list, function(a, b) return a.UserId < b.UserId end)   -- same order on every call
	local index = (table.find(list, player) or 1) - 1
	local angle = (index % SPAWN_SLOTS) / SPAWN_SLOTS * math.pi * 2
	local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * SPAWN_RADIUS
	local at = room.center + Vector3.new(0, 4, 0) + offset
	return CFrame.lookAt(at, at + offset)
end

-- Put a (new) character in the player's chosen spawn room (the start room if it isn't available)
local function placeInSpawnRoom(player)
	local character = player.Character
	if not (character and maze) then return end
	local room = objectives and objectives:CapturedRoom(player:GetAttribute("SpawnRoom") or 1) or maze.rooms[1]
	character:PivotTo(spawnSpot(player, room))
end

local function respawn(player)
	if not player.Parent or not player:GetAttribute("Respawning") then return end
	player:SetAttribute("Respawning", nil)
	player:SetAttribute("RespawnBy", nil)
	player:LoadCharacter()     -- CharacterAdded (below) moves the new character into the room
end

-- THE KILL (see MonsterAI.KILL for the timing): the monster lifts its victim overhead, holds them
-- struggling, then tears them apart. It's drawn on each player's computer (MonsterAnimate), where
-- the monster's hands are: the victim's body is shown in its grip, and at the rip a copy of it
-- comes apart in pieces. Here the victim is only frozen in place, then removed after the rip.
local function playKill(player, character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root) then return end
	player:SetAttribute("Seized", true)
	humanoid.PlatformStand = true                      -- no walking or balancing while held
	root.Anchored = true                               -- players' computers move it, for show only
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then part.CanCollide = false end
	end
	task.delay(KILL.RIP + 0.3, function()
		player:SetAttribute("Seized", nil)
		if character.Parent then character:Destroy() end   -- the pieces are players' own copies by now
	end)
end

local function onCaught(player, monster)
	if state ~= States.Playing then return end
	caughtAt[player] = os.clock()
	local lives = math.max(0, (player:GetAttribute("Lives") or 1) - 1)
	player:SetAttribute("Lives", lives)
	caughtEvent:FireClient(player, lives)
	local character = player.Character
	if monster and character then
		playKill(player, character)
	else
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then humanoid.Health = 0 end
	end

	-- Once the kill has played out: out of the match, or choose where to come back (if they
	-- don't choose in time, their last room is used)
	task.delay(monster and KILL.DONE or 0, function()
		if state ~= States.Playing or not player.Parent then return end
		if lives <= 0 then
			player:SetAttribute("Out", true)    -- out for the rest of the match: watches teammates
			return
		end
		player:SetAttribute("Respawning", true)
		player:SetAttribute("RespawnBy", workspace:GetServerTimeNow() + Config.RESPAWN_CHOICE_TIME)
		task.delay(Config.RESPAWN_CHOICE_TIME, function()
			if state == States.Playing then respawn(player) end
		end)
	end)
end

-- A player clicked to collect a relic (Objectives checks they're really on it)
collectEvent.OnServerEvent:Connect(function(player, relicId)
	if state ~= States.Playing or not objectives or typeof(relicId) ~= "number" then return end
	if player:GetAttribute("Role") ~= Roles.Survivor or player:GetAttribute("Seized") then return end
	objectives:StartCollecting(player, relicId)
end)

-- A player picked a spawn room. Check everything: never trust what a client sends.
chooseSpawnEvent.OnServerEvent:Connect(function(player, roomId)
	if state ~= States.Playing or not player:GetAttribute("Respawning") then return end
	if typeof(roomId) ~= "number" or not objectives or not objectives:CapturedRoom(roomId) then return end
	player:SetAttribute("SpawnRoom", roomId)
	local wait = MIN_RESPAWN_DELAY - (os.clock() - (caughtAt[player] or 0))
	if wait > 0 then
		task.delay(wait, function()
			if state == States.Playing then respawn(player) end
		end)
	else
		respawn(player)
	end
end)

local function cleanUp()
	for _, monster in monsters do monster:Destroy() end
	table.clear(monsters)
	if objectives then objectives:Destroy() end
	objectives = nil
	table.clear(caughtAt)
	for _, player in Players:GetPlayers() do
		for _, name in { "Lives", "Out", "Respawning", "RespawnBy", "SpawnRoom" } do
			player:SetAttribute(name, nil)
		end
	end
end

-- The free cell nearest the middle of the maze, for a monster to appear in
local function monsterStartCell()
	local mid = math.ceil(maze.n / 2)
	local best, bestDist
	for x = 1, maze.n do
		for z = 1, maze.n do
			if not objectives:IsBlocked(x, z) then
				local d = math.abs(x - mid) + math.abs(z - mid)
				if not bestDist or d < bestDist then best, bestDist = { x, z }, d end
			end
		end
	end
	return best
end

local function formatTime(seconds)
	seconds = math.max(0, math.floor(seconds))
	return ("%d:%02d"):format(seconds // 60, seconds % 60)
end

---------------------------------------------------------------- the states
local function runWaiting()
	setState(States.Waiting, nil, "Waiting for players...")
	while #Players:GetPlayers() < Config.MIN_PLAYERS do
		task.wait(0.5)
	end
end

local function runCountdown()
	maze = MazeBuilder.build({
		spawnRooms = Config.SPAWN_ROOMS,
		roomSpacing = Config.SPAWN_ROOM_SPACING,
		relics = Config.RELIC_TOTAL,
		relicSpacing = Config.RELIC_SPACING,
		relicsNearStart = Config.RELICS_NEAR_START,
	})
	objectives = Objectives.new(maze, {
		onRelic = function(player, relic)
			local stats = player:FindFirstChild("leaderstats")
			if stats then stats.Relics.Value += 1 end
			noticeEvent:FireAllClients(("%s collected a relic! (%d/%d)"):format(
				player.DisplayName, objectives.collected, Config.RELICS_NEEDED))
		end,
		onCapture = function(player, room)
			noticeEvent:FireAllClients(("%s captured a spawn room!"):format(player.DisplayName))
		end,
	})

	for _ = 1, Config.MONSTER_COUNT do
		local monster = MonsterAI.new(maze, {
			onCatch = onCaught,
			isBlocked = function(x, z) return objectives:IsBlocked(x, z) end,
			startCell = monsterStartCell(),
		})
		monster.active = false
		table.insert(monsters, monster)
	end

	setState(States.Countdown, Config.COUNTDOWN)
	for _, player in Players:GetPlayers() do
		player:SetAttribute("Role", Roles.Survivor)   -- Phase 1: everyone is a survivor
		player:SetAttribute("Lives", Config.LIVES)
		player:SetAttribute("Out", nil)
		player:SetAttribute("Respawning", nil)
		player:SetAttribute("SpawnRoom", 1)
		task.spawn(player.LoadCharacter, player)      -- a fresh character in the start room
	end
	task.wait(Config.COUNTDOWN)
end

-- Returns "survivors", "time", "caught", or nil if the match was abandoned (everyone left)
local function runPlaying()
	setState(States.Playing, Config.MATCH_TIME)
	local endsAt = os.clock() + Config.MATCH_TIME
	for _, monster in monsters do monster.active = true end
	for _, player in Players:GetPlayers() do applySpeed(player) end

	while true do
		if #Players:GetPlayers() < Config.MIN_PLAYERS then return nil end
		local collectors = {}
		for _, player in survivorsInMatch() do
			if not player:GetAttribute("Seized") then table.insert(collectors, player) end
		end
		objectives:Update(collectors)
		if objectives.collected >= Config.RELICS_NEEDED then return "survivors" end
		if os.clock() >= endsAt then return "time" end
		if #survivorsInMatch() == 0 then return "caught" end
		task.wait(0.1)
	end
end

local function runResults(outcome, elapsed)
	for _, monster in monsters do monster.active = false end
	local message
	if outcome == "survivors" then
		message = ("The survivors escaped with %d relics in %s!"):format(objectives.collected, formatTime(elapsed))
		for _, player in Players:GetPlayers() do
			local stats = player:FindFirstChild("leaderstats")
			if stats and player:GetAttribute("Role") == Roles.Survivor then stats.Wins.Value += 1 end
		end
	elseif outcome == "time" then
		message = ("Time's up! The monsters win. (%d/%d relics)"):format(objectives.collected, Config.RELICS_NEEDED)
	else
		message = "Every survivor was caught! The monsters win."
	end
	status:SetAttribute("Winner", outcome == "survivors" and Roles.Survivor or Roles.Monster)
	setState(States.Results, Config.RESULTS_TIME, message)
	task.wait(Config.RESULTS_TIME)
	status:SetAttribute("Winner", nil)
end

---------------------------------------------------------------- players
local function onPlayerAdded(player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	stats.Parent = player

	local wins = Instance.new("IntValue")
	wins.Name = "Wins"        -- matches won as a survivor
	wins.Parent = stats

	local relics = Instance.new("IntValue")
	relics.Name = "Relics"    -- relics collected, all time (this session)
	relics.Parent = stats

	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Humanoid")
		character:WaitForChild("HumanoidRootPart")
		applySpeed(player)
		if state == States.Countdown or state == States.Playing then
			task.defer(placeInSpawnRoom, player)
		end
	end)

	-- Joining mid-match: you're a survivor with full lives, in the start room
	if state == States.Countdown or state == States.Playing then
		player:SetAttribute("Role", Roles.Survivor)
		player:SetAttribute("Lives", Config.LIVES)
		player:SetAttribute("SpawnRoom", 1)
	end
	player:LoadCharacter()
end

Players.PlayerRemoving:Connect(function(player)
	caughtAt[player] = nil
end)

---------------------------------------------------------------- main loop
function Match.run()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do task.spawn(onPlayerAdded, player) end

	-- The monsters think every frame while a match is on
	RunService.Heartbeat:Connect(function(dt)
		if #monsters == 0 then return end
		local targets = huntable()
		for _, monster in monsters do monster:Step(dt, targets) end
	end)

	while true do
		runWaiting()
		runCountdown()
		local started = os.clock()
		local outcome = runPlaying()
		if outcome then
			runResults(outcome, os.clock() - started)
		end
		cleanUp()
	end
end

return Match
