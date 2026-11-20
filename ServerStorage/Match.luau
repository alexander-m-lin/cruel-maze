-- Runs matches, one after another, as a "state machine": the match is always in exactly one
-- state, and moves to the next when that state's job is done.
--
--   Waiting   - fewer than Config.MIN_PLAYERS players; nothing happens until more arrive
--   Countdown - a new maze is built and everyone gets a role (3 survivors, 2 monsters, 1 Maze
--               Master; see assignRoles). Survivors get lives and a character in the start room,
--               monsters a character at their start spot, the Maze Master no character at all. All
--               frozen while a short countdown runs; the monsters don't hunt yet
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
--   monster that's killing them: their controls stop), Killing (a monster player mid-kill: can't
--   move), DevRole (Studio only: the role they asked for in the dev panel)
--
-- Survivor bots fill empty survivor slots (Config.SURVIVOR_BOTS); they pass for players (SurvivorBot).
--
-- Monsters played by people: an invisible character dressed in the monster body (PlayerMonster).
-- Empty monster slots get AI monsters (MonsterAI). Monster characters are in the "MonsterPlayers"
-- collision group, which collides with the spawn rooms' barriers ("Wards"); nothing else does.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Config)
local Net = require(ReplicatedStorage.Net)
local MazeBuilder = require(ServerStorage.MazeBuilder)
local MonsterAI = require(ServerStorage.MonsterAI)
local PlayerMonster = require(ServerStorage.PlayerMonster)
local SurvivorBot = require(ServerStorage.SurvivorBot)
local Objectives = require(ServerStorage.Objectives)
local Doors = require(ServerStorage.Doors)
local Crushers = require(ServerStorage.Crushers)
local MazeMaster = require(ServerStorage.MazeMaster)

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
local lungeEvent = Net.event("Lunge")                -- monster player -> server: I clicked to lunge
local devEvent = Net.event("DevMatch")               -- Studio only: { "role", role | nil } or { "restart" }
local toolEvent = Net.event("MazeMasterTool")        -- Maze Master -> server: use a tool (tool, target)
local toolResultEvent = Net.event("MazeMasterResult") -- server -> Maze Master: (ok, message)
local falseRelicEvent = Net.event("FalseRelicSprung") -- server -> survivor: you clicked a false relic
local falseRelicsEvent = Net.event("FalseRelics")     -- server -> monster side only: the ids of the false relics

-- Spawn-room barriers stop monster players and nothing else; crushing walls stop everyone but them.
-- Monster players pass through survivors (players and bots): they catch with the lunge, and a
-- solid monster shoving into a survivor - a bot especially - could fling it into the air.
PhysicsService:RegisterCollisionGroup("Survivors")
PhysicsService:RegisterCollisionGroup("MonsterPlayers")
PhysicsService:RegisterCollisionGroup("Wards")
PhysicsService:RegisterCollisionGroup("Crushers")
PhysicsService:CollisionGroupSetCollidable("Crushers", "MonsterPlayers", false)
PhysicsService:CollisionGroupSetCollidable("Survivors", "MonsterPlayers", false)
for _, group in PhysicsService:GetRegisteredCollisionGroups() do
	if group.name ~= "MonsterPlayers" and group.name ~= "Wards" then
		PhysicsService:CollisionGroupSetCollidable("Wards", group.name, false)
	end
end
PhysicsService:CollisionGroupSetCollidable("Wards", "Wards", false)
PhysicsService:CollisionGroupSetCollidable("Wards", "MonsterPlayers", true)

local state = nil
local maze = nil         -- this match's maze (see MazeBuilder.build)
local objectives = nil   -- this match's relics and spawn rooms (see Objectives)
local monsters = {}      -- this match's monsters: MonsterAI (bots) and PlayerMonster objects
local playerMonsters = {} -- [player] = their PlayerMonster
local bots = {}           -- this match's survivor bots (SurvivorBot: they pass for players)
local restartRequested = false   -- Studio dev panel: end this match now
local doors = nil        -- this match's doors (see Doors)
local crushers = nil     -- this match's crushing walls (see Crushers)
local mazeMasterTools = nil  -- the Maze Master player's tools (see MazeMaster), if a person is the Maze Master
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
	for _, bot in bots do
		if not bot:GetAttribute("Out") then table.insert(list, bot) end
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
	local full = player:GetAttribute("Role") == Roles.Monster and Config.MONSTER_SPEED or Config.PLAYER_SPEED
	local speed = (state == States.Countdown) and 0 or full
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
	for _, bot in bots do table.insert(list, bot) end
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

-- A survivor's character (a player's or a bot's): in the "Survivors" collision group, which monster
-- players pass through. Parts added later (accessories loading) join it too.
local function setUpSurvivorCharacter(character)
	local function join(d)
		if d:IsA("BasePart") then d.CollisionGroup = "Survivors" end
	end
	for _, d in character:GetDescendants() do join(d) end
	character.DescendantAdded:Connect(join)
end

-- A monster player's character: invisible (the monster body is drawn in its place), no name tag,
-- and stopped by spawn-room barriers. Placed at its monster's start spot.
local function setUpMonsterCharacter(player, character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None end
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			d.Transparency = 1
			d.CastShadow = false
			d.CollisionGroup = "MonsterPlayers"
		elseif d:IsA("Decal") then
			d.Transparency = 1
		elseif d:IsA("Accessory") then
			d:Destroy()
		end
	end
	local monster = playerMonsters[player]
	if monster then monster:PlaceCharacter(character) end
end

local function respawn(player)
	if not player.Parent or not player:GetAttribute("Respawning") then return end
	player:SetAttribute("Respawning", nil)
	player:SetAttribute("RespawnBy", nil)
	player:LoadCharacter()     -- CharacterAdded (below) moves the new character into the room
	if player.isBot then                                  -- (bots have no CharacterAdded)
		setUpSurvivorCharacter(player.Character)
		placeInSpawnRoom(player)
	end
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
	if not player.isBot then caughtEvent:FireClient(player, lives) end
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
		if player.isBot then
			-- bots pick a captured room at random, straight away
			local rooms = {}
			for _, room in maze.rooms do
				if room.captured then table.insert(rooms, room.id) end
			end
			player:SetAttribute("SpawnRoom", rooms[math.random(#rooms)] or 1)
			task.delay(0.5, function()
				if state == States.Playing then respawn(player) end
			end)
			return
		end
		task.delay(Config.RESPAWN_CHOICE_TIME, function()
			if state == States.Playing then respawn(player) end
		end)
	end)
end

-- A monster player clicked to lunge (PlayerMonster checks it's allowed)
lungeEvent.OnServerEvent:Connect(function(player)
	if state ~= States.Playing then return end
	local monster = playerMonsters[player]
	if monster then monster:Lunge() end
end)

-- The Maze Master used a tool (MazeMaster checks everything)
toolEvent.OnServerEvent:Connect(function(player, tool, target)
	if state ~= States.Playing or not mazeMasterTools or mazeMasterTools.player ~= player then return end
	if typeof(tool) ~= "string" then return end
	local ok, message = mazeMasterTools:Use(tool, target)
	toolResultEvent:FireClient(player, ok, message)
end)

-- Studio dev panel: pick your role for the next match, or end this match now
devEvent.OnServerEvent:Connect(function(player, action, value)
	if not RunService:IsStudio() then return end
	if action == "role" and (value == nil or (typeof(value) == "string" and Config.ROLE_SLOTS[value])) then
		player:SetAttribute("DevRole", value)
	elseif action == "restart" then
		restartRequested = true
	end
end)

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
	restartRequested = false    -- (a "New match" click during the countdown still ends that match, once it's playing)
	for _, monster in monsters do monster:Destroy() end
	table.clear(monsters)
	table.clear(playerMonsters)
	for _, bot in bots do bot:Destroy() end
	table.clear(bots)
	if objectives then objectives:Destroy() end
	objectives = nil
	if doors then doors:Destroy() end
	doors = nil
	crushers = nil
	if mazeMasterTools then mazeMasterTools:Destroy() end
	mazeMasterTools = nil
	table.clear(caughtAt)
	for _, player in Players:GetPlayers() do
		for _, name in { "Lives", "Out", "Respawning", "RespawnBy", "SpawnRoom", "Killing", "RevealedUntil", "SlowUntil" } do
			player:SetAttribute(name, nil)
		end
	end
end

-- The free cell nearest the middle of the maze, for a monster to appear in
-- Where each monster appears. The first: the free cell nearest the middle. Each one after: as far
-- as possible from those already placed, but never near the start room (survivors spawn there).
local START_ROOM_CLEARANCE = 6   -- cells
local function monsterStartCell(taken)
	local mid = math.ceil(maze.n / 2)
	local startRoom = maze.rooms[1]
	local best, bestScore
	for x = 1, maze.n do
		for z = 1, maze.n do
			if objectives:IsBlocked(x, z) then continue end
			if math.abs(x - startRoom.x) + math.abs(z - startRoom.z) < START_ROOM_CLEARANCE then continue end
			local score
			if #taken == 0 then
				score = -(math.abs(x - mid) + math.abs(z - mid))       -- nearest the middle
			else
				score = math.huge
				for _, c in taken do score = math.min(score, math.abs(x - c[1]) + math.abs(z - c[2])) end
			end
			if not bestScore or score > bestScore then best, bestScore = { x, z }, score end
		end
	end
	return best
end

-- ROLES: 3 survivors, 2 monsters, 1 Maze Master (Config.ROLE_SLOTS), handed out at random. In
-- Studio, a role picked in the dev panel (DevRole) comes first. Without survivor bots, there's
-- always at least one survivor; anyone beyond six players is a survivor too.
-- Returns { [player] = role }
local function assignRoles()
	local free = table.clone(Config.ROLE_SLOTS)
	local roles = {}
	local rest = {}
	for _, player in Players:GetPlayers() do
		local wanted = RunService:IsStudio() and player:GetAttribute("DevRole")
		if wanted and (free[wanted] or 0) > 0 then
			roles[player] = wanted
			free[wanted] -= 1
		else
			table.insert(rest, player)
		end
	end
	for i = #rest, 2, -1 do
		local j = math.random(i)
		rest[i], rest[j] = rest[j], rest[i]
	end
	local hasSurvivor = Config.SURVIVOR_BOTS   -- (with bots there are always survivors)
	for _, role in roles do if role == Roles.Survivor then hasSurvivor = true end end
	for _, player in rest do
		local role
		if not hasSurvivor then
			role = Roles.Survivor
		else
			-- a random free slot (each slot equally likely)
			local total = 0
			for _, n in free do total += n end
			if total == 0 then
				role = Roles.Survivor
			else
				local pick = math.random(total)
				for name, n in free do
					if pick <= n then role = name break end
					pick -= n
				end
			end
		end
		roles[player] = role
		if (free[role] or 0) > 0 then free[role] -= 1 end
		if role == Roles.Survivor then hasSurvivor = true end
	end
	return roles
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
		doorCorridors = Config.DOOR_CORRIDORS,
		doorShortcuts = Config.DOOR_SHORTCUTS,
		doorSpacing = Config.DOOR_SPACING,
		doorMinDetour = Config.DOOR_MIN_DETOUR,
		crushers = Config.CRUSHERS,
		crusherSpacing = Config.CRUSHER_SPACING,
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
		-- a false relic was placed: tell the monster side (only them) which relics are false
		onFalseRelicPlaced = function()
			local ids = {}
			for _, relic in objectives.fakes do table.insert(ids, relic.id) end
			for _, player in Players:GetPlayers() do
				local role = player:GetAttribute("Role")
				if role == Roles.Monster or role == Roles.MazeMaster then falseRelicsEvent:FireClient(player, ids) end
			end
		end,
		-- a survivor clicked a false relic: revealed to the monster side, and slowed
		onFalseRelic = function(player, relic)
			local now = workspace:GetServerTimeNow()
			player:SetAttribute("RevealedUntil", now + Config.FALSE_RELIC_REVEAL_TIME)
			player:SetAttribute("SlowUntil", now + Config.FALSE_RELIC_SLOW_TIME)
			if not player.isBot then falseRelicEvent:FireClient(player) end
		end,
	})

	-- spawn-room barriers become solid for monster players
	for _, room in maze.rooms do
		for _, ward in room.wards do
			ward.CanCollide = true
			ward.CollisionGroup = "Wards"
		end
	end

	-- Roles, then the monsters: one per monster player, AI for the empty slots
	local roles = assignRoles()
	local monsterPlayers, mazeMaster = {}, nil
	for player, role in roles do
		if role == Roles.Monster then table.insert(monsterPlayers, player) end
		if role == Roles.MazeMaster then mazeMaster = player end
	end
	local starts = {}
	for i = 1, math.max(Config.MONSTER_COUNT, #monsterPlayers) do
		local startCell = monsterStartCell(starts)
		table.insert(starts, startCell)
		local player = monsterPlayers[i]
		local monster
		if player then
			monster = PlayerMonster.new(player, maze, { onCatch = onCaught, startCell = startCell })
			playerMonsters[player] = monster
		else
			monster = MonsterAI.new(maze, {
				onCatch = onCaught,
				isBlocked = function(x, z) return objectives:IsBlocked(x, z) end,
				startCell = startCell,
				pack = monsters,                        -- they spread out from each other when roaming
			})
		end
		monster.active = false
		table.insert(monsters, monster)
	end
	-- with no Maze Master player, an AI works the doors
	doors = Doors.new(maze, { monsters = monsters, survivors = survivorsInMatch, ai = mazeMaster == nil,
		bots = function() return bots end })
	crushers = Crushers.new(maze, { onCrush = function(player) onCaught(player, nil) end, survivors = survivorsInMatch })
	if mazeMaster then
		mazeMasterTools = MazeMaster.new(mazeMaster, { maze = maze, doors = doors, crushers = crushers, objectives = objectives })
	end

	-- survivor bots for the empty survivor slots
	if Config.SURVIVOR_BOTS then
		local humans = 0
		for _, role in roles do if role == Roles.Survivor then humans += 1 end end
		for i = 1, math.max(0, Config.ROLE_SLOTS.Survivor - humans) do
			local bot = SurvivorBot.new(maze, objectives, i)
			table.insert(bots, bot)
		end
	end

	setState(States.Countdown, Config.COUNTDOWN)
	for _, bot in bots do
		bot:SetAttribute("Role", Roles.Survivor)
		bot:SetAttribute("Lives", Config.LIVES)
		bot:SetAttribute("SpawnRoom", 1)
		bot:SetAttribute("BaseSpeed", 0)
		bot:LoadCharacter()
		setUpSurvivorCharacter(bot.Character)
		placeInSpawnRoom(bot)
	end
	for player, role in roles do
		player:SetAttribute("Role", role)
		player:SetAttribute("Lives", role == Roles.Survivor and Config.LIVES or nil)
		player:SetAttribute("Out", nil)
		player:SetAttribute("Respawning", nil)
		player:SetAttribute("Killing", nil)
		player:SetAttribute("SpawnRoom", role == Roles.Survivor and 1 or nil)
		if role == Roles.MazeMaster then
			if player.Character then player.Character:Destroy() end   -- no body in the maze
			player.Character = nil
		else
			task.spawn(player.LoadCharacter, player)  -- a fresh character (start room, or monster spot)
		end
	end
	task.wait(Config.COUNTDOWN)
end

-- Returns "survivors", "time", "caught", or nil if the match was abandoned (everyone left)
local function runPlaying()
	setState(States.Playing, Config.MATCH_TIME)
	local endsAt = os.clock() + Config.MATCH_TIME
	for _, monster in monsters do monster.active = true end
	for _, bot in bots do bot:SetAttribute("BaseSpeed", Config.PLAYER_SPEED) end
	doors.running = true
	if mazeMasterTools then mazeMasterTools.active = true end
	for _, player in Players:GetPlayers() do applySpeed(player) end

	local hadSurvivors = #survivorsInMatch() > 0
	while true do
		if #Players:GetPlayers() < Config.MIN_PLAYERS or restartRequested then return nil end
		local collectors = {}
		for _, player in survivorsInMatch() do
			if not player:GetAttribute("Seized") then table.insert(collectors, player) end
		end
		objectives:Update(collectors)
		objectives:UpdateMonsterSight(monsters)
		if objectives.collected >= Config.RELICS_NEEDED then return "survivors" end
		if os.clock() >= endsAt then return "time" end
		if #survivorsInMatch() == 0 and hadSurvivors then return "caught" end   -- (none at all: a test, play on)
		task.wait(0.1)
	end
end

local function runResults(outcome, elapsed)
	for _, monster in monsters do monster.active = false end
	if doors then doors.running = false end
	if mazeMasterTools then mazeMasterTools.active = false end
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
			if player:GetAttribute("Role") == Roles.MazeMaster then
				-- the Maze Master has no body in the maze. (One can still turn up: a character
				-- that was loading when they joined, finishing after the match gave them the role.)
				task.defer(function()
					if player.Character == character then player.Character = nil end
					character:Destroy()
				end)
			elseif player:GetAttribute("Role") == Roles.Monster then
				task.defer(setUpMonsterCharacter, player, character)
			else
				setUpSurvivorCharacter(character)
				task.defer(placeInSpawnRoom, player)
			end
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

---------------------------------------------------------------- test hook (Studio only)
-- Tools that run code in Studio get their own copy of this module, so they reach the match
-- through ServerStorage.MatchTest:Invoke(action, ...):
--   "crushers"              -> { [id] = { center, state } }
--   "crush", id             -> set that crusher off (no dark mana needed)
--   "falseRelic", x, z      -> place a false relic in cell (x, z); -> its id, or nil
--   "monsters", on          -> switch every monster on or off (off: they stand still and catch nobody)
if RunService:IsStudio() then
	local hook = Instance.new("BindableFunction")
	hook.Name = "MatchTest"
	hook.OnInvoke = function(action, a, b)
		if action == "crushers" and crushers then
			local out = {}
			for id, c in crushers.list do out[id] = { center = c.center, state = c.state, x = c.x, z = c.z, along = c.along } end
			return out
		elseif action == "crush" and crushers then
			return crushers:Trigger(a)
		elseif action == "monsters" then
			for _, monster in monsters do monster.active = a == true end
			return true
		elseif action == "falseRelic" and objectives then
			local relic = objectives:AddFalseRelic(a, b)
			return relic and relic.id
		end
		return nil
	end
	hook.Parent = ServerStorage
end

---------------------------------------------------------------- main loop
function Match.run()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do task.spawn(onPlayerAdded, player) end

	-- Doors move and the monsters think every frame while a match is on
	RunService.Heartbeat:Connect(function(dt)
		if doors then doors:Step(dt) end
		if crushers then crushers:Step() end
		if mazeMasterTools then mazeMasterTools:Step(dt) end
		for _, bot in bots do bot:Step(dt, monsters) end
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
