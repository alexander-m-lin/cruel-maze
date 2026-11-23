-- KAI's abilities on the server (his numbers: ReplicatedStorage.HeroData.Kai).
-- Each handler gets (ctx, cast): see Abilities for both. Return true if it was used (the cooldown
-- starts), or false (and maybe a message for the player) if not.
--
-- SCANNER: the cone is fixed when he starts it, published on him for every computer: "ScanFrom"
-- (floor point), "ScanDir" (flat, unit), "ScanCone" (degrees), "ScanRange" (studs), "ScanAt" (server
-- time it starts seeing) and "ScanUntil". Survivors' fog sees the whole cone through walls meanwhile
-- (FogOfWar: monsters, doors, crushing walls and wards in it show as they would in plain sight);
-- here, relics (real and false) and wards in it are spotted for the team, as if seen.
--
-- EMP: after def.activation, every door, crushing wall and ward within def.radius of where he cast
-- it is disrupted for def.duration (Doors:Jam, Crushers:Jam, WardEyes:Disable). Everyone's computer
-- is told ("EMP": centre, radius, pulse time, end time) to draw the blue circle there.
--
-- ENCRYPT: ServerStorage.Encrypt (the circuit indicators). Ends early when he uses another ability
-- (Abilities) or starts collecting a relic or destroying a ward (Match).

local ServerStorage = game:GetService("ServerStorage")
local Encrypt = require(ServerStorage.Encrypt)

local handlers = {}

local function flat(v) return v * Vector3.new(1, 0, 1) end

-- SCANNER
function handlers.Scanner(ctx, cast)
	local match, user, root, aim, def = ctx.match, cast.user, cast.root, cast.aim, cast.def
	local maze, objectives = match.maze, match.objectives
	local from = Vector3.new(root.Position.X, maze.floorY, root.Position.Z)
	local now = workspace:GetServerTimeNow()
	local seesAt, endsAt = now + def.castTime, now + def.castTime + def.duration
	user:SetAttribute("ScanFrom", from)
	user:SetAttribute("ScanDir", aim)
	user:SetAttribute("ScanCone", def.cone)
	user:SetAttribute("ScanRange", def.range)
	user:SetAttribute("ScanAt", seesAt)
	user:SetAttribute("ScanUntil", endsAt)
	ctx.fx:FireAllClients("Scanner", user.UserId)
	local cos = math.cos(math.rad(def.cone / 2))
	local function inCone(p)
		local offset = flat(p - from)
		local d = offset.Magnitude
		return d <= def.range and (d < 1 or offset.Unit:Dot(aim) >= cos)
	end
	task.spawn(function()
		task.wait(def.castTime)
		while ctx.match == match and workspace:GetServerTimeNow() < endsAt and user:GetAttribute("ScanUntil") == endsAt do
			for _, relic in maze.relics do
				if not relic.collected and not relic.discovered and inCone(relic.center) then objectives:Discover(relic) end
			end
			for _, relic in objectives.fakes do
				if not relic.discovered and inCone(relic.center) then objectives:Discover(relic) end
			end
			for _, ward in match.wards and match.wards.list or {} do
				if not ward.info:GetAttribute("Discovered") and inCone(ward.center) then ward.info:SetAttribute("Discovered", true) end
			end
			task.wait(0.1)
		end
	end)
	return true
end

-- EMP
function handlers.EMP(ctx, cast)
	local match, user, root, def = ctx.match, cast.user, cast.root, cast.def
	local center = Vector3.new(root.Position.X, match.maze.floorY, root.Position.Z)
	local now = workspace:GetServerTimeNow()
	ctx.fx:FireAllClients("EMP", user.UserId, center, def.radius, now + def.activation, now + def.activation + def.duration)
	local function near(p) return flat(p - center).Magnitude <= def.radius end
	task.delay(def.activation, function()
		if ctx.match ~= match then return end
		if match.doors then
			for id, door in match.doors.list do
				if near(door.closedCF.Position) then match.doors:Jam(id, def.duration) end
			end
		end
		if match.crushers then
			for id, crusher in match.crushers.list do
				if near(crusher.center) then match.crushers:Jam(id, def.duration) end
			end
		end
		if match.wards then
			for _, ward in table.clone(match.wards.list) do
				if near(ward.center) then match.wards:Disable(ward, def.duration) end   -- (only wards there now)
			end
		end
	end)
	return true
end

-- ENCRYPT
function handlers.Encrypt(ctx, cast)
	local match, user, root, def = ctx.match, cast.user, cast.root, cast.def
	if not Encrypt.start(user, def, match.maze, match.objectives) then return false end
	ctx.fx:FireAllClients("Encrypt", user.UserId, root.Position)
	return true
end

return handlers
