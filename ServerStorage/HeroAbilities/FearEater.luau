-- FEAR EATER's abilities on the server (his numbers: ReplicatedStorage.HeroData.FearEater).
-- Each handler gets (ctx, cast): see Abilities for both.
--
-- DEVOUR: a dash the way he faces; the monster body does the dashing and catching
-- (monster:Devour, in PlayerMonster and MonsterAI). Here we only work out where to: aimed at a
-- feared survivor ("FearedUntil"), it heads straight for them and reaches much further.
--
-- INSTILL FEAR: every survivor not in a sanctuary gets "DreadUntil" (server time). Until then,
-- reaching a sanctuary or another survivor clears it; otherwise they're feared: "FearedUntil",
-- "FearSlow" (Movement slows them) and "RevealedUntil" (the monster side sees them).
--
-- LIVING NIGHTMARE: (monster players; AI monsters don't use it yet) the character goes into the
-- "Nightmare" collision group, which passes through the maze's "MazeInner" walls and doors, and
-- "NightmareUntil" + "NightmareBoost" speed it up toward feared survivors (Movement, SpeedCheck).

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local SpeedCheck = require(ServerStorage.SpeedCheck)

local handlers = {}

local function flat(v) return v * Vector3.new(1, 0, 1) end

---------------------------------------------------------------- Devour
function handlers.Devour(ctx, cast)
	local monster, def = cast.monster, cast.def
	if not (monster and monster.Devour and monster.pos) then return false end
	local from = monster.pos
	local aim = cast.aim
	local distance, time = def.range, def.dashTime

	-- the feared survivor closest to where he's aiming, in range and in a clear line
	local now = workspace:GetServerTimeNow()
	local best, bestAngle
	for _, survivor in ctx.match.survivors() do
		if (survivor:GetAttribute("FearedUntil") or 0) <= now or survivor:GetAttribute("Seized") then continue end
		local root = ctx.rootOf(survivor)
		if not root then continue end
		local offset = flat(root.Position - from)
		local d = offset.Magnitude
		if d < 0.5 or d > def.fearedRange then continue end
		local angle = math.deg(math.acos(math.clamp(offset.Unit:Dot(aim), -1, 1)))
		if angle > def.fearedCone / 2 then continue end
		if ctx.wallBetween(from, root.Position) then continue end
		if not bestAngle or angle < bestAngle then best, bestAngle = { offset = offset, d = d }, angle end
	end
	if best then
		aim = best.offset.Unit
		distance = math.min(best.d + 1, def.fearedRange)
		time = distance / def.fearedSpeed
	end
	return monster:Devour(aim, distance, time, def)
end

---------------------------------------------------------------- Instill Fear
-- The monster's body shows the cast: "CastAt" (server time) and "CastKind" (the ability's id)
local function showCast(monster, kind)
	if monster and monster.model then
		monster.model:SetAttribute("CastKind", kind)
		monster.model:SetAttribute("CastAt", workspace:GetServerTimeNow())
	end
end

function handlers.InstillFear(ctx, cast)
	local match, def = ctx.match, cast.def
	local objectives = match.objectives
	local now = workspace:GetServerTimeNow()
	if cast.user then cast.user:SetAttribute("CastingUntil", now + def.castTime) end   -- holds still (Movement.held)
	showCast(cast.monster, "InstillFear")

	local dreaded = {}
	for _, survivor in match.survivors() do
		local root = ctx.rootOf(survivor)
		if root and not survivor:GetAttribute("Seized") and not objectives:IsSafe(root.Position) then
			survivor:SetAttribute("DreadUntil", now + def.dreadTime)
			dreaded[survivor] = true
		end
	end

	-- near another survivor (players and bots, not being killed)?
	local function nearAlly(survivor, root)
		for _, other in match.survivors() do
			local otherRoot = other ~= survivor and not other:GetAttribute("Seized") and ctx.rootOf(other)
			if otherRoot and flat(otherRoot.Position - root.Position).Magnitude <= def.nearAlly then return true end
		end
		return false
	end

	task.spawn(function()
		local endsAt = now + def.dreadTime
		while next(dreaded) and workspace:GetServerTimeNow() < endsAt do
			task.wait(0.1)
			for survivor in dreaded do
				local root = ctx.rootOf(survivor)
				local over = ctx.match ~= match or not survivor.Parent or not root or survivor:GetAttribute("Seized")
				if over or objectives:IsSafe(root.Position) or nearAlly(survivor, root) then
					survivor:SetAttribute("DreadUntil", nil)    -- made it (or out of the match)
					dreaded[survivor] = nil
				end
			end
		end
		if ctx.match ~= match then return end
		-- still dreading: feared
		local at = workspace:GetServerTimeNow()
		for survivor in dreaded do
			survivor:SetAttribute("DreadUntil", nil)
			survivor:SetAttribute("FearSlow", def.fearSlow)
			survivor:SetAttribute("FearedUntil", at + def.fearTime)
			survivor:SetAttribute("RevealedUntil", math.max(survivor:GetAttribute("RevealedUntil") or 0, at + def.fearTime))
		end
	end)
	return true
end

---------------------------------------------------------------- Living Nightmare
-- Mark the maze's walls he may pass through: every wall panel, post and door except those on the
-- outer wall or touching a sanctuary (checked by the cells either side of it). Once per maze.
local function markInnerWalls(match)
	local maze, objectives = match.maze, match.objectives
	if maze.model:GetAttribute("InnerWallsMarked") then return end
	maze.model:SetAttribute("InnerWallsMarked", true)
	local function open(p)   -- a cell inside the maze that monsters may enter?
		local x, z = objectives:CellOf(p)
		return x ~= nil and not objectives:IsBlocked(x, z)
	end
	for _, part in maze.model:GetDescendants() do
		if not part:IsA("BasePart") or (part.Name ~= "Wall" and part.Name ~= "Door") then continue end
		local c, size = part.Position, part.Size
		local probes
		if size.X > 4 and size.Z <= 4 then          -- a panel along X: the cells north and south of it
			probes = { c + Vector3.new(0, 0, 3), c - Vector3.new(0, 0, 3) }
		elseif size.Z > 4 and size.X <= 4 then      -- along Z: east and west
			probes = { c + Vector3.new(3, 0, 0), c - Vector3.new(3, 0, 0) }
		else                                         -- a post: the four cells round the corner
			probes = { c + Vector3.new(3, 0, 3), c + Vector3.new(-3, 0, 3), c + Vector3.new(3, 0, -3), c + Vector3.new(-3, 0, -3) }
		end
		local inner = true
		for _, q in probes do
			if not open(q) then inner = false break end
		end
		if inner then part.CollisionGroup = "MazeInner" end
	end
end

function handlers.LivingNightmare(ctx, cast)
	local monster, def = cast.monster, cast.def
	if not (monster and monster.Nightmare) then return false end
	markInnerWalls(ctx.match)
	return monster:Nightmare(def, function(character)
		-- ending inside a wall: pushed out to the middle of the cell he's in (or the nearest open one)
		local root = character:FindFirstChild("HumanoidRootPart")
		if not root or ctx.match == nil then return end
		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { ctx.match.maze.model }
		local stuck = false
		for _, part in workspace:GetPartBoundsInBox(root.CFrame, Vector3.new(3, 4, 3), params) do
			if part.CanCollide and (part.Name == "Wall" or part.Name == "Door") then stuck = true break end
		end
		if not stuck then return end
		local maze, objectives = ctx.match.maze, ctx.match.objectives
		local x, z = objectives:CellOf(root.Position)
		if not x then return end
		local best, bestD
		for dx = -1, 1 do
			for dz = -1, 1 do
				local cx, cz = x + dx, z + dz
				if cx >= 1 and cz >= 1 and cx <= maze.n and cz <= maze.n and not objectives:IsBlocked(cx, cz) then
					local center = Vector3.new((cx - 0.5) * maze.S - maze.half, root.Position.Y, (cz - 0.5) * maze.S - maze.half)
					local d = (center - root.Position).Magnitude
					if not bestD or d < bestD then best, bestD = center, d end
				end
			end
		end
		if best then
			character:PivotTo(CFrame.new(best) * root.CFrame.Rotation)
			if Players:GetPlayerFromCharacter(character) then SpeedCheck.moved(Players:GetPlayerFromCharacter(character)) end
		end
	end)
end

return handlers
