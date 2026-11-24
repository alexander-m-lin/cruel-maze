-- Who Fear Eater's DEVOUR (and the Minotaur's Tear Asunder: any auto-targeted catch, `autoTarget`)
-- goes for, and whether it lands. Shared by the server (HeroAbilities.FearEater,
-- which carries it out) and the player's computer (FearMarks, which rings the survivor it would
-- target, so you know before you click).
--
--   local root, feared = DevourAim.pick(from, facing, def, candidates, blocked)
--     from       - where he is (Vector3; only X and Z matter)
--     facing     - the flat unit direction he faces
--     def        - Devour's numbers (HeroData.FearEater)
--     candidates - { { root = HumanoidRootPart, feared = bool, visible = bool }, ... }: survivors he
--                  may catch (not in a sanctuary, not already held). visible: his side can see them
--                  (the caller decides: the server's sight check, or the fog on a player's computer)
--     blocked(a, b) - true if a wall stands between two points
--   1. FEARED: the nearest feared survivor within def.fearedRange, in a clear line (anywhere
--      round him: they're revealed). feared = true. (Skipped without a fearedRange.)
--   2. Otherwise the nearest visible survivor within def.range, in a clear line, in front of him
--      (within Config.VIEW_CONE, or closer than Config.VIEW_NEAR).
--   Nobody: nil.
--
--   DevourAim.lands(from, root, def, feared, blocked) -> bool: when the windup ends, is it a catch?
--     feared: still within def.fearedCatchRange (walls don't matter: he's sure of them).
--     others: within def.catchRange, in a clear line.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))

local DevourAim = {}

local function flat(v) return v * Vector3.new(1, 0, 1) end

function DevourAim.pick(from, facing, def, candidates, blocked)
	local best, bestD, bestFeared
	local halfCone = Config.VIEW_CONE / 2
	for pass = 1, 2 do                        -- feared first, then anyone in sight
		for _, c in candidates do
			if (pass == 1) ~= (c.feared == true) then continue end
			if pass == 1 and not def.fearedRange then continue end   -- (no fear in it: Tear Asunder)
			local offset = flat(c.root.Position - from)
			local d = offset.Magnitude
			if d > (pass == 1 and def.fearedRange or def.range) then continue end
			if pass == 2 then
				if not c.visible then continue end
				if d > Config.VIEW_NEAR and d > 0.5 then
					local angle = math.deg(math.acos(math.clamp(offset.Unit:Dot(facing), -1, 1)))
					if angle > halfCone then continue end
				end
			end
			if bestD and d >= bestD then continue end
			if blocked(from, c.root.Position) then continue end
			best, bestD, bestFeared = c.root, d, pass == 1
		end
		if best then return best, bestFeared end
	end
	return nil, false
end

function DevourAim.lands(from, root, def, feared, blocked)
	local d = flat(root.Position - from).Magnitude
	if feared and def.fearedCatchRange then return d <= def.fearedCatchRange end
	return d <= def.catchRange and not blocked(from, root.Position)
end

return DevourAim
