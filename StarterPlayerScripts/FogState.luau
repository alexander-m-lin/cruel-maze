-- What the fog of war knows, shared with other scripts on this player's computer (the minimap,
-- the door view, the camera). The FogOfWar script fills it in; others only read it.
--
--   tiles[x][z]  - one per fog tile: .explored (seen at some point), .onWall (a wall is there, as
--                  far as you know: a door tile is a wall while you remember its door shut)
--   visible      - { [tile] = true } for tiles in view right now (yours and your team's)
--   count        - tiles along each side; tile (x, z) covers world X from (x-1)*tileSize - half
--   tileSize, half (half the maze's width, in studs)
--   maze         - the maze model these belong to (nil until the first fog is built)
--   doors        - [door part] = { closed = remembered shut?, seen = in view right now?, tiles }
--   doorGhosts   - [door part] = the copy of it this player sees (see DoorView)

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Config"))

local FogState = {
	tiles = nil,
	visible = {},
	count = 0,
	tileSize = 2,
	half = 0,
	maze = nil,
	doors = {},
	doorGhosts = {},
}

-- Where a door's slab is right now, worked out from its attributes (smoother than waiting for the
-- server to send the part's position), and whether it counts as shut.
-- Returns cframe, shut
function FogState.doorPose(part)
	local closedCF, openCF = part:GetAttribute("ClosedCFrame"), part:GetAttribute("OpenCFrame")
	if not (closedCF and openCF) then return part.CFrame, part.CanCollide end
	local opening = part:GetAttribute("Open") == true      -- what it is, or is becoming
	local state = part:GetAttribute("State")
	if state == "warning" then
		return opening and closedCF or openCF, opening      -- hasn't moved yet: still the old way
	elseif state == "moving" then
		local t = math.clamp((workspace:GetServerTimeNow() - (part:GetAttribute("MoveAt") or 0)) / Config.DOOR_MOVE_TIME, 0, 1)
		local eased = t * t * (3 - 2 * t)
		if opening then
			return closedCF:Lerp(openCF, eased), t < 0.7
		else
			return openCF:Lerp(closedCF, eased), t > 0.3
		end
	end
	return opening and openCF or closedCF, not opening
end

return FogState
