-- FEAR EATER's abilities on the server (his numbers: ReplicatedStorage.HeroData.FearEater).
-- Each handler gets (ctx, cast): see Abilities for both.
--
-- DEVOUR: auto-targeted (DevourAim picks who). He gathers himself for def.windup (the target gets
-- "DevourTargetAt", server time, and is warned on their screen), then DevourAim.lands decides: a
-- catch, or a lunge that misses. The monster body does the moving (monster:DevourStart /
-- DevourDash / DevourCatch, in PlayerMonster and MonsterAI). A stun or pull meanwhile calls it off
-- (monster.devourToken is cleared). Nobody to target: not used, no cooldown.
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
local DevourAim = require(game:GetService("ReplicatedStorage").DevourAim)
local Movement = require(game:GetService("ReplicatedStorage").Movement)
local Fear = require(ServerStorage.Fear)
local Protection = require(game:GetService("ReplicatedStorage").Protection)

local handlers = {}

local function flat(v) return v * Vector3.new(1, 0, 1) end

---------------------------------------------------------------- Devour
-- not stunned, pulled (a whip) or mid-kill: free to carry on with a Devour
local function monsterFree(monster)
	if monster:Killing() or (monster.stunUntil or 0) > os.clock() or monster.pull ~= nil then return false end
	return not (monster.player and Movement.held(monster.player))
end

function handlers.Devour(ctx, cast)
	local monster, def = cast.monster, cast.def
	if not (monster and monster.DevourStart and monster.pos) or not monster.active then return false end   -- (inactive: the countdown)
	local objectives = ctx.match.objectives
	local now = workspace:GetServerTimeNow()
	-- who he could go for: not in a sanctuary, not already held, not encrypted (Kai: hidden, so no
	-- giving away which circuit is him); feared ones, and whether he sees the rest. (Sara mid-Flourish
	-- can be targeted: the catch is deflected.)
	local candidates, survivorOf = {}, {}
	for _, survivor in ctx.match.survivors() do
		local root = ctx.rootOf(survivor)
		if root and not survivor:GetAttribute("Seized") and not objectives:IsSafe(root.Position)
			and not Protection.encrypted(survivor) then
			local feared = (survivor:GetAttribute("FearedUntil") or 0) > now
			table.insert(candidates, { root = root, feared = feared,
				visible = feared or objectives:CanSee(monster.pos, cast.aim, { center = root.Position }) })
			survivorOf[root] = survivor
		end
	end
	local target, feared = DevourAim.pick(monster.pos, cast.aim, def, candidates, ctx.wallBetween)
	if not target then return false, "Nobody in reach" end
	local survivor = survivorOf[target]
	local targetAt = target.Position
	local token = {}
	monster.devourToken = token
	local toward = flat(target.Position - monster.pos)
	toward = toward.Magnitude > 0.1 and toward.Unit or cast.aim
	monster:DevourStart(toward, def, survivor)   -- (he keeps facing them, through the lunge too)
	survivor:SetAttribute("DevourTargetAt", now)       -- their screen warns them (FearMarks)
	survivor:SetAttribute("DevourWindup", def.windup)
	local match = ctx.match

	task.delay(def.windup, function()
		if monster.devourToken ~= token or ctx.match ~= match or not monsterFree(monster) then return end
		local root = ctx.rootOf(survivor)
		-- (encrypted meanwhile: he lunges at where they were, giving nothing away)
		if root and Protection.encrypted(survivor) then root = nil end
		local hit = root ~= nil and not survivor:GetAttribute("Seized") and not objectives:IsSafe(root.Position)
			and DevourAim.lands(monster.pos, root, def, feared, ctx.wallBetween)
		local to = flat((root and root.Position or targetAt) - monster.pos)
		local aim = to.Magnitude > 0.1 and to.Unit or toward
		local distance = hit and math.max(0, to.Magnitude - 2.5) or math.min(to.Magnitude, def.missDistance)
		local time = math.max(0.08, distance / def.dashSpeed)
		monster:DevourDash(aim, distance, time)
		if not hit then
			monster.devourToken = nil
			return
		end
		-- the catch: once he's reached them (a player's computer carries them, so it can lag a
		-- little), or a moment after the lunge should have got there
		task.spawn(function()
			local giveUp = os.clock() + time + 0.4
			while os.clock() < giveUp do
				task.wait()
				if monster.devourToken ~= token then return end
				local theirs = ctx.rootOf(survivor)
				if theirs and flat(theirs.Position - monster.pos).Magnitude <= 5 then break end
			end
			if monster.devourToken ~= token then return end
			monster.devourToken = nil
			if ctx.match ~= match or not monsterFree(monster) then return end
			local theirs = ctx.rootOf(survivor)
			if not theirs or survivor:GetAttribute("Seized") or objectives:IsSafe(theirs.Position) then return end
			monster:DevourCatch(survivor)
		end)
	end)

	-- in his Living Nightmare it recharges much faster
	local nightmare = (cast.user ~= nil and (cast.user:GetAttribute("NightmareUntil") or 0) > now)
		or (cast.user == nil and monster.Nightmaring ~= nil and monster:Nightmaring())
	return true, nil, nightmare and def.nightmareCooldown or nil
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
	if not cast.user and cast.monster and cast.monster.Cast then cast.monster:Cast(def.castTime) end   -- (an AI monster)
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
		for survivor in dreaded do Fear.apply(survivor, def, at) end
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
	-- Devour recharges in its nightmareCooldown meanwhile; whatever's left of it now is cut to that
	local devour = cast.hero.abilities.Primary
	if devour and devour.nightmareCooldown then
		ctx.shortenCooldown(cast.user or monster, "Primary", devour.nightmareCooldown)
	end
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
