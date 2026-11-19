-- Plays the game's sound effects on this player's computer (the sounds themselves are listed in
-- ReplicatedStorage.Sounds). Nothing here changes the game: it watches what the server publishes
-- and plays a sound when something happens.
--
--   relic being collected  - a hum from the relic, rising in pitch as the bar fills
--   relic collected        - a chime (everyone)
--   spawn room captured    - a chime (everyone)
--   monster starts a chase - a roar from the monster
--   monster kill           - a roar as it lifts its victim, their scream, then cracking bones at the rip
--   countdown              - a tick each second
--   match over             - a win or lose sting, depending on your team
--   background music       - always, on a loop
--
-- Sounds that come from somewhere (the relic, the monster) are placed there in the world, so
-- they get quieter with distance and come from the right side.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Sounds = require(ReplicatedStorage:WaitForChild("Sounds"))

local player = Players.LocalPlayer
local match = ReplicatedStorage:WaitForChild("Match")
local KILL_RIP = 1.7   -- seconds from catch to the rip (MonsterAI.KILL.RIP on the server)
local SCREAM_LENGTH = 1.2  -- seconds: the KillScream sound's length, so it ends at the rip

local function newSound(def, parent)
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. def.id
	s.Volume = def.volume or 0.5
	s.PlaybackSpeed = def.speed or 1
	s.Looped = def.looped or false
	if def.range then
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = 10
		s.RollOffMaxDistance = def.range
	end
	s.Parent = parent
	return s
end

-- Play once and clean up (cut short after def.stopAfter seconds, if set)
local function playOnce(def, parent)
	local s = newSound(def, parent)
	s:Play()
	task.delay(def.stopAfter or 10, function()
		if s.Parent then s:Destroy() end
	end)
	s.Ended:Once(function() s:Destroy() end)
	return s
end

local function play2D(def) return playOnce(def, SoundService) end

-- A sound at a point in the world (for things that may disappear while the sound plays)
local function playAt(def, position)
	local a = Instance.new("Attachment")
	a.WorldPosition = position
	a.Parent = workspace.Terrain
	local s = playOnce(def, a)
	s.Destroying:Once(function() a:Destroy() end)
end

---------------------------------------------------------------- relics and spawn rooms
local hums = {}        -- [relic info] = looping Sound while someone collects it
local seen = {}        -- [info] = last known Collected/Captured, so we only react to changes

local function updateObjectives()
	local relics = match:FindFirstChild("Relics")
	local rooms = match:FindFirstChild("SpawnRooms")
	local maze = workspace:FindFirstChild("Maze")
	local now = workspace:GetServerTimeNow()

	if relics then
		for _, info in relics:GetChildren() do
			-- the hum while it's being collected
			local since = info:GetAttribute("CollectSince")
			local relicModel = maze and maze:FindFirstChild("Relic" .. tostring(info:GetAttribute("Id")))
			local gem = relicModel and relicModel:FindFirstChild("Gem")
			local hum = hums[info]
			if since and gem then
				if not hum or hum.Parent ~= gem then
					if hum then hum:Destroy() end
					hum = newSound(Sounds.RelicHum, gem)
					hum:Play()
					hums[info] = hum
				end
				local progress = math.clamp((now - since) / Config.RELIC_COLLECT_TIME, 0, 1)
				hum.PlaybackSpeed = 0.8 + 0.6 * progress
			elseif hum then
				hum:Destroy()
				hums[info] = nil
			end
			-- the chime when it's collected
			local collected = info:GetAttribute("Collected") == true
			if seen[info] == false and collected then play2D(Sounds.RelicCollected) end
			seen[info] = collected
		end
	end
	if rooms then
		for _, info in rooms:GetChildren() do
			local captured = info:GetAttribute("Captured") == true
			if seen[info] == false and captured then play2D(Sounds.RoomCaptured) end
			seen[info] = captured
		end
	end
	for info, hum in hums do
		if not info.Parent then hum:Destroy() hums[info] = nil end
	end
	for info in seen do
		if not info.Parent then seen[info] = nil end
	end
end

---------------------------------------------------------------- the monster
local monsterState = {}   -- [model] = { mode, killStart }

local function monsterHead(model)
	local head = model:FindFirstChild("Head", true)
	return head and head.Position or model:GetPivot().Position
end

local function updateMonsters()
	for _, model in CollectionService:GetTagged("Monster") do
		local st = monsterState[model]
		if not st then
			st = { mode = model:GetAttribute("Mode"), killStart = model:GetAttribute("KillStart") }
			monsterState[model] = st
		end
		local mode = model:GetAttribute("Mode")
		if mode == "chase" and st.mode ~= "chase" then playAt(Sounds.MonsterRoar, monsterHead(model)) end
		st.mode = mode

		local killStart = model:GetAttribute("KillStart")
		if killStart and killStart ~= st.killStart then
			playAt(Sounds.KillGrab, monsterHead(model))
			local function at(seconds, fn)   -- run fn this many seconds after the catch
				task.delay(math.max(0, killStart + seconds - workspace:GetServerTimeNow()), function()
					if model.Parent then fn(monsterHead(model) + Vector3.new(0, 3, 0)) end
				end)
			end
			-- the scream starts while they're being lifted and ends right at the rip
			at(KILL_RIP - SCREAM_LENGTH, function(pos) playAt(Sounds.KillScream, pos) end)
			at(KILL_RIP, function(pos) playAt(Sounds.KillCrack, pos) end)
		end
		st.killStart = killStart
	end
	for model in monsterState do
		if not model.Parent then monsterState[model] = nil end
	end
end

---------------------------------------------------------------- match flow
local lastTick = nil
local lastState = nil

local function updateMatch()
	local state = match:GetAttribute("State")
	if state == Config.States.Countdown then
		local endsAt = match:GetAttribute("EndsAt")
		local left = endsAt and math.ceil(endsAt - workspace:GetServerTimeNow())
		if left and left >= 1 and left ~= lastTick then
			lastTick = left
			play2D(Sounds.CountdownTick)
		end
	else
		lastTick = nil
	end
	if state == Config.States.Results and lastState ~= state then
		local winner = match:GetAttribute("Winner")
		if winner then
			play2D(winner == player:GetAttribute("Role") and Sounds.Win or Sounds.Lose)
		end
	end
	lastState = state
end

-- Background music: one looping track, always playing
local music = newSound(Sounds.Music, SoundService)
music.Name = "Music"
music:Play()

RunService.Heartbeat:Connect(function()
	updateObjectives()
	updateMonsters()
	updateMatch()
end)

-- WHERE YOU HEAR FROM. Roblox normally hears from the camera, but ours hangs 210 studs away, far
-- enough that every sound placed in the world faded to nothing. So listen from what the camera
-- is looking at (your character, or the teammate you're watching), facing the way the camera
-- faces, so sounds on the left of the screen come from the left.
local camera = workspace.CurrentCamera
RunService:BindToRenderStep("SoundListener", Enum.RenderPriority.Camera.Value + 3, function()
	SoundService:SetListener(Enum.ListenerType.CFrame, CFrame.new(camera.Focus.Position) * camera.CFrame.Rotation)
end)
