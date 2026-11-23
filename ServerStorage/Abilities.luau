-- HERO ABILITIES on the server: checking each use, keeping cooldowns, and carrying them out.
-- The heroes and their numbers are in ReplicatedStorage.Heroes (and HeroData); what each ability
-- does is in ServerStorage.HeroAbilities.<hero>.
--
--   Abilities.start(match)   -- a match begins: match = { maze, objectives, monsters, survivors = fn,
--                            --   stun = fn(monster, seconds), monsterOf = fn(player) -> monster }
--   Abilities.stop()         -- the match is over
--   Abilities.use(player, slot, aim)          -- a player (survivor or monster) uses an ability
--   Abilities.useMonster(monster, slot, aim)  -- an AI monster does
--   Abilities.ready(who, slot)                -- off cooldown? (who: a player or an AI monster)
--   Abilities.resetCooldowns(who)             -- everything ready now (the dev Sandbox)
--
-- A player's computer sends "UseAbility" (slot, aim): slot is "Primary" / "Secondary" / "Ultimate",
-- aim the flat direction they face. Checked here: a match is on, their hero has that slot, they're
-- alive and not held, stunned, pulled or in the middle of a kill, and the cooldown is over.
-- Survivors and monsters (players or AI) all go through the same path. Cooldowns are kept here and
-- published as "AbilityReady<Slot>" (server time) on the player, for the ability bar.
--
-- A handler is called as handler(ctx, cast):
--   ctx  = { match, fx (the "AbilityFx" event), rayParams (the maze's walls), rootOf(who),
--            wallBetween(a, b), stopOutsideSanctuaries(from, to) }
--   cast = { user (the player, nil for an AI monster), monster (the monster using it, if one),
--            root (the user's HumanoidRootPart, if they have a character), aim (flat, unit),
--            def (the ability's numbers), hero }
-- and returns ok, message[, cooldown] (cooldown: seconds, instead of the ability's own, e.g. Devour's
-- during Living Nightmare). ctx.shortenCooldown(who, slot, seconds) cuts what's left of another
-- ability's cooldown to at most `seconds`. Everyone's computer is told what happened through "AbilityFx" (kind, the
-- user's UserId, details) so it can draw it (HeroVisuals).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Config)
local Net = require(ReplicatedStorage.Net)
local Heroes = require(ReplicatedStorage.Heroes)
local Movement = require(ReplicatedStorage.Movement)

local useEvent = Net.event("UseAbility")     -- player -> server: (slot, aim)
local fxEvent = Net.event("AbilityFx")       -- server -> players: (kind, userId, ...)
local resultEvent = Net.event("AbilityResult")   -- server -> player: (slot, message) when a use fails

local Abilities = {}

-- every hero's handlers, by ability id
local handlers = {}
for _, id in Heroes.ORDER do
	local module = ServerStorage.HeroAbilities:FindFirstChild(id)
	if module then
		for abilityId, fn in require(module) do handlers[abilityId] = fn end
	end
end

local readyAt = {}         -- [player or AI monster][slot] = os.clock() when it can be used again

local function rootOf(who)
	local character = who.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and humanoid and humanoid.Health > 0 then return root end
	return nil
end

local ctx = { fx = fxEvent, rootOf = rootOf }

-- A wall between two points (at waist height)?
function ctx.wallBetween(a, b)
	local y = ctx.match.maze.floorY + 3
	local from, to = Vector3.new(a.X, y, a.Z), Vector3.new(b.X, y, b.Z)
	local hit = workspace:Raycast(from, to - from, ctx.rayParams)
	return hit ~= nil and hit.Instance.CanCollide
end

-- Can't go into a sanctuary: a monster pulled toward someone inside one stops at the edge
function ctx.stopOutsideSanctuaries(from, to)
	local objectives = ctx.match.objectives
	local steps = math.ceil((to - from).Magnitude / 1)
	local last = from
	for i = 1, steps do
		local p = from:Lerp(to, i / steps)
		if objectives:IsSafe(p) then return last end
		last = p
	end
	return to
end

function Abilities.start(parts)
	ctx.match = parts
	table.clear(readyAt)
	ctx.rayParams = RaycastParams.new()
	ctx.rayParams.FilterType = Enum.RaycastFilterType.Include
	ctx.rayParams.FilterDescendantsInstances = { parts.maze.model }
end

function Abilities.stop()
	ctx.match = nil
	for _, player in Players:GetPlayers() do
		for _, slot in Heroes.SLOTS do player:SetAttribute("AbilityReady" .. slot, nil) end
	end
	table.clear(readyAt)
end

local function setCooldown(who, slot, seconds)
	readyAt[who] = readyAt[who] or {}
	readyAt[who][slot] = os.clock() + seconds
	if typeof(who) == "Instance" then
		who:SetAttribute("AbilityReady" .. slot, workspace:GetServerTimeNow() + seconds)
	end
end

-- Cut what's left of a cooldown to at most `seconds`
function ctx.shortenCooldown(who, slot, seconds)
	local left = ((readyAt[who] or {})[slot] or 0) - os.clock()
	if left > seconds then setCooldown(who, slot, seconds) end
end

-- Every ability ready again (the dev Sandbox's "Ready" button)
function Abilities.resetCooldowns(who)
	readyAt[who] = nil
	if typeof(who) == "Instance" then
		for _, slot in Heroes.SLOTS do who:SetAttribute("AbilityReady" .. slot, nil) end
	end
end

function Abilities.ready(who, slot)
	return ctx.match ~= nil and os.clock() >= ((readyAt[who] or {})[slot] or 0)
end

-- aim: flat, unit length (`fallback` if it's missing or odd)
local function flatAim(aim, fallback)
	if typeof(aim) ~= "Vector3" or aim ~= aim then aim = fallback end
	aim = aim * Vector3.new(1, 0, 1)
	if aim.Magnitude < 0.01 then aim = fallback * Vector3.new(1, 0, 1) end
	return aim.Magnitude > 0.01 and aim.Unit or Vector3.new(0, 0, -1)
end

-- Carry it out and start the cooldown. who: whose cooldown (the player, or the AI monster).
local function cast(who, slot, c)
	local handler = handlers[c.def.id]
	if not handler then return false end         -- not built yet
	if not Abilities.ready(who, slot) then return false end
	local ok, message, cooldown = handler(ctx, c)
	if ok then
		setCooldown(who, slot, cooldown or c.def.cooldown)
	elseif c.def.missCooldown then
		setCooldown(who, slot, c.def.missCooldown)
	end
	return ok, message
end

-- A monster in no state to act: in the middle of a kill, stunned or being dragged
local function monsterBusy(monster)
	if monster:Killing() then return true end
	if (monster.stunUntil or 0) > os.clock() then return true end
	return monster.pull ~= nil
end

-- user: a player (survivor or monster). Returns ok, message.
function Abilities.use(user, slot, aim)
	if not ctx.match then return false end
	local hero = Heroes.get(user:GetAttribute("Hero"))
	local def = hero and hero.abilities[slot]
	if not def then return false end
	local role = user:GetAttribute("Role")
	local root = rootOf(user)
	if not root or user:GetAttribute("Seized") or Movement.held(user) then return false end
	local monster = nil
	if role == Config.Roles.Monster then
		monster = ctx.match.monsterOf and ctx.match.monsterOf(user)
		if not monster or monsterBusy(monster) then return false end
	elseif role ~= Config.Roles.Survivor then
		return false
	end
	return cast(user, slot, { user = user, monster = monster, root = root, def = def, hero = hero,
		aim = flatAim(aim, root.CFrame.LookVector) })
end

-- An AI monster uses an ability (its hero: monster.hero)
function Abilities.useMonster(monster, slot, aim)
	if not ctx.match or monsterBusy(monster) then return false end
	local hero = Heroes.get(monster.hero)
	local def = hero and hero.abilities[slot]
	if not def then return false end
	return cast(monster, slot, { monster = monster, def = def, hero = hero, aim = flatAim(aim, monster.facing) })
end

useEvent.OnServerEvent:Connect(function(player, slot, aim)
	if typeof(slot) ~= "string" then return end
	local ok, message = Abilities.use(player, slot, aim)
	if not ok and message then resultEvent:FireClient(player, slot, message) end
end)

Players.PlayerRemoving:Connect(function(player) readyAt[player] = nil end)

return Abilities
