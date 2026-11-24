-- AN AUTO-TARGETED CATCH on the server: Fear Eater's Devour and the Minotaur's Tear Asunder (any
-- monster Primary with `autoTarget`). Their handlers call AutoCatch.run(ctx, cast) (see Abilities
-- for both).
--
-- DevourAim picks who: the nearest survivor he can see in front of him within def.range (and, with
-- a def.fearedRange, a feared survivor much further, first). He gathers himself for def.windup
-- (the target gets "DevourTargetAt", server time, and is warned on their screen), then
-- DevourAim.lands decides: a catch, or a lunge that misses. The monster body does the moving
-- (monster:DevourStart / DevourDash / DevourCatch, in PlayerMonster and MonsterAI; players'
-- computers draw it from the same "Devour..." attributes whatever the hero). A stun or pull
-- meanwhile calls it off (monster.devourToken is cleared). Nobody to target: not used, no cooldown.
--
--   local ok, message = AutoCatch.run(ctx, cast)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DevourAim = require(ReplicatedStorage.DevourAim)
local Movement = require(ReplicatedStorage.Movement)
local Protection = require(ReplicatedStorage.Protection)

local AutoCatch = {}

local function flat(v) return v * Vector3.new(1, 0, 1) end

-- not stunned, pulled (a whip) or mid-kill: free to carry on with the catch
local function monsterFree(monster)
	if monster:Killing() or (monster.stunUntil or 0) > os.clock() or monster.pull ~= nil then return false end
	return not (monster.player and Movement.held(monster.player))
end

function AutoCatch.run(ctx, cast)
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
			local feared = def.fearedRange ~= nil and (survivor:GetAttribute("FearedUntil") or 0) > now
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
	return true
end

return AutoCatch
