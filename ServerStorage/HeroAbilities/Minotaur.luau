-- THE MINOTAUR's abilities on the server (his numbers: ReplicatedStorage.HeroData.Minotaur).
-- Each handler gets (ctx, cast): see Abilities for both.
--
-- TEAR ASUNDER: auto-targeted, the same catch as Fear Eater's Devour (AutoCatch), without the fear.
--
-- DEVASTATING CHARGE: the direction is locked when he uses it. The path is planned here: a ray along
-- it at waist height against everything that stops a monster player (walls, shut doors, the
-- sanctuaries' barriers; not crushing walls), stopping def.bodyRadius short, and never into a
-- sanctuary. After the windup he's carried along it at def.speed (the player's computer moves
-- their character, MonsterControls; SpeedCheck lets it). Every frame the path so far is checked
-- (the server's own idea of where he is, not the client's): every survivor within def.halfWidth of
-- it, not behind him, in a clear line from it, outside sanctuaries, is TRAMPLED - caught, flung
-- aside on everyone's computer ("Trampled"), and he runs on. A door shutting in front of him
-- meanwhile ends it early there. A stun calls it off where he is. Then he reels for def.recovery,
-- and the cooldown starts. (Monster players only for now: AI monsters don't charge yet.)
--
-- CRUSH: the landing point is the aimed point (cast.point; or straight ahead at full range),
-- brought within def.range, then pulled back toward him until it's somewhere he could stand:
-- inside the maze, not a sanctuary, clear of walls by def.bodyRadius. He leaps (monster:LeapStart:
-- the player's computer carries their character over the walls); at def.windup every survivor
-- within def.radius of the landing, in a clear line from it, outside sanctuaries and not
-- encrypted, is STUNNED for def.stun ("StunnedUntil": Movement holds them, Abilities refuses their
-- abilities). Everyone's computer is told ("CrushImpact").

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AutoCatch = require(ServerStorage.AutoCatch)
local Protection = require(ReplicatedStorage.Protection)

local handlers = {}

local function flat(v) return v * Vector3.new(1, 0, 1) end

---------------------------------------------------------------- Tear Asunder
function handlers.TearAsunder(ctx, cast)
	return AutoCatch.run(ctx, cast)
end

---------------------------------------------------------------- Devastating Charge
local chargeRays = RaycastParams.new()
chargeRays.FilterType = Enum.RaycastFilterType.Include
chargeRays.RespectCanCollide = true
chargeRays.CollisionGroup = "MonsterPlayers"     -- (what stops a monster player stops the charge)

-- Where a charge from `from` along `dir` ends: the first wall or shut door, less his body's
-- radius, and never inside a sanctuary. (floor-level points)
local function chargeEnd(ctx, from, dir, def)
	local maze = ctx.match.maze
	chargeRays.FilterDescendantsInstances = { maze.model }
	local origin = Vector3.new(from.X, maze.floorY + 3, from.Z)
	local hit = workspace:Raycast(origin, dir * def.maxDistance, chargeRays)
	local length = hit and math.max(0, hit.Distance - def.bodyRadius) or def.maxDistance
	return ctx.stopOutsideSanctuaries(from, from + dir * length)
end

-- the survivors a charge from `a` to `b` (floor points) touches now
local function touched(ctx, a, b, def, caught)
	local objectives = ctx.match.objectives
	local length = flat(b - a).Magnitude
	local dir = length > 0.01 and flat(b - a).Unit or Vector3.zero
	local list = {}
	for _, survivor in ctx.match.survivors() do
		if caught[survivor] or survivor:GetAttribute("Seized") or Protection.encrypted(survivor) then continue end
		local root = ctx.rootOf(survivor)
		if not root or objectives:IsSafe(root.Position) then continue end
		local offset = flat(root.Position - a)
		local along = offset:Dot(dir)
		if along < -1 then continue end                         -- behind where he set off
		local closest = a + dir * math.clamp(along, 0, length)
		if flat(root.Position - closest).Magnitude <= def.halfWidth and not ctx.wallBetween(closest, root.Position) then
			table.insert(list, survivor)
		end
	end
	return list
end

function handlers.Charge(ctx, cast)
	local monster, def, hero = cast.monster, cast.def, cast.hero
	if not (monster and monster.ChargeWindup and monster.pos) or not monster.active then return false end
	local who = cast.user or monster
	local dir = cast.aim
	local match = ctx.match
	local token = {}
	monster.chargeToken = token
	monster:ChargeWindup(dir, def, chargeEnd(ctx, monster.pos, dir, def))

	task.delay(def.windup, function()
		if ctx.match ~= match then return end
		if monster.chargeToken ~= token then             -- stunned in the windup: called off
			if monster.ChargeEnd then monster:ChargeEnd(monster.pos, 0) end
			ctx.setCooldown(who, "Secondary", def.cooldown)
			return
		end
		local from = monster.pos
		local to = chargeEnd(ctx, from, dir, def)
		local distance = (to - from).Magnitude
		local time = math.max(0.05, distance / def.speed)
		monster:ChargeGo(from, to, time)
		local started = os.clock()
		local caught = {}
		local at, stunned = from, false
		while true do
			task.wait()
			if ctx.match ~= match then return end
			if monster.chargeToken ~= token then
				stunned = true
				break
			end
			local k = math.min(1, (os.clock() - started) / time)
			at = from + dir * distance * k
			-- a door shut across his path meanwhile: he stops at it
			local ahead = chargeEnd(ctx, at, dir, def)
			if (ahead - at).Magnitude < (to - at).Magnitude - 0.5 then
				to = ahead
				distance = (to - from).Magnitude
				time = math.max(0.05, distance / def.speed)
				monster:ChargeGo(from, to, time)                 -- (their computer stops there)
			end
			for _, survivor in touched(ctx, from, at + dir * def.reach, def, caught) do
				caught[survivor] = true
				if monster:Trample(survivor, hero.trample) then
					ctx.fx:FireAllClients("Trampled", survivor.UserId, dir)
				end
			end
			if k >= 1 then break end
		end
		if monster.chargeToken == token then monster.chargeToken = nil end
		monster:ChargeEnd(at, stunned and 0 or def.recovery)
		ctx.setCooldown(who, "Secondary", def.cooldown)
	end)
	-- (a placeholder: the real cooldown is set when the charge ends)
	return true, nil, def.windup + def.maxDistance / def.speed + def.recovery + def.cooldown
end

---------------------------------------------------------------- Crush
local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Include

-- somewhere he could stand: in the maze, not a sanctuary, clear of walls and doors
local function canLand(ctx, p, def)
	local objectives, maze = ctx.match.objectives, ctx.match.maze
	local x, z = objectives:CellOf(p)
	if not x or objectives:IsBlocked(x, z) or objectives:IsSafe(p) then return false end
	overlap.FilterDescendantsInstances = { maze.model }
	local box = CFrame.new(p.X, maze.floorY + 3, p.Z)
	for _, part in workspace:GetPartBoundsInBox(box, Vector3.new(def.bodyRadius * 2, 4, def.bodyRadius * 2), overlap) do
		if part.CanCollide then return false end
	end
	return true
end

-- the aimed point, pulled back toward him until he could land there (or where he is)
local function landing(ctx, from, want, def)
	local offset = flat(want - from)
	if offset.Magnitude > def.range then offset = offset.Unit * def.range end
	local steps = math.ceil(offset.Magnitude)
	for i = steps, 1, -1 do
		local p = from + offset * (i / steps)
		if canLand(ctx, p, def) then return p end
	end
	return from
end

function handlers.Crush(ctx, cast)
	local monster, def = cast.monster, cast.def
	if not (monster and monster.LeapStart and monster.pos) or not monster.active then return false end
	local from = monster.pos
	local want = cast.point or (from + cast.aim * def.range)
	local to = landing(ctx, from, Vector3.new(want.X, from.Y, want.Z), def)
	monster:LeapStart(from, to, def)
	local match = ctx.match
	task.delay(def.windup, function()
		if ctx.match ~= match then return end
		local objectives = match.objectives
		local now = workspace:GetServerTimeNow()
		for _, survivor in match.survivors() do
			local root = ctx.rootOf(survivor)
			if not root or survivor:GetAttribute("Seized") or Protection.encrypted(survivor) then continue end
			if objectives:IsSafe(root.Position) or flat(root.Position - to).Magnitude > def.radius then continue end
			if ctx.wallBetween(to, root.Position) then continue end
			survivor:SetAttribute("StunnedUntil", math.max(survivor:GetAttribute("StunnedUntil") or 0, now + def.stun))
		end
		ctx.fx:FireAllClients("CrushImpact", cast.user and cast.user.UserId or 0, to, def.radius)
	end)
	return true
end

return handlers
