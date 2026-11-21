-- A monster played by a person.
--
--   local monster = PlayerMonster.new(player, maze, { onCatch = fn(player, monster), startCell = {x, z},
--                                                     hero = heroId })
--   monster:Step(dt, targets)   -- every frame, like MonsterAI (targets = survivors it may catch)
--   monster:Lunge()             -- the player clicked to lunge (checked here; the stand-in only)
--   monster:Devour(aim, distance, time, def)   -- Devour (from HeroAbilities.FearEater)
--   monster:Stun(seconds)       -- can't move, lunge or catch for a while
--   monster:Pull(to, speed)     -- their character dragged to `to` (Pull); -> seconds
--   monster:Destroy()
--
-- The player moves an ordinary character, made invisible (see Match), and this module dresses it
-- in the same monster body the AI uses (MonsterAI.buildBody): every frame it publishes where the
-- character is as the body's "Pivot" attribute, and MonsterAnimate on each computer moves and
-- animates the body from that - the gait, the reaching arms, the kill. (On the player's own
-- computer the body follows their character directly, so it never lags behind their controls.)
--
-- CATCHING (a hero monster): with its abilities - Fear Eater's Devour is a dash much like the
-- lunge below (its numbers in HeroData), sent to the player's computer as "DevourAt" etc. on the
-- body, which carries them (MonsterControls) while the server checks for a catch.
--
-- CATCHING (the stand-in): by lunging. The player's computer crouches them for Config.LUNGE_WINDUP seconds, then
-- carries them Config.LUNGE_DISTANCE studs forward; during that time any survivor within
-- Config.LUNGE_REACH of them is caught (checked here, on the server). A miss means waiting
-- Config.LUNGE_COOLDOWN seconds to lunge again. A catch plays the kill (MonsterAI.killFor), during
-- which the monster can't move (the player's "Killing" attribute; see Controls).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Config)
local MonsterAI = require(ServerStorage.MonsterAI)
local Pull = require(ServerStorage.Pull)
local SpeedCheck = require(ServerStorage.SpeedCheck)
local Heroes = require(ReplicatedStorage.Heroes)
local CATCH_GRACE = 4      -- seconds a just-caught survivor is ignored
local LATENCY_SLACK = 0.3  -- the lunge's catch window stays open this much longer (positions arrive late)

local PlayerMonster = {}
PlayerMonster.__index = PlayerMonster

function PlayerMonster.new(player, maze, options)
	options = options or {}
	local self = setmetatable({}, PlayerMonster)
	self.player = player
	self.maze = maze
	self.onCatch = options.onCatch or function() end
	self.model, self.groundOffset, self.isRig = MonsterAI.buildBody(options.hero)
	self.hero = self.model:GetAttribute("Hero")
	self.kill = MonsterAI.killFor(self.hero)
	local heroDef = Heroes.get(self.hero)
	self.canLunge = not (heroDef and heroDef.lunge == false)
	self.model.Name = "Monster_" .. player.Name
	self.model:SetAttribute("OwnerUserId", player.UserId)   -- whose body this is (MonsterAnimate, fog)
	local start = options.startCell or { math.ceil(maze.n / 2), math.ceil(maze.n / 2) }
	self.startCell = start
	self.pos = Vector3.new((start[1] - 0.5) * maze.S - maze.half, maze.floorY, (start[2] - 0.5) * maze.S - maze.half)
	self.startPos = self.pos      -- (pos follows the character from now on; this stays put)
	self.facing = Vector3.new(0, 0, -1)
	self.path = {}               -- (unused; Doors clears it on monsters)
	self.mode = "roam"
	self.active = false          -- false = can't catch (the countdown)
	self.graceUntil = {}
	self.cooldownUntil = 0
	self:publish()
	return self
end

function PlayerMonster:Destroy()
	if self.model then self.model:Destroy() end
	self.model = nil
	if self.player.Parent then
		self.player:SetAttribute("Killing", nil)
		self.player:SetAttribute("StunnedUntil", nil)
	end
end

-- Put the player's (new) character at the start spot. Until this is done, the body ignores the
-- character - it first appears on the start sanctuary's spawn pad, where survivors would see it.
function PlayerMonster:PlaceCharacter(character)
	character:PivotTo(self:StartCFrame())
	self.placed = character
end

-- Where the start cell's centre is, raised to standing height (for placing the character)
function PlayerMonster:StartCFrame()
	local at = self.startPos + Vector3.new(0, 4, 0)
	return CFrame.lookAt(at, at + Vector3.new(0, 0, 1))
end

local function rootOf(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then return character:FindFirstChild("HumanoidRootPart") end
	return nil
end

function PlayerMonster:publish()
	local model = self.model
	if not model then return end
	local at = self.isRig and self.pos + Vector3.new(0, self.groundOffset, 0)
		or self.pos + Vector3.new(0, MonsterAI.HOVER, 0)
	local pivot = CFrame.lookAt(at, at + self.facing)
	if model:GetAttribute("Pivot") ~= pivot then model:SetAttribute("Pivot", pivot) end
	if model:GetAttribute("Mode") ~= self.mode then model:SetAttribute("Mode", self.mode) end
end

-- Stunned: the player's character can't move (Movement reads "StunnedUntil"), and they can't
-- lunge or catch. A lunge under way is called off.
-- Mid-kill: can't be stunned or pulled (as for AI monsters, see MonsterAI:Killing)
function PlayerMonster:Killing()
	return self.killUntil ~= nil and os.clock() < self.killUntil
end

function PlayerMonster:Stun(seconds)
	if self:Killing() then return end
	self.reach, self.reachForward, self.dashAim = nil, nil, nil
	self.stunUntil = math.max(self.stunUntil or 0, os.clock() + seconds)
	local untilServer = workspace:GetServerTimeNow() + (self.stunUntil - os.clock())
	self.player:SetAttribute("StunnedUntil", untilServer)
	if self.model then self.model:SetAttribute("StunnedUntil", untilServer) end
	self.lungeHitFrom, self.lungeUntil = nil, nil
end

function PlayerMonster:Pull(to, speed)
	if self:Killing() then return 0 end
	return Pull.character(self.player, to, speed)
end

-- The player clicked to lunge. Returns true if it started.
function PlayerMonster:Lunge()
	local now = os.clock()
	if not self.canLunge or not self.active or self.killUntil or now < self.cooldownUntil then return false end
	if now < (self.stunUntil or 0) then return false end
	if not rootOf(self.player) then return false end
	self.lungeHitFrom = now + Config.LUNGE_WINDUP
	self.lungeUntil = self.lungeHitFrom + Config.LUNGE_TIME + LATENCY_SLACK
	self.cooldownUntil = self.lungeUntil + Config.LUNGE_COOLDOWN
	self.mode = "chase"           -- arms up and reaching
	return true
end

-- DEVOUR (HeroAbilities.FearEater worked out where to): the player's computer holds them still for
-- def.windup, then carries them `distance` studs along `aim` in `time` seconds; meanwhile the first
-- survivor within def.reach of a point def.reachForward ahead of them is caught.
function PlayerMonster:Devour(aim, distance, time, def)
	local now = os.clock()
	if not self.active or self.killUntil or now < (self.stunUntil or 0) then return false end
	if not rootOf(self.player) then return false end
	self.lungeHitFrom = now + def.windup
	self.lungeUntil = self.lungeHitFrom + time + LATENCY_SLACK
	self.reach, self.reachForward, self.dashAim = def.reach, def.reachForward, aim
	self.facing = aim
	self.mode = "chase"
	SpeedCheck.grant(self.player, distance + 4)        -- their computer carries them this far
	local model = self.model
	model:SetAttribute("DevourAim", aim * distance)
	model:SetAttribute("DevourWindup", def.windup)
	model:SetAttribute("DevourTime", time)
	model:SetAttribute("DevourAt", workspace:GetServerTimeNow())
	self:publish()
	return true
end

-- LIVING NIGHTMARE (HeroAbilities.FearEater): for def.duration seconds their character is in the
-- "Nightmare" collision group (through inner walls and doors) and sped toward feared survivors
-- ("NightmareUntil"/"NightmareBoost", read by Movement and SpeedCheck). The body shows it too.
-- onEnd(character) runs when it wears off (pushing them out of a wall they ended inside).
function PlayerMonster:Nightmare(def, onEnd)
	if not self.active or self.killUntil or os.clock() < (self.stunUntil or 0) then return false end
	local character = self.player.Character
	if not rootOf(self.player) then return false end
	local untilServer = workspace:GetServerTimeNow() + def.duration
	local function setGroup(group)
		for _, d in character:GetDescendants() do
			if d:IsA("BasePart") then d.CollisionGroup = group end
		end
	end
	setGroup("Nightmare")
	self.player:SetAttribute("NightmareBoost", def.speedBoost)
	self.player:SetAttribute("NightmareUntil", untilServer)
	self.model:SetAttribute("NightmareUntil", untilServer)
	self.model:SetAttribute("CastKind", "LivingNightmare")
	self.model:SetAttribute("CastAt", workspace:GetServerTimeNow())
	task.delay(def.duration, function()
		if (self.player:GetAttribute("NightmareUntil") or 0) > workspace:GetServerTimeNow() + 0.05 then return end  -- cast again since
		self.player:SetAttribute("NightmareUntil", nil)
		if self.model then self.model:SetAttribute("NightmareUntil", nil) end
		if character.Parent then
			setGroup("MonsterPlayers")
			onEnd(character)
		end
	end)
	return true
end

function PlayerMonster:Step(dt, targets)
	if not self.model then return end
	local now = os.clock()
	local root = self.placed == self.player.Character and rootOf(self.player) or nil
	if root then
		self.pos = Vector3.new(root.Position.X, self.maze.floorY, root.Position.Z)
		local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
		if look.Magnitude > 0.01 and not self.killUntil then self.facing = look.Unit end   -- (faces its victim while killing)
	end

	-- the kill playing out: stand still until it's over
	if self.killUntil then
		if now < self.killUntil then
			self:publish()
			return
		end
		self.killUntil = nil
		self.mode = "roam"
		self.model:SetAttribute("KillVictim", nil)
		self.model:SetAttribute("KillStart", nil)
		self.player:SetAttribute("Killing", nil)
	end

	if self.lungeUntil and now > self.lungeUntil then
		self.lungeUntil, self.lungeHitFrom = nil, nil
		self.reach, self.reachForward, self.dashAim = nil, nil, nil
		self.mode = "roam"
	end

	-- the lunge: catch the first survivor within reach
	if self.active and root and self.lungeHitFrom and now >= self.lungeHitFrom then
		-- (Devour reaches from a point ahead of them, where the hands are)
		local reachAt = root.Position + (self.dashAim or Vector3.zero) * (self.reachForward or 0)
		for _, player in targets do
			local theirRoot = rootOf(player)
			if theirRoot and (self.graceUntil[player] or 0) < now and not player:GetAttribute("Seized") then
				local flat = (theirRoot.Position - reachAt) * Vector3.new(1, 0, 1)
				if flat.Magnitude < (self.reach or Config.LUNGE_REACH) and not self:wallBetween(root.Position, theirRoot.Position) then
					self:catch(player, flat, now)
					break
				end
			end
		end
	end
	self:publish()
end

-- A wall between two points (at waist height)? The lunge can't catch through one.
function PlayerMonster:wallBetween(a, b)
	if not self.rayParams then
		self.rayParams = RaycastParams.new()
		self.rayParams.FilterType = Enum.RaycastFilterType.Include
		self.rayParams.FilterDescendantsInstances = { self.maze.model }
	end
	local y = self.maze.floorY + 3
	local from, to = Vector3.new(a.X, y, a.Z), Vector3.new(b.X, y, b.Z)
	local hit = workspace:Raycast(from, to - from, self.rayParams)
	return hit ~= nil and hit.Instance.CanCollide
end

function PlayerMonster:catch(player, toThem, now)
	self.graceUntil[player] = now + CATCH_GRACE
	self.lungeUntil, self.lungeHitFrom = nil, nil
	self.reach, self.reachForward, self.dashAim = nil, nil, nil
	self.cooldownUntil = now + self.kill.DONE
	if toThem.Magnitude > 0.1 then self.facing = toThem.Unit end
	self.mode = "kill"
	self.killUntil = now + self.kill.DONE
	self.player:SetAttribute("Killing", true)     -- holds the monster still (Controls)
	self.model:SetAttribute("KillVictim", player.UserId)
	self.model:SetAttribute("KillStart", workspace:GetServerTimeNow())
	self:publish()
	self.onCatch(player, self)
end

return PlayerMonster
