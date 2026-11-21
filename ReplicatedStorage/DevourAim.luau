-- Where Fear Eater's DEVOUR goes, worked out the same way on the server (HeroAbilities.FearEater,
-- which carries it out) and on the player's computer (HeroVisuals.FearEater, which paints the
-- area it will catch in while the button is held).
--
--   local aim, distance, seconds, target = DevourAim.pick(from, aim, def, feared, blocked)
--     from     - where he is (Vector3; only X and Z matter)
--     aim      - the flat unit direction he faces
--     def      - Devour's numbers (HeroData.FearEater)
--     feared   - HumanoidRootParts of the feared survivors to consider
--     blocked(a, b) - true if a wall stands between two points
--   Aimed within def.fearedCone of a feared survivor in def.fearedRange with a clear line, it heads
--   straight for them (the closest to where he aims), going 1 stud past them. Otherwise it goes
--   def.range straight ahead. target: the root it's heading for, if any.

local DevourAim = {}

local function flat(v) return v * Vector3.new(1, 0, 1) end

function DevourAim.pick(from, aim, def, feared, blocked)
	local best, bestAngle
	for _, root in feared do
		local offset = flat(root.Position - from)
		local d = offset.Magnitude
		if d < 0.5 or d > def.fearedRange then continue end
		local angle = math.deg(math.acos(math.clamp(offset.Unit:Dot(aim), -1, 1)))
		if angle > def.fearedCone / 2 then continue end
		if blocked(from, root.Position) then continue end
		if not bestAngle or angle < bestAngle then best, bestAngle = { offset = offset, d = d, root = root }, angle end
	end
	if best then
		local distance = math.min(best.d + 1, def.fearedRange)
		return best.offset.Unit, distance, distance / def.fearedSpeed, best.root
	end
	return aim, def.range, def.dashTime, nil
end

return DevourAim
