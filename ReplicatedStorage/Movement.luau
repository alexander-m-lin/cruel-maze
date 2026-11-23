-- How fast a character may move, and its running animation's direction: the same rules for players
-- (Controls, on their own computer) and survivor bots (SurvivorBot, on the server). Only where the
-- input comes from differs: a player's mouse and keys, or a bot's brain.
--
--   local speed, angle = Movement.walkSpeed(who, humanoid, root, options)
--   Movement.setRunBackwards(humanoid, angle > Movement.BACKWARDS_FROM)
--
-- who: the player or bot (its attributes: BaseSpeed, Seized, Killing, Lunging, SlowUntil,
--   StunnedUntil, PullAt/PullTime, FearedUntil + FearSlow, NightmareUntil + NightmareBoost, ChaseBoost)
-- options.aiming: true when facing comes from aiming (the mouse) rather than from moving, so moving
--   away from where you face is slower (Config.FACING_*). A bot faces the way it walks.
-- options.collecting: true while collecting a relic (you face it, and move at the backwards speed)

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local Config = require(script.Parent:WaitForChild("Config"))

local Movement = {}

Movement.BACKWARDS_FROM = 100   -- moving more than this many degrees from your facing plays the run backwards

-- Speed multiplier for moving at `angle` degrees away from where you face:
-- full inside the front cone, slightly slower on the sides, much slower backwards.
-- Each change blends in over Config.FACING_BLEND degrees just past the zone's edge, so each zone
-- keeps its full speed right up to its edge (a sideways strafe at 90° gets the side speed).
function Movement.facingSpeed(angle)
	local frontEdge = Config.FACING_FULL_CONE / 2                 -- 50°
	local sideEdge = frontEdge + Config.FACING_SIDE_CONE          -- 90°
	local blend = Config.FACING_BLEND
	local toSide = math.clamp((angle - frontEdge) / blend, 0, 1)
	local toBack = math.clamp((angle - sideEdge) / blend, 0, 1)
	local side = 1 + (Config.FACING_SIDE_SPEED - 1) * toSide
	return side + (Config.FACING_BACK_SPEED - side) * toBack
end

-- Is `who` stunned, casting, or being pulled right now? ("StunnedUntil", "CastingUntil";
-- "PullAt" + "PullTime": server times)
function Movement.held(who)
	local now = workspace:GetServerTimeNow()
	if (who:GetAttribute("StunnedUntil") or 0) > now then return true end
	if (who:GetAttribute("CastingUntil") or 0) > now then return true end      -- winding up an ability (Flourish)
	local pullAt = who:GetAttribute("PullAt")
	return pullAt ~= nil and now < pullAt + (who:GetAttribute("PullTime") or 0)
end

-- Survivors (players and bots) who are feared right now: their HumanoidRootParts
local NIGHTMARE_CONE = 60      -- degrees either side of straight at a feared survivor that count as "toward"
function Movement.fearedRoots()
	local now = workspace:GetServerTimeNow()
	local roots = {}
	local function consider(holder, character)
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and (holder:GetAttribute("FearedUntil") or 0) > now then table.insert(roots, root) end
	end
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("Role") == Config.Roles.Survivor then consider(player, player.Character) end
	end
	for _, bot in CollectionService:GetTagged("SurvivorBot") do consider(bot, bot) end   -- (a bot's attributes are on its body)
	return roots
end

-- Moving (flat direction `move`) from `at` toward a feared survivor?
function Movement.towardFeared(at, move)
	if move.Magnitude < 0.1 then return false end
	local cos = math.cos(math.rad(NIGHTMARE_CONE))
	for _, root in Movement.fearedRoots() do
		local to = (root.Position - at) * Vector3.new(1, 0, 1)
		if to.Magnitude > 0.5 and to.Unit:Dot(move.Unit) >= cos then return true end
	end
	return false
end

-- Returns the walk speed, and the angle (degrees) between moving and facing
function Movement.walkSpeed(who, humanoid, root, options)
	options = options or {}
	-- held by a monster, killing someone (monster players), or crouched to lunge: can't move
	if who:GetAttribute("Seized") or who:GetAttribute("Killing") or who:GetAttribute("Lunging") then
		return 0, 0
	end
	-- stunned (a monster), or being pulled along by a whip (Pull): not under your own control
	if Movement.held(who) then return 0, 0 end
	local base = who:GetAttribute("BaseSpeed") or Config.PLAYER_SPEED
	local move = humanoid.MoveDirection * Vector3.new(1, 0, 1)
	local angle = 0
	if move.Magnitude > 0.1 then
		local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
		if look.Magnitude > 0.01 then
			angle = math.deg(math.acos(math.clamp(move.Unit:Dot(look.Unit), -1, 1)))
		end
	end
	local multiplier = 1
	if options.collecting then
		multiplier = Config.FACING_BACK_SPEED
	elseif options.aiming and move.Magnitude > 0.1 then
		multiplier = Movement.facingSpeed(angle)
	end
	-- tricked by a false relic: slowed for a while
	if (who:GetAttribute("SlowUntil") or 0) > workspace:GetServerTimeNow() then
		multiplier *= Config.FALSE_RELIC_SLOW
	end
	-- feared (Fear Eater's Instill Fear): slowed while it lasts
	if (who:GetAttribute("FearedUntil") or 0) > workspace:GetServerTimeNow() then
		multiplier *= who:GetAttribute("FearSlow") or 1
	end
	-- a monster player chasing a survivor they can see (PlayerMonster): faster the longer it lasts
	multiplier *= 1 + (who:GetAttribute("ChaseBoost") or 0)
	-- Fear Eater in his Living Nightmare: much faster while moving toward a feared survivor
	if (who:GetAttribute("NightmareUntil") or 0) > workspace:GetServerTimeNow() and Movement.towardFeared(root.Position, move) then
		multiplier *= 1 + (who:GetAttribute("NightmareBoost") or 0)
	end
	return base * multiplier, angle
end

-- Play the walk/run animation forwards or backwards (so legs match the way you move instead of
-- moonwalking). The Animate script keeps setting its speed (always positive) as you speed up and
-- slow down, so this flips the sign every frame.
local RUN_TRACKS = { RunAnim = true, WalkAnim = true }
function Movement.setRunBackwards(humanoid, backwards)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then return end
	for _, track in animator:GetPlayingAnimationTracks() do
		if RUN_TRACKS[track.Name] or (track.Animation and RUN_TRACKS[track.Animation.Name]) then
			local speed = track.Speed
			if (backwards and speed > 0) or (not backwards and speed < 0) then track:AdjustSpeed(-speed) end
		end
	end
end

return Movement
