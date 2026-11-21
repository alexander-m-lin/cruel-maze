-- SARA's abilities on the server (her numbers: ReplicatedStorage.HeroData.Sara).
-- Each handler gets (ctx, cast): see Abilities for both. Return true if it was used (the cooldown
-- starts), or false (and maybe a message for the player) if not.

local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")
local Config = require(game:GetService("ReplicatedStorage").Config)
local Pull = require(ServerStorage.Pull)

local EYE_HEIGHT = 3       -- the whip travels at this height above the floor

local handlers = {}

-- WHIP: the first thing along the lash, out to its range
function handlers.Whip(ctx, cast)
	local match, user, root, aim, def = ctx.match, cast.user, cast.root, cast.aim, cast.def
	local maze = match.maze
	local origin = Vector3.new(root.Position.X, maze.floorY + EYE_HEIGHT, root.Position.Z)
	local wall = workspace:Raycast(origin, aim * def.range, ctx.rayParams)
	local reach = wall and wall.Distance or def.range
	-- where along the lash something at `p` sits, if it's within `radius` of it with no wall
	-- between (nil = not hit)
	local function along(p, radius)
		local offset = Vector3.new(p.X - origin.X, 0, p.Z - origin.Z)
		local t = offset:Dot(aim)
		if t <= 0.5 or t > reach then return nil end
		local side = offset - aim * t
		if side.Magnitude > radius then return nil end
		if side.Magnitude > 0.5 and workspace:Raycast(origin + aim * t, side, ctx.rayParams) then return nil end
		return t
	end
	local hit = { kind = wall and "wall" or "miss", t = reach }
	local function consider(kind, t, thing)
		if t and t < hit.t then hit = { kind = kind, t = t, thing = thing } end
	end
	for _, monster in match.monsters do
		if monster.pos then consider("monster", along(monster.pos, def.monsterHitRadius), monster) end
	end
	for _, other in match.survivors() do
		local otherRoot = other ~= user and not other:GetAttribute("Seized") and ctx.rootOf(other)
		if otherRoot then consider("ally", along(otherRoot.Position, def.allyHitRadius), other) end
	end
	for _, relic in match.maze.relics do
		if not relic.collected then consider("relic", along(relic.center, def.relicHitRadius), relic) end
	end
	for _, relic in match.objectives.fakes do
		consider("relic", along(relic.center, def.relicHitRadius), relic)
	end

	local tip = origin + aim * hit.t
	ctx.fx:FireAllClients("Whip", user.UserId, Vector3.new(tip.X, maze.floorY, tip.Z), hit.kind)
	-- what happens once the lash gets there
	task.delay(hit.t / def.speed, function()
		if ctx.match ~= match or not ctx.rootOf(user) then return end
		local here = ctx.rootOf(user).Position
		if hit.kind == "wall" or hit.kind == "relic" then
			-- you're pulled to it (stopping short of the wall, or beside the relic)
			local stopShort = hit.kind == "wall" and 2.5 or 3.5
			Pull.character(user, tip - aim * stopShort, def.pullSpeed, "slide")
		elseif hit.kind == "ally" then
			local ally = hit.thing
			Pull.character(ally, here + aim * 3, def.pullSpeed)
		elseif hit.kind == "monster" then
			local monster = hit.thing
			local to = ctx.stopOutsideSanctuaries(monster.pos, Vector3.new(here.X, maze.floorY, here.Z) + aim * 5)
			local seconds = monster:Pull(to, def.pullSpeed) or 0
			match.stun(monster, seconds + def.stun)        -- stunned while dragged, then for def.stun
		end
	end)
	if hit.kind == "miss" then return false end   -- a whiff: def.missCooldown instead (no message)
	return true
end

-- TREASURE HUNT: the nearest relic the survivors haven't spotted, within range
function handlers.TreasureHunt(ctx, cast)
	local match, user, root, def = ctx.match, cast.user, cast.root, cast.def
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
			ctx.fx:FireClient(other, "TreasureHunt", user.UserId, best.center)
		end
	end
	return true
end

-- FLOURISH: she stands still for castTime ("CastingUntil": Movement.held); stunAt seconds in,
-- every monster in range of her is stunned. Caught (or out of the match) before then: nothing.
function handlers.Flourish(ctx, cast)
	local match, user, def = ctx.match, cast.user, cast.def
	user:SetAttribute("CastingUntil", workspace:GetServerTimeNow() + def.castTime)
	ctx.fx:FireAllClients("Flourish", user.UserId)
	task.delay(def.castTime, function()
		if (user:GetAttribute("CastingUntil") or 0) <= workspace:GetServerTimeNow() + 0.05 then user:SetAttribute("CastingUntil", nil) end
	end)
	task.delay(def.stunAt, function()
		local now = ctx.rootOf(user)
		if ctx.match ~= match or not now or user:GetAttribute("Seized") then return end
		for _, monster in match.monsters do
			if monster.pos and ((monster.pos - now.Position) * Vector3.new(1, 0, 1)).Magnitude <= def.range then
				match.stun(monster, def.stun)
			end
		end
	end)
	return true
end

return handlers
