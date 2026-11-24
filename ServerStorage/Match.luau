-- Runs matches, one after another, as a "state machine": the match is always in exactly one
-- state, and moves to the next when that state's job is done.
--
--   Waiting   - THE LOBBY: everyone waits between matches, picks a preferred role ("PreferredRole"
--               on the player) and anyone presses Start (needs Config.MIN_PLAYERS players)
--   Countdown - a new maze is built and everyone gets a role (3 survivors, 2 monsters, 1 Maze
--               Master; see assignRoles). Survivors get lives and a character in the start sanctuary,
--               monsters a character at their start spot, the Maze Master no character at all. All
--               frozen while a short countdown runs; the monsters don't hunt yet
--   Playing   - survivors have Config.MATCH_TIME seconds to collect Config.RELICS_NEEDED relics.
--               Caught survivors lose a life and pick a captured sanctuary to come back in;
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
--   RelicsCollected / RelicsNeeded / RelicsTotal, and a Sanctuaries folder (see Objectives)
--   Winner  - during Results: the role that won (Config.Roles.Survivor or .Monster)
--   Sandbox - true while the match is the dev Sandbox (ServerStorage.Sandbox)
-- and on each player:
--   Role, Lives, Out (no lives left), Respawning (choosing a sanctuary), RespawnBy (deadline),
--   Sanctuary (the sanctuary they'll come back in), BaseSpeed (see Controls), Seized (held by a
--   monster that's killing them: their controls stop), Killing (a monster player mid-kill: can't
--   move), DevRole (Studio only: the role they asked for in the dev panel), RevealedUntil (server
--   time: shown to the monster side wherever they are), SlowUntil (a false relic), Hero (their hero;
--   survivors' are all different while the roster allows: pickSurvivorHero), PreferredHero (lobby)
--
-- Survivor bots fill empty survivor slots (Config.SURVIVOR_BOTS); they pass for players (SurvivorBot).
--
-- Monsters played by people: an invisible character dressed in the monster body (PlayerMonster).
-- Empty monster slots get AI monsters (MonsterAI). Monster characters are in the "MonsterPlayers"
-- collision group, which collides with the sanctuaries' barriers ("Wards"); nothing else does.

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
local MazeMasterAI = require(ServerStorage.MazeMasterAI)
local WardEyes = require(ServerStorage.WardEyes)
local Dev = require(ServerStorage.Dev)
local Abilities = require(ServerStorage.Abilities)
local Pull = require(ServerStorage.Pull)
local SpeedCheck = require(ServerStorage.SpeedCheck)
local Sandbox = require(ServerStorage.Sandbox)
local Fear = require(ServerStorage.Fear)
local Heroes = require(ReplicatedStorage.Heroes)
local Protection = require(ReplicatedStorage.Protection)
local Encrypt = require(ServerStorage.Encrypt)
local BotAbilities = require(ServerStorage.BotAbilities)

local States, Roles = Config.States, Config.Roles

local RESPAWN_AFTER_KILL = 0.5              -- seconds after the kill has played out before you can come back

local Match = {}

local status = Instance.new("Configuration")   -- just a container for the attributes above
status.Name = "Match"
status.Parent = ReplicatedStorage

local caughtEvent = Net.event("Caught")              -- server -> player: you were caught (lives left)
local chooseSpawnEvent = Net.event("ChooseSpawn")    -- player -> server: respawn me in this sanctuary
local noticeEvent = Net.event("Notice")              -- server -> everyone: a short message (relic found...)
local collectEvent = Net.event("CollectRelic")       -- player -> server: I clicked to collect this relic
local lungeEvent = Net.event("Lunge")                -- monster player -> server: I clicked to lunge
local devEvent = Net.event("DevMatch")               -- developers only (Dev): { "role", role | nil } or { "restart" }
local lobbyEvent = Net.event("Lobby")                -- player -> server, in the lobby: { "prefer", role | nil } or { "start" }
local toolEvent = Net.event("MazeMasterTool")        -- Maze Master -> server: use a tool (tool, target)
local toolResultEvent = Net.event("MazeMasterResult") -- server -> Maze Master: (ok, message)
local falseRelicEvent = Net.event("FalseRelicSprung") -- server -> survivor: you clicked a false relic
local falseRelicsEvent = Net.event("FalseRelics")     -- server -> monster side only: the ids of the false relics
local destroyWardEvent = Net.event("DestroyWard")     -- survivor -> server: I clicked to destroy this ward

-- Spawn-sanctuary barriers stop monster players and nothing else; crushing walls stop everyone but them.
-- Monster players pass through survivors (players and bots): they catch with the lunge, and a
-- solid monster shoving into a survivor - a bot especially - could fling it into the air.
PhysicsService:RegisterCollisionGroup("Survivors")
PhysicsService:RegisterCollisionGroup("MonsterPlayers")
PhysicsService:RegisterCollisionGroup("Wards")
PhysicsService:RegisterCollisionGroup("Crushers")
-- Fear Eater's Living Nightmare: his character ("Nightmare") passes through the maze's inner walls
-- and doors ("MazeInner"; the outer wall and sanctuaries' walls stay ordinary), and otherwise
-- collides like any monster player
PhysicsService:RegisterCollisionGroup("MazeInner")
PhysicsService:RegisterCollisionGroup("Nightmare")
PhysicsService:CollisionGroupSetCollidable("Crushers", "MonsterPlayers", false)
PhysicsService:CollisionGroupSetCollidable("Survivors", "MonsterPlayers", false)
PhysicsService:CollisionGroupSetCollidable("Crushers", "Nightmare", false)
PhysicsService:CollisionGroupSetCollidable("Survivors", "Nightmare", false)
PhysicsService:CollisionGroupSetCollidable("MazeInner", "Nightmare", false)
for _, group in PhysicsService:GetRegisteredCollisionGroups() do
	if group.name ~= "MonsterPlayers" and group.name ~= "Nightmare" and group.name ~= "Wards" then
		PhysicsService:CollisionGroupSetCollidable("Wards", group.name, false)
	end
end
PhysicsService:CollisionGroupSetCollidable("Wards", "Wards", false)
PhysicsService:CollisionGroupSetCollidable("Wards", "MonsterPlayers", true)
PhysicsService:CollisionGroupSetCollidable("Wards", "Nightmare", true)

local state = nil
local maze = nil         -- this match's maze (see MazeBuilder.build)
local objectives = nil   -- this match's relics and sanctuaries (see Objectives)
local monsters = {}      -- this match's monsters: MonsterAI (bots) and PlayerMonster objects
local playerMonsters = {} -- [player] = their PlayerMonster
local bots = {}           -- this match's survivor bots (SurvivorBot: they pass for players)
local restartRequested = false   -- dev panel: end this match now (and start the next straight away)
local startRequested = false     -- someone pressed Start in the lobby
local sandbox = false            -- this match is the dev Sandbox (see Sandbox): status attribute "Sandbox"
local sandboxNext = false        -- the next match is (dev panel: "Sandbox"; "New match" clears it)
local botCount = 0               -- survivor bots made this match (each gets the next number)
local aiMonsterCount = 0         -- AI monsters this match that cast their hero's Q and E
local heroesTaken = {}           -- [survivor hero id] = how many survivors have it this match
local monsterHeroesTaken = {}    -- [monster hero id] = how many monsters have it this match
local doors = nil        -- this match's doors (see Doors)
local crushers = nil     -- this match's crushing walls (see Crushers)
local wards = nil        -- the Maze Master's wards, floating eyes (see WardEyes)
local mazeMasterTools = nil  -- the Maze Master's tools (see MazeMaster): a person's, or the AI's
local mazeMasterAI = nil     -- the AI working them when nobody is the Maze Master (see MazeMasterAI)
local respawnFrom = {}   -- [player] = os.clock() from when they may come back (after being caught)

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

-- Survivors the monsters may hunt right now: alive, not being killed, not inside a protected sanctuary,
-- and not encrypted (Kai's Encrypt: hidden and uncatchable; monster players chase his circuits instead)
local function huntable()
	local list = {}
	for _, player in survivorsInMatch() do
		local character = not player:GetAttribute("Seized") and not Protection.encrypted(player) and aliveCharacter(player)
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
	local full = Config.PLAYER_SPEED
	if player:GetAttribute("Role") == Roles.Monster then
		local hero = Heroes.get(player:GetAttribute("Hero"))
		full = Config.MONSTER_SPEED * (hero and hero.speed or 1)   -- (a hero's own pace: the Minotaur's slower)
	end
	local speed = (state == States.Countdown) and 0 or full
	player:SetAttribute("BaseSpeed", speed)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = speed
	end
end

-- Each player gets their own spot in a sanctuary, so nobody spawns inside anybody else.
-- Spots sit on a circle around the sanctuary's centre, facing outward.
local SPAWN_RADIUS = 5
local SPAWN_SLOTS = 6
local function spawnSpot(player, sanctuary)
	local list = Players:GetPlayers()
	for _, bot in bots do table.insert(list, bot) end
	table.sort(list, function(a, b) return a.UserId < b.UserId end)   -- same order on every call
	local index = (table.find(list, player) or 1) - 1
	local angle = (index % SPAWN_SLOTS) / SPAWN_SLOTS * math.pi * 2
	local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * SPAWN_RADIUS
	local at = sanctuary.center + Vector3.new(0, 4, 0) + offset
	return CFrame.lookAt(at, at + offset)
end

-- A survivor bot (a SurvivorBot table) rather than a real Player. (Reading `player.isBot` on a
-- real Player is an error, not nil: Instances throw on unknown members.)
local function isBot(player)
	return typeof(player) ~= "Instance"
end

-- Put a (new) character in the player's chosen sanctuary (the start sanctuary if it isn't available)
local function placeInSanctuary(player)
	local character = player.Character
	if not (character and maze) then return end
	local sanctuary = objectives and objectives:CapturedSanctuary(player:GetAttribute("Sanctuary") or 1) or maze.sanctuaries[1]
	character:PivotTo(spawnSpot(player, sanctuary))
	SpeedCheck.moved(player)
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
-- and stopped by spawn-sanctuary barriers. Placed at its monster's start spot.
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
	SpeedCheck.moved(player)
end

local function respawn(player)
	if not player.Parent or not player:GetAttribute("Respawning") then return end
	player:SetAttribute("Respawning", nil)
	player:SetAttribute("RespawnBy", nil)
	player:LoadCharacter()     -- CharacterAdded (below) moves the new character into the sanctuary
	if isBot(player) then                                  -- (bots have no CharacterAdded)
		setUpSurvivorCharacter(player.Character)
		placeInSanctuary(player)
	end
end

-- THE KILL (timing: the monster's `kill`, MonsterAI.killFor): the stand-in lifts its victim
-- overhead and tears them apart; Fear Eater devours them and drops the body. It's drawn on each
-- player's computer (MonsterAnimate, HeroVisuals), where the monster's hands are: the victim's body
-- is shown in its grip, and when it's let go of (kill.RELEASE) players' computers carry on with
-- their own copy of it (the pieces, or the body on the floor). Here the victim is only frozen in
-- place, then removed just after it's let go of.
local function playKill(player, character, kill)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root) then return end
	player:SetAttribute("Seized", true)
	humanoid.PlatformStand = true                      -- no walking or balancing while held
	root.Anchored = true                               -- players' computers move it, for show only
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then part.CanCollide = false end
	end
	task.delay(kill.RELEASE + 0.3, function()
		player:SetAttribute("Seized", nil)
		if character.Parent then character:Destroy() end   -- the pieces are players' own copies by now
	end)
end

-- CRUSHED (a crushing wall): held where they stand, then the body is gone. Not by setting their
-- health to 0: that plays Roblox's default death sound (the "oof"). Players' computers draw it
-- (CrusherView: a burst of dust and a crack, and the body hidden at once). The hidden body stays
-- for Config.CRUSHED_LINGER seconds, so their camera stays on the shut walls before they're asked
-- where to respawn (onCaught waits the same).
local crushedEvent = Net.event("Crushed")            -- server -> everyone: (UserId, position)
local function playCrushed(player, character)
	local root = character:FindFirstChild("HumanoidRootPart")
	player:SetAttribute("Seized", true)
	if root then
		root.Anchored = true
		crushedEvent:FireAllClients(player.UserId, root.Position)
	end
	task.delay(Config.CRUSHED_LINGER, function()
		player:SetAttribute("Seized", nil)
		if character.Parent then character:Destroy() end
	end)
end

-- kill: the timing to use instead of the monster's own (the Minotaur's Charge tramples: its `trample`)
local function onCaught(player, monster, kill)
	if state ~= States.Playing then return end
	kill = kill or (monster and monster.kill)
	local killDone = kill and kill.DONE or Config.CRUSHED_LINGER
	respawnFrom[player] = os.clock() + killDone + RESPAWN_AFTER_KILL
	local lives = math.max(0, (player:GetAttribute("Lives") or 1) - 1)
	player:SetAttribute("Lives", lives)
	if not isBot(player) then caughtEvent:FireClient(player, lives) end
	local character = player.Character
	if monster and character then
		playKill(player, character, kill)
	elseif character then
		playCrushed(player, character)
	end

	-- Once the kill has played out: out of the match, or choose where to come back (if they
	-- don't choose in time, their last sanctuary is used)
	task.delay(killDone, function()
		if state ~= States.Playing or not player.Parent then return end
		if lives <= 0 then
			player:SetAttribute("Out", true)    -- out for the rest of the match: watches teammates
			return
		end
		player:SetAttribute("Respawning", true)
		player:SetAttribute("RespawnBy", workspace:GetServerTimeNow() + Config.RESPAWN_CHOICE_TIME)
		if isBot(player) then
			-- bots pick a captured sanctuary at random, straight away
			local sanctuaries = {}
			for _, sanctuary in maze.sanctuaries do
				if sanctuary.captured then table.insert(sanctuaries, sanctuary.id) end
			end
			player:SetAttribute("Sanctuary", sanctuaries[math.random(#sanctuaries)] or 1)
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

-- Can the monster side see this spot right now? The same sources as their fog (FogOfWar), checked
-- more simply (straight sight lines, a little extra range for the difference): every monster's
-- cone, wards and crushing walls. (Relics give the monster side no sight: the Maze Master knows
-- where they are, and watches them with wards.) Used by the AI Maze Master, and by AI monsters
-- (spottedBySide) to go after survivors their side can see.
local SIGHT_SLACK = 3
local function monsterSideSees(position, survivor)
	if objectives:IsSafe(position) then return false end   -- nobody sees into a sanctuary
	if survivor and Protection.encrypted(survivor) then return false end   -- (Kai's Encrypt hides him)
	local spot = { center = position }
	for _, monster in monsters do
		if monster.pos and monster.facing and objectives:CanSee(monster.pos, monster.facing, spot) then return true end
	end
	if wards and wards:Sees(position) then return true end
	for _, crusher in crushers and crushers.list or {} do
		if wards:clearLine(crusher.center, position, maze.S / 2 + Config.CRUSHER_VISION + SIGHT_SLACK) then return true end
	end
	return false
end

-- A survivor clicked to destroy a ward (WardEyes checks they're really next to it)
destroyWardEvent.OnServerEvent:Connect(function(player, wardId)
	if state ~= States.Playing or not wards or typeof(wardId) ~= "number" then return end
	if player:GetAttribute("Role") ~= Roles.Survivor or player:GetAttribute("Seized") then return end
	wards:StartDestroying(player, wardId)
	if wards:byId(wardId) and wards:byId(wardId).collector == player then Encrypt.stop(player) end   -- (interacting ends Encrypt)
end)

-- A monster player clicked to lunge (PlayerMonster checks it's allowed)
lungeEvent.OnServerEvent:Connect(function(player)
	if state ~= States.Playing then return end
	local monster = playerMonsters[player]
	if monster and monster:Lunge() then
		SpeedCheck.grant(player, Config.LUNGE_DISTANCE + 2)   -- (their computer carries them the lunge's distance)
	end
end)

-- The Maze Master used a tool (MazeMaster checks everything)
toolEvent.OnServerEvent:Connect(function(player, tool, target)
	if state ~= States.Playing or not mazeMasterTools or mazeMasterTools.player ~= player then return end
	if typeof(tool) ~= "string" then return end
	local ok, message = mazeMasterTools:Use(tool, target)
	toolResultEvent:FireClient(player, ok, message)
end)

-- Dev panel: force your role for the next match, end this match now and start another, or go to
-- the Sandbox (and, in it, its panel's actions: sandboxAction below)
local sandboxAction
devEvent.OnServerEvent:Connect(function(player, action, value, extra)
	if not Dev.isDev(player) then return end
	if action == "role" and (value == nil or (typeof(value) == "string" and Config.ROLE_SLOTS[value])) then
		player:SetAttribute("DevRole", value)
	elseif action == "restart" or action == "sandbox" then
		sandboxNext = action == "sandbox"
		-- end the match under way (from the lobby there's none: that would end the next one at once)
		restartRequested = state == States.Countdown or state == States.Playing
		startRequested = true          -- (straight into the next match, past the lobby)
	elseif action == "sandboxAction" and sandbox and state == States.Playing and typeof(value) == "string" then
		local ok, message = sandboxAction(player, value, extra)
		devEvent:FireClient(player, "sandboxResult", ok, message)
	end
end)

-- The lobby: a preferred role, and Start
lobbyEvent.OnServerEvent:Connect(function(player, action, value)
	if action == "prefer" and (value == nil or (typeof(value) == "string" and Config.ROLE_SLOTS[value])) then
		player:SetAttribute("PreferredRole", value)
	elseif action == "preferHero" and (value == nil or (typeof(value) == "string" and table.find(Heroes.survivorIds(), value))) then
		player:SetAttribute("PreferredHero", value)
	elseif action == "preferMonsterHero" and (value == nil or (typeof(value) == "string" and table.find(Heroes.monsterIds(), value))) then
		player:SetAttribute("PreferredMonsterHero", value)
	elseif action == "start" and state == States.Waiting then
		startRequested = true
	end
end)

-- A player clicked to collect a relic (Objectives checks they're really on it)
collectEvent.OnServerEvent:Connect(function(player, relicId)
	if state ~= States.Playing or not objectives or typeof(relicId) ~= "number" then return end
	if player:GetAttribute("Role") ~= Roles.Survivor or player:GetAttribute("Seized") then return end
	objectives:StartCollecting(player, relicId)
end)

-- A player picked a sanctuary. Check everything: never trust what a client sends.
chooseSpawnEvent.OnServerEvent:Connect(function(player, sanctuaryId)
	if state ~= States.Playing or not player:GetAttribute("Respawning") then return end
	if typeof(sanctuaryId) ~= "number" or not objectives or not objectives:CapturedSanctuary(sanctuaryId) then return end
	player:SetAttribute("Sanctuary", sanctuaryId)
	local wait = (respawnFrom[player] or 0) - os.clock()
	if wait > 0 then
		task.delay(wait, function()
			if state == States.Playing then respawn(player) end
		end)
	else
		respawn(player)
	end
end)

local function cleanUp()
	Abilities.stop()
	Encrypt.clear()
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
	if wards then wards:Destroy() end
	wards = nil
	if mazeMasterTools then mazeMasterTools:Destroy() end
	mazeMasterTools = nil
	mazeMasterAI = nil
	table.clear(respawnFrom)
	for _, player in Players:GetPlayers() do
		player.ReplicationFocus = nil          -- (the Maze Master's; see runCountdown)
		for _, name in { "Lives", "Out", "Respawning", "RespawnBy", "Sanctuary", "Killing", "RevealedUntil", "SlowUntil",
			"StunnedUntil", "CastingUntil", "PullAt", "PullTime", "PullFrom", "PullTo", "PullStyle",
			"DeflectUntil", "EncryptedUntil", "ScanFrom", "ScanDir", "ScanCone", "ScanRange", "ScanAt", "ScanUntil" } do
			player:SetAttribute(name, nil)
		end
	end
end

-- The free cell nearest the middle of the maze, for a monster to appear in
-- Where each monster appears. The first: the free cell nearest the middle. Each one after: as far
-- as possible from those already placed, but never near the start sanctuary (survivors spawn there).
local START_SANCTUARY_CLEARANCE = 6   -- cells
local function monsterStartCell(taken)
	local mid = math.ceil(maze.n / 2)
	local startSanctuary = maze.sanctuaries[1]
	local best, bestScore
	for x = 1, maze.n do
		for z = 1, maze.n do
			if objectives:IsBlocked(x, z) then continue end
			if math.abs(x - startSanctuary.x) + math.abs(z - startSanctuary.z) < START_SANCTUARY_CLEARANCE then continue end
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
	local function shuffle(list)
		for i = #list, 2, -1 do
			local j = math.random(i)
			list[i], list[j] = list[j], list[i]
		end
	end
	-- first a developer's forced role, then lobby preferences (in random order, so nobody always
	-- wins a contested slot), then the rest at random
	local preferring = {}
	for _, player in Players:GetPlayers() do
		local forced = Dev.isDev(player) and player:GetAttribute("DevRole")
		if forced and (free[forced] or 0) > 0 then
			roles[player] = forced
			free[forced] -= 1
		else
			table.insert(preferring, player)
		end
	end
	shuffle(preferring)
	for _, player in preferring do
		local wanted = player:GetAttribute("PreferredRole")
		if wanted and (free[wanted] or 0) > 0 then
			roles[player] = wanted
			free[wanted] -= 1
		else
			table.insert(rest, player)
		end
	end
	shuffle(rest)
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

-- A survivor's hero for this match: the one they'd like if nobody has it yet, otherwise the first
-- free one (Heroes.ORDER). Only once every survivor hero is taken do they repeat (the least used).
local function pickSurvivorHero(wanted)
	local ids = Heroes.survivorIds()
	local pick = nil
	if wanted and table.find(ids, wanted) and (heroesTaken[wanted] or 0) == 0 then pick = wanted end
	if not pick then
		for _, id in ids do
			if not pick or (heroesTaken[id] or 0) < (heroesTaken[pick] or 0) then pick = id end
		end
	end
	pick = pick or Config.DEFAULT_SURVIVOR_HERO
	heroesTaken[pick] = (heroesTaken[pick] or 0) + 1
	return pick
end

-- A monster's hero for this match, the same way: the one wanted if nobody has it yet, otherwise the
-- least used (Heroes.ORDER breaks ties), so a match's two monsters are different heroes.
local function pickMonsterHero(wanted)
	local ids = Heroes.monsterIds()
	local pick = nil
	if wanted and table.find(ids, wanted) and (monsterHeroesTaken[wanted] or 0) == 0 then pick = wanted end
	if not pick then
		for _, id in ids do
			if not pick or (monsterHeroesTaken[id] or 0) < (monsterHeroesTaken[pick] or 0) then pick = id end
		end
	end
	pick = pick or Config.DEFAULT_MONSTER_HERO
	if pick then monsterHeroesTaken[pick] = (monsterHeroesTaken[pick] or 0) + 1 end
	return pick
end

-- An AI monster (a match's empty monster slots, or one the Sandbox panel adds), with the next free
-- monster hero. Up to Config.AI_MONSTERS_CASTING a match whose hero has a Q/E brain (Fear Eater so
-- far) use those abilities too. Not yet in `monsters`, and not active.
local function addAIMonster(startCell)
	local hero = pickMonsterHero(nil)
	local casts = hero == "FearEater" and aiMonsterCount < Config.AI_MONSTERS_CASTING
	if casts then aiMonsterCount += 1 end
	return MonsterAI.new(maze, {
		onCatch = onCaught,
		hero = hero,
		castsAbilities = casts,
		isBlocked = function(x, z) return objectives:IsBlocked(x, z) end,
		startCell = startCell,
		pack = monsters,                        -- they spread out from each other when roaming
		-- can the monster side see this survivor right now (another monster, a ward, a crushing wall)?
		spottedBySide = function(survivor)
			local character = aliveCharacter(survivor)
			return character ~= nil and monsterSideSees(character.HumanoidRootPart.Position)
		end,
	})
end

-- A survivor bot, with its character in the start sanctuary (frozen until the match is playing)
local function addBot()
	botCount += 1
	local bot = SurvivorBot.new(maze, objectives, botCount)
	table.insert(bots, bot)
	bot:SetAttribute("Role", Roles.Survivor)
	bot:SetAttribute("Lives", sandbox and Sandbox.LIVES or Config.LIVES)
	bot:SetAttribute("Sanctuary", 1)
	bot:SetAttribute("Hero", pickSurvivorHero(nil))
	-- the first Config.AI_SURVIVORS_CASTING bots whose hero has a brain use their abilities (BotAbilities)
	local casting = 0
	for _, other in bots do
		if other.castsAbilities then casting += 1 end
	end
	if casting < Config.AI_SURVIVORS_CASTING and BotAbilities.has(bot:GetAttribute("Hero")) then
		bot.castsAbilities = true
		bot.wards = wards
	end
	bot:SetAttribute("BaseSpeed", state == States.Playing and Config.PLAYER_SPEED or 0)
	bot:LoadCharacter()
	setUpSurvivorCharacter(bot.Character)
	placeInSanctuary(bot)
	return bot
end

-- THE SANDBOX PANEL's actions (SandboxPanel on a developer's computer; only in a Sandbox match).
-- `at` is a point on the floor for the ones placed by clicking. -> ok, message
--   "bot" / "dummy" / "fearedDummy"  a survivor bot there: roaming, or held in place (a dummy:
--                                     it comes back there after being caught), or held and feared
--   "monster"                         an AI monster there (the least used monster hero)
--   "ward" / "falseRelic"             the Maze Master's ward or false relic there (their own rules)
--   "concepts"                        a copy of every model in ServerStorage.ModelConcepts (character
--                                     models being designed), in a row centred there, each gliding
--                                     round a small square to show every side; "clear" removes them
--   "fearAll"                         every survivor feared (as Instill Fear does)
--   "freeze"                          AI monsters stop / start again
--   "ready"                           your abilities are ready again
--   "lives"                           your lives back (and back in the start sanctuary if you were out)
--   "clear"                           every bot and AI monster gone
--   "hero"                            switch to the next survivor hero (a survivor) or monster hero
--                                     (a monster: a new body where you stand), abilities ready
sandboxAction = function(player, action, at)
	local spot = typeof(at) == "Vector3" and Vector3.new(at.X, maze.floorY, at.Z) or nil
	local x, z = nil, nil
	if spot then x, z = objectives:CellOf(spot) end
	local fearDef = Heroes.get("FearEater").abilities.Secondary
	if action == "bot" or action == "dummy" or action == "fearedDummy" then
		if not x then return false, "Click inside the maze" end
		local bot = addBot()
		local cf = CFrame.new(spot + Vector3.new(0, 3, 0))
		if bot.Character then bot.Character:PivotTo(cf) end
		if action ~= "bot" then bot.heldAt = cf end
		if action == "fearedDummy" then Fear.apply(bot, { fearTime = 3600, fearSlow = fearDef.fearSlow }) end
		return true, bot.DisplayName
	elseif action == "monster" then
		if not x or objectives:IsBlocked(x, z) then return false, "Not in a sanctuary" end
		table.clear(monsterHeroesTaken)        -- (the least used among the monsters here now: yours too)
		for _, m in monsters do
			if m.hero then monsterHeroesTaken[m.hero] = (monsterHeroesTaken[m.hero] or 0) + 1 end
		end
		local monster = addAIMonster({ x, z })
		monster.active = true
		table.insert(monsters, monster)
		return true, "AI " .. (Heroes.get(monster.hero) and Heroes.get(monster.hero).name or "monster")
	elseif action == "ward" then
		local ok = x ~= nil and wards:Add(x, z) ~= nil
		return ok, ok and "Ward" or "Can't put a ward there"
	elseif action == "falseRelic" then
		local ok = x ~= nil and objectives:AddFalseRelic(x, z) ~= nil
		return ok, ok and "False relic" or "Can't put a false relic there (needs 2-3 ways out)"
	elseif action == "concepts" then
		local source = ServerStorage:FindFirstChild("ModelConcepts")
		local models = source and source:GetChildren() or {}
		table.sort(models, function(m1, m2) return m1.Name < m2.Name end)   -- (A, B, C... left to right)
		if not spot then return false, "Click the floor" end
		if #models == 0 then return false, "No models in ServerStorage.ModelConcepts" end
		local holder = workspace:FindFirstChild("SandboxConcepts") or Instance.new("Folder")
		holder.Name = "SandboxConcepts"
		holder.Parent = workspace
		local toCamera = Vector3.new(Config.CAMERA_DIRECTION.X, 0, Config.CAMERA_DIRECTION.Z).Unit
		local across = Vector3.new(-toCamera.Z, 0, toCamera.X)
		local GAP, SIDE, SPEED, TURN = 9, 6, 8, 6   -- studs between, the square walked (studs), studs/s, turn rate
		local widths, total = {}, 0
		for i, model in models do
			local _, size = model:GetBoundingBox()
			widths[i] = math.max(size.X, size.Z)
			total += widths[i] + (i > 1 and GAP or 0)
		end
		-- each walks (glides: no animation) round a small square about its place in the row, turning to
		-- face the way it goes, so it's seen from every side
		local corners = {
			-across - toCamera, across - toCamera, across + toCamera, -across + toCamera,
		}
		local walkers = {}
		local offset = -total / 2
		for i, model in models do
			local copy = model:Clone()
			for _, part in copy:GetDescendants() do
				if part:IsA("BasePart") then part.Anchored, part.CanCollide, part.CanQuery = true, false, false end
			end
			copy.Parent = holder
			local box, size = copy:GetBoundingBox()
			-- a concept's front is its bounding box's -Z (LookVector), as models are made facing
			table.insert(walkers, {
				model = copy,
				boxToPivot = box:ToObjectSpace(copy:GetPivot()),
				centre = spot + across * (offset + widths[i] / 2) + Vector3.new(0, size.Y / 2, 0),
				walked = (i - 1) * SIDE * 0.7,   -- not all in step
				look = toCamera,
			})
			offset += widths[i] + GAP
		end
		local connection
		connection = RunService.Heartbeat:Connect(function(dt)
			if not holder.Parent then connection:Disconnect() return end
			for _, w in walkers do
				if w.model.Parent ~= holder then continue end
				w.walked += SPEED * dt
				local along = w.walked / SIDE
				local edge = math.floor(along) % 4
				local from, to = corners[edge + 1], corners[(edge + 1) % 4 + 1]
				local pos = w.centre + from:Lerp(to, along % 1) * (SIDE / 2)
				local heading = (to - from).Unit
				w.look = w.look:Lerp(heading, math.min(1, TURN * dt)).Unit
				w.model:PivotTo(CFrame.lookAt(pos, pos + w.look) * w.boxToPivot)
			end
		end)
		return true, ("%d concept%s"):format(#models, #models == 1 and "" or "s")
	elseif action == "fearAll" then
		for _, survivor in survivorsInMatch() do Fear.apply(survivor, fearDef) end
		return true, "Feared"
	elseif action == "freeze" then
		local frozen = false
		for _, monster in monsters do
			if not playerMonsters[monster.player] then
				monster.active = not monster.active
				frozen = not monster.active
			end
		end
		return true, frozen and "AI monsters frozen" or "AI monsters moving"
	elseif action == "ready" then
		Abilities.resetCooldowns(player)
		return true, "Abilities ready"
	elseif action == "lives" then
		if player:GetAttribute("Role") ~= Roles.Survivor then return false, "Survivors only" end
		player:SetAttribute("Lives", Sandbox.LIVES)
		if player:GetAttribute("Out") then
			player:SetAttribute("Out", nil)
			player:SetAttribute("Respawning", true)
			player:SetAttribute("Sanctuary", 1)
			respawn(player)
		end
		return true, "Lives back"
	elseif action == "hero" and player:GetAttribute("Role") == Roles.Monster then
		-- a monster: the next monster hero, a new body where they stand
		local old = playerMonsters[player]
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not old or not root then return false, "No monster to change" end
		local ids = Heroes.monsterIds()
		local next = ids[(table.find(ids, player:GetAttribute("Hero")) or 0) % #ids + 1]
		local x, z = objectives:CellOf(root.Position)
		local monster = PlayerMonster.new(player, maze, { onCatch = onCaught, startCell = { x or 1, z or 1 }, hero = next,
			isSafe = function(p) return objectives:IsSafe(p) end })
		monster.active = true
		monster.placed = player.Character        -- (it stays where it is)
		table.remove(monsters, table.find(monsters, old) or #monsters + 1)
		old:Destroy()
		playerMonsters[player] = monster
		table.insert(monsters, monster)
		player:SetAttribute("Hero", next)
		applySpeed(player)
		Abilities.resetCooldowns(player)
		return true, "You're " .. Heroes.get(next).name
	elseif action == "hero" then
		if player:GetAttribute("Role") ~= Roles.Survivor then return false, "Survivors and monsters only" end
		local ids = Heroes.survivorIds()
		local next = ids[(table.find(ids, player:GetAttribute("Hero")) or 0) % #ids + 1]
		Encrypt.stop(player)
		player:SetAttribute("Hero", next)
		Abilities.resetCooldowns(player)
		return true, "You're " .. Heroes.get(next).name
	elseif action == "clear" then
		for i = #monsters, 1, -1 do
			local monster = monsters[i]
			if not playerMonsters[monster.player] then
				monster:Destroy()
				table.remove(monsters, i)
			end
		end
		for _, bot in bots do bot:Destroy() end
		table.clear(bots)
		local concepts = workspace:FindFirstChild("SandboxConcepts")
		if concepts then concepts:Destroy() end
		return true, "Cleared"
	end
	return false, "Unknown"
end

local function formatTime(seconds)
	seconds = math.max(0, math.floor(seconds))
	return ("%d:%02d"):format(seconds // 60, seconds % 60)
end

---------------------------------------------------------------- the states
local function runWaiting()
	setState(States.Waiting, nil, "")
	while not (startRequested and #Players:GetPlayers() >= Config.MIN_PLAYERS) do
		task.wait(0.2)
	end
	startRequested = false
end

local function runCountdown()
	sandbox = sandboxNext
	status:SetAttribute("Sandbox", sandbox or nil)
	local concepts = workspace:FindFirstChild("SandboxConcepts")   -- (the Sandbox panel's "Concepts")
	if concepts then concepts:Destroy() end
	botCount, aiMonsterCount = 0, 0
	table.clear(heroesTaken)
	table.clear(monsterHeroesTaken)
	maze = MazeBuilder.build(sandbox and { layout = Sandbox.layout() } or {
		sanctuaries = Config.SANCTUARIES,
		sanctuarySpacing = Config.SANCTUARY_SPACING,
		sanctuarySize = Config.SANCTUARY_SIZE,
		startSanctuarySize = Config.START_SANCTUARY_SIZE,
		sanctuaryExitSpacing = Config.SANCTUARY_EXIT_SPACING,
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
		onInteract = function(player) Encrypt.stop(player) end,   -- (interacting ends Kai's Encrypt)
		onCapture = function(player, sanctuary)
			noticeEvent:FireAllClients(("%s captured a sanctuary!"):format(player.DisplayName))
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
			if not isBot(player) then falseRelicEvent:FireClient(player) end
		end,
	})

	-- spawn-sanctuary barriers become solid for monster players
	for _, sanctuary in maze.sanctuaries do
		for _, ward in sanctuary.wards do
			ward.CanCollide = true
			ward.CollisionGroup = "Wards"
		end
	end

	-- Roles, then the monsters: one per monster player, AI for the empty slots
	local roles = assignRoles()
	local monsterPlayers, mazeMaster = {}, nil
	local monsterHeroOf = {}
	for player, role in roles do
		if role == Roles.Monster then table.insert(monsterPlayers, player) end
		if role == Roles.MazeMaster then mazeMaster = player end
	end
	-- (the Sandbox starts with only its players: no AI monsters)
	local starts = {}
	for i = 1, sandbox and #monsterPlayers or math.max(Config.MONSTER_COUNT, #monsterPlayers) do
		local startCell = monsterStartCell(starts)
		table.insert(starts, startCell)
		local player = monsterPlayers[i]
		local monster
		if player then
			monsterHeroOf[player] = pickMonsterHero(player:GetAttribute("PreferredMonsterHero"))
			monster = PlayerMonster.new(player, maze, { onCatch = onCaught, startCell = startCell,
				hero = monsterHeroOf[player],
				isSafe = function(p) return objectives:IsSafe(p) end })
			playerMonsters[player] = monster
		else
			monster = addAIMonster(startCell)
		end
		monster.active = false
		table.insert(monsters, monster)
	end
	-- with no Maze Master player, an AI Maze Master uses the tools (or, with that off, the old
	-- random door AI works the doors)
	doors = Doors.new(maze, { monsters = monsters, survivors = survivorsInMatch,
		ai = mazeMaster == nil and not Config.MAZE_MASTER_AI, bots = function() return bots end })
	crushers = Crushers.new(maze, { onCrush = function(player) onCaught(player, nil) end, survivors = survivorsInMatch,
		monsters = monsters })
	wards = WardEyes.new(maze, objectives)
	if mazeMaster or Config.MAZE_MASTER_AI then
		mazeMasterTools = MazeMaster.new(mazeMaster, { maze = maze, doors = doors, crushers = crushers, objectives = objectives,
			wards = wards })
	end
	if not mazeMaster and Config.MAZE_MASTER_AI and not sandbox then
		mazeMasterAI = MazeMasterAI.new(mazeMasterTools, { maze = maze, doors = doors, crushers = crushers, wards = wards,
			objectives = objectives, monsters = monsters, survivors = survivorsInMatch, sees = monsterSideSees })
	end

	-- survivors' heroes: people first (those with a preference first, in random order), then bots
	local heroOf = {}
	local preferring, others = {}, {}
	for player, role in roles do
		if role == Roles.Survivor then
			table.insert(player:GetAttribute("PreferredHero") and preferring or others, player)
		end
	end
	for _, list in { preferring, others } do
		for i = #list, 2, -1 do
			local j = math.random(i)
			list[i], list[j] = list[j], list[i]
		end
	end
	local humanSurvivors = table.move(others, 1, #others, #preferring + 1, preferring)
	for _, player in humanSurvivors do heroOf[player] = pickSurvivorHero(player:GetAttribute("PreferredHero")) end

	-- survivor bots for the empty survivor slots (none in the Sandbox: its panel adds them)
	if Config.SURVIVOR_BOTS and not sandbox then
		local humans = 0
		for _, role in roles do if role == Roles.Survivor then humans += 1 end end
		for _ = 1, math.max(0, Config.ROLE_SLOTS.Survivor - humans) do addBot() end
	end
	if sandbox then objectives:AddFalseRelic(Sandbox.FALSE_RELIC[1], Sandbox.FALSE_RELIC[2]) end

	setState(States.Countdown, Config.COUNTDOWN)
	for player, role in roles do
		player:SetAttribute("Role", role)
		player:SetAttribute("Lives", role == Roles.Survivor and (sandbox and Sandbox.LIVES or Config.LIVES) or nil)
		player:SetAttribute("Out", nil)
		player:SetAttribute("Respawning", nil)
		player:SetAttribute("Killing", nil)
		player:SetAttribute("Sanctuary", role == Roles.Survivor and 1 or nil)
		player:SetAttribute("Hero", (role == Roles.Survivor and heroOf[player])
			or (role == Roles.Monster and monsterHeroOf[player]) or nil)
		if role == Roles.MazeMaster then
			if player.Character then player.Character:Destroy() end   -- no body in the maze
			player.Character = nil
			-- With streaming on, a player's computer only gets what's near their character. The
			-- Maze Master has none, so give them a spot to stream around instead: the middle of the
			-- maze (the streaming radius covers the whole map from there). Without it, survivors'
			-- bodies never reach their computer, so they can't be seen.
			local focus = Instance.new("Part")
			focus.Name = "MazeMasterFocus"
			focus.Anchored = true
			focus.CanCollide, focus.CanQuery, focus.CanTouch = false, false, false
			focus.Transparency = 1
			focus.Size = Vector3.one
			focus.Position = Vector3.new(0, maze.floorY, 0)
			focus.Parent = maze.model
			player.ReplicationFocus = focus
		else
			task.spawn(player.LoadCharacter, player)  -- a fresh character (start sanctuary, or monster spot)
		end
	end
	task.wait(Config.COUNTDOWN)
end

-- Returns "survivors", "time", "caught", or nil if the match was abandoned (everyone left)
local function runPlaying()
	setState(States.Playing, not sandbox and Config.MATCH_TIME or nil)   -- (the Sandbox has no timer, and never ends)
	local endsAt = sandbox and math.huge or os.clock() + Config.MATCH_TIME
	for _, monster in monsters do monster.active = true end
	for _, bot in bots do bot:SetAttribute("BaseSpeed", Config.PLAYER_SPEED) end
	doors.running = true
	if mazeMasterTools then mazeMasterTools.active = true end
	if mazeMasterAI then mazeMasterAI:Start() end
	Abilities.start({ maze = maze, objectives = objectives, monsters = monsters, survivors = survivorsInMatch,
		stun = function(monster, seconds) if monster.Stun then monster:Stun(seconds) end end,
		monsterOf = function(player) return playerMonsters[player] end,
		doors = doors, crushers = crushers, wards = wards })
	for _, player in Players:GetPlayers() do applySpeed(player) end

	local hadSurvivors = #survivorsInMatch() > 0
	while true do
		if #Players:GetPlayers() < Config.MIN_PLAYERS or restartRequested then return nil end
		local collectors = {}
		for _, player in survivorsInMatch() do
			if not player:GetAttribute("Seized") then table.insert(collectors, player) end
		end
		objectives:Update(collectors)
		wards:Update(collectors)
		objectives:UpdateMonsterSight(monsters, wards)
		if not sandbox then
			if objectives.collected >= Config.RELICS_NEEDED then return "survivors" end
			if os.clock() >= endsAt then return "time" end
			if #survivorsInMatch() == 0 and hadSurvivors then return "caught" end   -- (none at all: a test, play on)
		end
		task.wait(0.1)
	end
end

local function runResults(outcome, elapsed)
	Abilities.stop()
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
	player:SetAttribute("Dev", Dev.isDev(player))   -- (players' computers show the dev panels from this)
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
				task.defer(placeInSanctuary, player)
			end
		end
	end)

	-- Joining mid-match: you're a survivor with full lives, in the start sanctuary
	if state == States.Countdown or state == States.Playing then
		player:SetAttribute("Role", Roles.Survivor)
		player:SetAttribute("Lives", Config.LIVES)
		player:SetAttribute("Sanctuary", 1)
		player:SetAttribute("Hero", pickSurvivorHero(player:GetAttribute("PreferredHero")))
	end
	player:LoadCharacter()
end

Players.PlayerRemoving:Connect(function(player)
	respawnFrom[player] = nil
end)

---------------------------------------------------------------- test hook (Studio only)
-- Tools that run code in Studio get their own copy of this module, so they reach the match
-- through ServerStorage.MatchTest:Invoke(action, ...):
--   "crushers"              -> { [id] = { center, state } }
--   "crush", id             -> set that crusher off (no dark mana needed)
--   "falseRelic", x, z      -> place a false relic in cell (x, z); -> its id, or nil
--   "monsters", on[, "ai"]  -> switch every monster (or only the AI ones) on or off (off: they stand still and catch nobody)
--   "ward", x, z            -> place a ward in cell (x, z) (no Maze Master needed); -> its id, or nil
--   "sees", position        -> can the monster side see that spot right now?
--   "reveal", userId, secs  -> reveal that survivor to the monster side (as a false relic does)
--   "teleport", player, cf  -> move a player's character there (past the speed check)
--   "ability", userId, slot, aim -> use a hero ability as that survivor (player or bot): -> ok, message
--   "bot", userId, cframe   -> hold that survivor bot at cframe (nil lets it go)
if RunService:IsStudio() then
	local hook = Instance.new("BindableFunction")
	hook.Name = "MatchTest"
	hook.OnInvoke = function(action, a, b, ...)
		if action == "crushers" and crushers then
			local out = {}
			for id, c in crushers.list do out[id] = { center = c.center, state = c.state, x = c.x, z = c.z, along = c.along } end
			return out
		elseif action == "crush" and crushers then
			return crushers:Trigger(a)
		elseif action == "monsters" then
			for _, monster in monsters do
				if b ~= "ai" or not playerMonsters[monster.player] then monster.active = a == true end
			end
			return true
		elseif action == "ward" and wards then
			local ward = wards:Add(a, b)
			return ward and ward.id
		elseif action == "teleport" and typeof(a) == "Instance" and a.Character then
			a.Character:PivotTo(b)
			SpeedCheck.moved(a)
			return true
		elseif action == "monsterAbility" and monsters[a] then   -- an AI monster (by number) uses an ability
			local monster = monsters[a]
			if monster.Devour and not playerMonsters[monster.player] then
				return { Abilities.useMonster(monster, b, select(1, ...)) }
			end
			return { false, "not an AI monster" }
		elseif action == "ability" then
			for _, survivor in survivorsInMatch() do
				if survivor.UserId == a then return { Abilities.use(survivor, b, select(1, ...)) } end
			end
			return { false, "no such survivor" }
		elseif action == "reveal" then
			for _, survivor in survivorsInMatch() do
				if survivor.UserId == a then
					survivor:SetAttribute("RevealedUntil", workspace:GetServerTimeNow() + (b or 5))
					return true
				end
			end
			return false
		elseif action == "sees" and maze then
			return monsterSideSees(a)
		elseif action == "attr" then   -- set an attribute on a survivor (player or bot) by UserId
			for _, survivor in survivorsInMatch() do
				if survivor.UserId == a then
					survivor:SetAttribute(b, (select(1, ...)))
					return true
				end
			end
			return false
		elseif action == "bot" then
			for _, bot in bots do
				if bot.UserId == a then bot.heldAt = b return true end
			end
			return false
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
	-- Each system runs on its own (safely), so an error in one can't stop the rest: it's reported
	-- (once every few seconds per system) and, in Studio, kept in the "LastError" attribute on
	-- ReplicatedStorage.Match.
	local reportedAt = {}
	local function safely(name, fn, ...)
		local ok, err = xpcall(fn, debug.traceback, ...)
		if not ok and os.clock() - (reportedAt[name] or -math.huge) > 5 then
			reportedAt[name] = os.clock()
			warn(("Match: %s failed: %s"):format(name, tostring(err)))
			if RunService:IsStudio() then status:SetAttribute("LastError", name .. ": " .. tostring(err):sub(1, 400)) end
		end
	end
	RunService.Heartbeat:Connect(function(dt)
		safely("speed check", SpeedCheck.step, dt)
		safely("pulls", Pull.step)
		safely("encrypt", Encrypt.step)
		if doors then safely("doors", doors.Step, doors, dt) end
		if crushers then safely("crushers", crushers.Step, crushers) end
		if mazeMasterTools then safely("Maze Master tools", mazeMasterTools.Step, mazeMasterTools, dt) end
		if mazeMasterAI then safely("Maze Master AI", mazeMasterAI.Step, mazeMasterAI, dt) end
		for _, bot in bots do safely("survivor bot", bot.Step, bot, dt, monsters) end
		if #monsters == 0 then return end
		local targets = huntable()
		for _, monster in monsters do safely("monster", monster.Step, monster, dt, targets) end
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
