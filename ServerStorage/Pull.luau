-- PULLING someone along a straight line (Sara's whip, and whatever else later pulls or knocks
-- people about). Reusable for survivors, survivor bots and monsters of both kinds.
--
--   local seconds = Pull.character(who, to, speed)   -- a player or bot (their character)
--   Pull.step()                                       -- every frame (Match): moves pulled bots
--
-- `to` is a floor point (only X and Z matter: they keep their height). Takes distance / speed
-- seconds, during which they can't move themselves (Movement.held).
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

function Pull.character(who, to, speed)
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
	if typeof(who) == "Instance" then
		SpeedCheck.grant(who, distance + 4)         -- their computer moves them this far
	else
		active[who] = { root = root, from = from, to = target, startedAt = os.clock(), time = seconds }
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
		character:PivotTo(character:GetPivot() + (at - p.root.Position))
		p.root.AssemblyLinearVelocity = Vector3.zero
		if k >= 1 then active[bot] = nil end
	end
end

return Pull
