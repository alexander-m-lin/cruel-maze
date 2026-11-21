-- FEAR EATER's abilities on the server (his numbers: ReplicatedStorage.HeroData.FearEater).
-- Each handler gets (ctx, cast): see Abilities for both.
--
-- DEVOUR: a dash the way he faces; the monster body does the dashing and catching
-- (monster:Devour, in PlayerMonster and MonsterAI). Here we only work out where to: aimed at a
-- feared survivor ("FearedUntil"), it heads straight for them and reaches much further.

local handlers = {}

local function flat(v) return v * Vector3.new(1, 0, 1) end

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

return handlers
