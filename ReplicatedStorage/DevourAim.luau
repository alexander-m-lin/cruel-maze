-- Where Fear Eater's DEVOUR goes, worked out the same way on the server (HeroAbilities.FearEater,
-- which carries it out) and on the player's computer (HeroVisuals.FearEater, which paints the
-- area it will catch in while the button is held).
--
--   local aim, distance, seconds, target, locked = DevourAim.pick(from, aim, def, feared, others, blocked)
--     from     - where he is (Vector3; only X and Z matter)
--     aim      - the flat unit direction he faces
--     def      - Devour's numbers (HeroData.FearEater)
--     feared   - HumanoidRootParts of the feared survivors to consider
--     others   - HumanoidRootParts of every other survivor he may catch (for aim assist)
--     blocked(a, b) - true if a wall stands between two points
--
--   1. FEARED: within def.fearedCone of his aim, def.fearedRange away, clear line: it heads
--      straight for them (the closest to his aim), 1 stud past them, much faster. locked = true.
--   2. AIM ASSIST: otherwise, any survivor within def.assistCone of his aim and def.assistRange
--      (as far as the normal dash can catch), clear line: it turns to head straight at them (the
--      closest to his aim). The dash and its reach are unchanged; only its direction.
--   3. Otherwise straight ahead, def.range. target: the root it's heading for, if any.

local DevourAim = {}

local function flat(v) return v * Vector3.new(1, 0, 1) end

-- the root closest to `aim` (in angle) within `cone` degrees (total) and `range` studs, in a clear line
local function closest(from, aim, roots, cone, range, blocked)
	local best, bestAngle
	for _, root in roots do
		local offset = flat(root.Position - from)
		local d = offset.Magnitude
		if d < 0.5 or d > range then continue end
		local angle = math.deg(math.acos(math.clamp(offset.Unit:Dot(aim), -1, 1)))
		if angle > cone / 2 then continue end
		if blocked(from, root.Position) then continue end
		if not bestAngle or angle < bestAngle then best, bestAngle = { offset = offset, d = d, root = root }, angle end
	end
	return best
end

function DevourAim.pick(from, aim, def, feared, others, blocked)
	local fearedTarget = closest(from, aim, feared, def.fearedCone, def.fearedRange, blocked)
	if fearedTarget then
		local distance = math.min(fearedTarget.d + 1, def.fearedRange)
		return fearedTarget.offset.Unit, distance, distance / def.fearedSpeed, fearedTarget.root, true
	end
	local assisted = def.assistCone and closest(from, aim, others, def.assistCone, def.assistRange, blocked)
	if assisted then
		return assisted.offset.Unit, def.range, def.dashTime, assisted.root, false
	end
	return aim, def.range, def.dashTime, nil, false
end

return DevourAim
