-- HERO ABILITIES on the server: checking each use, keeping cooldowns, and carrying them out.
-- The heroes and their numbers are in ReplicatedStorage.Heroes.
--
--   Abilities.start(match)   -- a match begins: match = { maze, objectives, monsters, survivors = fn,
--                            --   stun = fn(monster, seconds) }
--   Abilities.stop()         -- the match is over
--
-- A player's computer sends "UseAbility" (slot, aim): slot is "Primary" / "Secondary" / "Ultimate",
-- aim the flat direction they face. Checked here: a match is on, they're a survivor whose hero has
-- that slot, alive, not held or stunned or pulled, and the cooldown is over. Cooldowns are kept
-- here and published as "AbilityReady<Slot>" (server time) on the player, for the ability bar.
--
-- Everyone's computer is told what happened ("AbilityFx": kind, the user's UserId, details) so it
-- can draw it (HeroEffects); Treasure hunt's find goes only to survivors.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Config)
local Net = require(ReplicatedStorage.Net)
local Heroes = require(ReplicatedStorage.Heroes)
local Movement = require(ReplicatedStorage.Movement)
local Pull = require(ServerStorage.Pull)

local useEvent = Net.event("UseAbility")     -- player -> server: (slot, aim)
local fxEvent = Net.event("AbilityFx")       -- server -> players: (kind, userId, ...)

local Abilities = {}

local match = nil          -- the current match's parts (see Abilities.start)
local readyAt = {}         -- [player][slot] = os.clock() when it can be used again

local EYE_HEIGHT = 3       -- the whip travels at this height above the floor

local function rootOf(who)
	local character = who.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and humanoid and humanoid.Health > 0 then return root end
	return nil
end

function Abilities.start(parts)
	match = parts
	table.clear(readyAt)
	match.rayParams = RaycastParams.new()
	match.rayParams.FilterType = Enum.RaycastFilterType.Include
	match.rayParams.FilterDescendantsInstances = { parts.maze.model }
end

function Abilities.stop()
	match = nil
	for _, player in Players:GetPlayers() do
		for _, slot in Heroes.SLOTS do player:SetAttribute("AbilityReady" .. slot, nil) end
	end
	table.clear(readyAt)
end

local function setCooldown(user, slot, seconds)
	readyAt[user] = readyAt[user] or {}
	readyAt[user][slot] = os.clock() + seconds
	user:SetAttribute("AbilityReady" .. slot, workspace:GetServerTimeNow() + seconds)
end

-- Can't go into a spawn room: a monster pulled toward someone inside one stops at the edge
local function stopOutsideRooms(from, to)
	local objectives = match.objectives
	local steps = math.ceil((to - from).Magnitude / 1)
	local last = from
	for i = 1, steps do
		local p = from:Lerp(to, i / steps)
		if objectives:IsSafe(p) then return last end
		last = p
	end
	return to
end

---------------------------------------------------------------- Sara
local handlers = {}

-- WHIP: the first thing along the lash, out to its range
function handlers.Whip(user, root, aim, def)
	local maze = match.maze
	local origin = Vector3.new(root.Position.X, maze.floorY + EYE_HEIGHT, root.Position.Z)
	local wall = workspace:Raycast(origin, aim * def.range, match.rayParams)
	local reach = wall and wall.Distance or def.range
	-- where along the lash something flat at `p` sits (nil = not on it)
	local function along(p)
		local offset = Vector3.new(p.X - origin.X, 0, p.Z - origin.Z)
		local t = offset:Dot(aim)
		if t <= 0.5 or t > reach then return nil end
		if (offset - aim * t).Magnitude > def.hitRadius then return nil end
		return t
	end
	local hit = { kind = wall and "wall" or "miss", t = reach }
	local function consider(kind, t, thing)
		if t and t < hit.t then hit = { kind = kind, t = t, thing = thing } end
	end
	for _, monster in match.monsters do
		if monster.pos then consider("monster", along(monster.pos), monster) end
	end
	for _, other in match.survivors() do
		local otherRoot = other ~= user and not other:GetAttribute("Seized") and rootOf(other)
		if otherRoot then consider("ally", along(otherRoot.Position), other) end
	end
	for _, relic in match.maze.relics do
		if not relic.collected then consider("relic", along(relic.center), relic) end
	end
	for _, relic in match.objectives.fakes do
		consider("relic", along(relic.center), relic)
	end

	local tip = origin + aim * hit.t
	fxEvent:FireAllClients("Whip", user.UserId, Vector3.new(tip.X, maze.floorY, tip.Z), hit.kind)
	-- what happens once the lash gets there
	task.delay(hit.t / def.speed, function()
		if not match or not rootOf(user) then return end
		local here = rootOf(user).Position
		if hit.kind == "wall" or hit.kind == "relic" then
			-- you're pulled to it (stopping short of the wall, or beside the relic)
			local stopShort = hit.kind == "wall" and 2.5 or 3.5
			Pull.character(user, tip - aim * stopShort, def.pullSpeed)
		elseif hit.kind == "ally" then
			local ally = hit.thing
			Pull.character(ally, here + aim * 3, def.pullSpeed)
		elseif hit.kind == "monster" then
			local monster = hit.thing
			local to = stopOutsideRooms(monster.pos, Vector3.new(here.X, maze.floorY, here.Z) + aim * 5)
			local seconds = monster:Pull(to, def.pullSpeed) or 0
			match.stun(monster, seconds + def.stun)        -- stunned while dragged, then for def.stun
		end
	end)
	return true
end

-- TREASURE HUNT: the nearest relic the survivors haven't spotted, within range
function handlers.TreasureHunt(user, root, aim, def)
	local best, bestDist
	local function consider(relic)
		if relic.collected or relic.discovered then return end
		local d = ((relic.center - root.Position) * Vector3.new(1, 0, 1)).Magnitude
		if d <= def.range and (not bestDist or d < bestDist) then best, bestDist = relic, d end
	end
	for _, relic in match.maze.relics do consider(relic) end
	for _, relic in match.objectives.fakes do consider(relic) end
	if not best then return false, "No hidden relics nearby" end
	match.objectives:Discover(best)
	for _, other in Players:GetPlayers() do
		if other:GetAttribute("Role") == Config.Roles.Survivor then
			fxEvent:FireClient(other, "TreasureHunt", user.UserId, best.center)
		end
	end
	return true
end

-- FLOURISH: a wind-up standing still ("CastingUntil": Movement.held), then every monster in range
-- of where she stands is stunned. Caught (or out of the match) before it lands: nothing.
function handlers.Flourish(user, root, aim, def)
	user:SetAttribute("CastingUntil", workspace:GetServerTimeNow() + def.castTime)
	fxEvent:FireAllClients("Flourish", user.UserId)
	local thisMatch = match
	task.delay(def.castTime, function()
		user:SetAttribute("CastingUntil", nil)
		local now = rootOf(user)
		if match ~= thisMatch or not now or user:GetAttribute("Seized") then return end
		for _, monster in match.monsters do
			if monster.pos and ((monster.pos - now.Position) * Vector3.new(1, 0, 1)).Magnitude <= def.range then
				match.stun(monster, def.stun)
			end
		end
	end)
	return true
end

---------------------------------------------------------------- using one
local resultEvent = Net.event("AbilityResult")   -- server -> player: (slot, message) when a use fails

-- user: a player (or, later, a bot). Returns ok, message.
function Abilities.use(user, slot, aim)
	if not match then return false end
	local hero = Heroes.get(user:GetAttribute("Hero"))
	local def = hero and hero.abilities[slot]
	local handler = def and handlers[def.id]
	if not handler or user:GetAttribute("Role") ~= Config.Roles.Survivor then return false end
	if user:GetAttribute("Seized") or Movement.held(user) then return false end
	local root = rootOf(user)
	if not root then return false end
	if os.clock() < ((readyAt[user] or {})[slot] or 0) then return false end
	-- aim: flat, unit length (the way they face if it's missing or odd)
	if typeof(aim) ~= "Vector3" or aim ~= aim then aim = root.CFrame.LookVector end
	aim = aim * Vector3.new(1, 0, 1)
	if aim.Magnitude < 0.01 then aim = root.CFrame.LookVector * Vector3.new(1, 0, 1) end
	aim = aim.Unit
	local ok, message = handler(user, root, aim, def)
	if ok then
		setCooldown(user, slot, def.cooldown)
	elseif def.missCooldown then
		setCooldown(user, slot, def.missCooldown)
	end
	return ok, message
end

useEvent.OnServerEvent:Connect(function(player, slot, aim)
	if typeof(slot) ~= "string" then return end
	local ok, message = Abilities.use(player, slot, aim)
	if not ok and message then resultEvent:FireClient(player, slot, message) end
end)

Players.PlayerRemoving:Connect(function(player) readyAt[player] = nil end)

return Abilities
