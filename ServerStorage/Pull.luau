-- PULLING someone along a straight line (Sara's whip, and whatever else later pulls or knocks
-- people about). Reusable for survivors, survivor bots and monsters of both kinds.
--
--   local seconds = Pull.character(who, to, speed, style)   -- a player or bot (their character)
--   Pull.step()                                       -- every frame (Match): moves pulled bots
--
-- `to` is a floor point (only X and Z matter: they keep their height). Takes distance / speed
-- seconds, during which they can't move themselves (Movement.held).
-- style: nil (dragged as they stand), or "slide" (pulling yourself along a whip, skateboarder
-- style: turned side-on with the right hand toward where you're going, leaning back from it).
-- Published as "PullStyle"; the body's pose is Pull.pose.
--
-- Who moves the character: a player's own computer simulates their character, so the server only
-- says where and when (attributes PullFrom, PullTo, PullAt (server time), PullTime on the player)
-- and their computer carries them (Controls), with the speed check told to expect it. A bot's
-- body is the server's, so it's moved here. (AI monsters have their own :Pull, see MonsterAI.)

local ServerStorage = game:GetService("ServerStorage")

local SpeedCheck = require(ServerStorage.SpeedCheck)

local Pull = {}

local active = {}   -- [bot] = { root, from, to, startedAt, time }  (bots only)

local function rootOf(who)
	local character = who.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and humanoid and humanoid.Health > 0 then return root end
	return nil
end

-- The way someone sliding faces: side-on (their right toward where they're going), leaning back
-- away from it. -> a rotation-only CFrame (for a flat direction of travel)
function Pull.pose(direction)
	local facing = Vector3.yAxis:Cross(direction)     -- so that their right points along `direction`
	return CFrame.lookAt(Vector3.zero, facing) * CFrame.Angles(0, 0, math.rad(14))
end

function Pull.character(who, to, speed, style)
	local root = rootOf(who)
	if not root then return 0 end
	local from = root.Position
	local target = Vector3.new(to.X, from.Y, to.Z)
	local distance = (target - from).Magnitude
	if distance < 0.5 then return 0 end
	local seconds = distance / speed
	local now = workspace:GetServerTimeNow()
	who:SetAttribute("PullFrom", from)
	who:SetAttribute("PullTo", target)
	who:SetAttribute("PullAt", now)
	who:SetAttribute("PullTime", seconds)
	who:SetAttribute("PullStyle", style)
	if typeof(who) == "Instance" then
		SpeedCheck.grant(who, distance + 4)         -- their computer moves them this far
	else
		active[who] = { root = root, from = from, to = target, startedAt = os.clock(), time = seconds, style = style }
	end
	return seconds
end

-- Moves pulled bots along (players' computers move their own characters)
function Pull.step()
	local now = os.clock()
	for bot, p in active do
		if not p.root.Parent then
			active[bot] = nil
			continue
		end
		local k = math.clamp((now - p.startedAt) / p.time, 0, 1)
		local at = p.from:Lerp(p.to, k)
		local character = p.root.Parent
		if p.style == "slide" then
			local turn = Pull.pose(((p.to - p.from) * Vector3.new(1, 0, 1)).Unit)
			character:PivotTo(CFrame.new(at) * turn * (p.root.CFrame:Inverse() * character:GetPivot()))
		else
			character:PivotTo(character:GetPivot() + (at - p.root.Position))
		end
		p.root.AssemblyLinearVelocity = Vector3.zero
		if k >= 1 then active[bot] = nil end
	end
end

return Pull
