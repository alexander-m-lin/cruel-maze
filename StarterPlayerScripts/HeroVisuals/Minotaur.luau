-- THE MINOTAUR on players' computers: how his body moves (MonsterAnimate slides it into place and
-- calls `animate` here every frame), and how his abilities look. Everything is procedural (no
-- animation files): each frame works out the joints' Transforms. His numbers and the kill's timing
-- are in HeroData.Minotaur.
--
--   WALKING  - a heavy, stiff-legged stomp (his legs are single pieces: they swing from the hips,
--              and the body drops as they spread so the hooves stay on the floor), arms swinging
--              against them, the weight rolling side to side; he leans in with speed, and breathes
--              when standing. Chasing ("Mode" chase), he drops his head, horns first, arms out.
--   TEAR ASUNDER - ("DevourAt"/"DevourGo", as Devour) rears back with his arms spread wide for the
--              windup, then lunges, arms closing.
--   THE KILL - ("KillStart"/"KillVictim") he grabs them, lifts them overhead between his fists,
--              struggling, and tears them in two (Victims.tear), arms flung apart.
--   DEVASTATING CHARGE - ("ChargeAt" ...) for the windup he lowers his horns and paws the floor,
--              and a red LANE shows his path to the wall (anyone who can see him sees it; his side
--              always); then he gallops along it, kicking up dust; at the wall ("ChargeEnd") a
--              burst of dust and he reels, shaking his head. Survivors he TRAMPLES ("Trampled", from
--              the server) are flung aside and drop.
--   CRUSH    - ("LeapAt" ...) he crouches, leaps in a high arc with his arms going up overhead, and
--              slams them down as he lands. For the last moments a red RING shows where, drawn
--              above the fog and the walls, to his side and to survivors near it; at the impact a
--              shockwave runs out over it ("CrushImpact").
--   AIMING CRUSH - (hold E) a faint circle shows his range and a ring where he'd land.
--
-- Joints (ServerStorage.MinotaurRig): Root (the root to the torso), Neck, Left/RightShoulder,
-- Left/RightHip, all Motor6Ds whose frames are lined up with the body (facing -Z), so Transform
-- angles are in body axes: about X tips forward (negative) or back, swings a limb forward
-- (positive) or back; about Z the left limb goes out with a negative angle, the right with positive.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Net = require(ReplicatedStorage:WaitForChild("Net"))
local Heroes = require(ReplicatedStorage:WaitForChild("Heroes"))
local Characters = require(ReplicatedStorage:WaitForChild("Characters"))
local Victims = require(script.Parent.Parent:WaitForChild("Victims"))

local HERO = Heroes.list.Minotaur
local K = HERO.kill
local CHARGE = HERO.abilities.Secondary
local CRUSH = HERO.abilities.Ultimate
local player = Players.LocalPlayer
local fxEvent = Net.event("AbilityFx")

---------------------------------------------------------------- tuning
local STRIDE      = 13      -- studs travelled per full walk cycle (both legs)
local LEG_SWING   = 0.38    -- radians the legs swing walking...
local LEG_RUN     = 0.5     -- ...and at full speed
local ARM_SWING   = 0.3     -- radians the arms swing against them
local ARMS_OUT    = 0.1     -- radians the arms hang out from his sides (they're huge)
local FULL_SPEED  = 28      -- speed that counts as "full speed" (a chase boost on top of 24)
local LEAN        = 0.14    -- radians he leans in at full speed
local ROLL        = 0.05    -- radians his weight rolls side to side each step
local REACH_EASE  = 4       -- how quickly the chase pose comes and goes
local HEAD_DOWN   = 0.35    -- radians his head drops chasing (horns forward)
local GALLOP_RATE = 3.2     -- full leg cycles a second, charging
local THROW_SPEED = 22      -- how fast the torn halves fly apart (studs per second)
local REMAINS_TIME = 6      -- seconds the pieces lie about
local FLING_SPEED = 45      -- how fast someone he tramples is flung (studs per second, his way)
local RED = Color3.fromRGB(255, 45, 30)
local DUST = Color3.fromRGB(150, 130, 105)
local ABOVE_FOG = 1.3       -- studs above the wall tops the Crush ring floats (fog and walls never hide it)

local function lerp(a, b, t) return a + (b - a) * t end
local function smooth(x) x = math.clamp(x, 0, 1) return x * x * (3 - 2 * x) end

-- Seconds since `start` (server time). In Studio, a number in the Workspace attribute `hold` freezes
-- every Minotaur at that moment instead, for screenshots: "KillPreviewAt", "DevourPreviewAt",
-- "CastPreviewAt" (his Charge and Crush).
local IS_STUDIO = RunService:IsStudio()
local function clock(start, hold)
	local held = IS_STUDIO and workspace:GetAttribute(hold)
	if typeof(held) == "number" then return held end
	return workspace:GetServerTimeNow() - start
end

local folder = Instance.new("Folder")
folder.Name = "MinotaurEffects"
folder.Parent = workspace

local function maze() return workspace:FindFirstChild("Maze") end
local function floorY()
	local m = maze()
	return m and m:GetAttribute("FloorY") or 0
end
local function wallTop()
	local m = maze()
	return floorY() + (m and m:GetAttribute("WallHeight") or 7)
end
local function onMonsterSide()
	local role = player:GetAttribute("Role")
	return role == Config.Roles.Monster or role == Config.Roles.MazeMaster
end

local function part(name, size, color, transparency)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Neon
	p.Color = color or RED
	p.Transparency = transparency or 0
	p.Size = size or Vector3.one * 0.2
	p.Parent = folder
	return p
end

-- A flat bar on the floor (or any height) from a to b
local function bar(p, a, b, width)
	local length = (b - a).Magnitude
	p.Size = Vector3.new(width, 0.1, math.max(length, 0.05))
	local mid = (a + b) / 2
	p.CFrame = length > 0.01 and CFrame.lookAt(mid, mid + (b - a).Unit) or CFrame.new(mid)
end

-- A puff of dust at `at`
local function dustBurst(at, count, speed)
	local p = part("Dust", Vector3.one * 0.2, DUST, 1)
	p.Position = at
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(DUST)
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 6) })
	e.Lifetime = NumberRange.new(0.6, 1.2)
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.SpreadAngle = Vector2.new(180, 40)
	e.Drag = 4
	e.Rate = 0
	e.Parent = p
	e:Emit(count)
	Debris:AddItem(p, 2)
end

-- Raised above the fog: drawn `raise` studs higher and shifted back toward the camera by as much,
-- so on screen it still sits where it would on the floor
local function aboveFog(y)
	local raise = wallTop() + ABOVE_FOG - y
	local d = Config.CAMERA_DIRECTION
	return Vector3.new(d.X, 0, d.Z) * (raise / d.Y) + Vector3.yAxis * raise
end

local Minotaur = {}
local animate = {}
Minotaur.animate = animate

---------------------------------------------------------------- setup
-- Measured in the rest pose: his legs' length (hip to the floor), and where each fist is on its arm
function animate.setup(model, s)
	local mt = { joints = {}, t = math.random() * 10, phase = 0, reach = 0, fists = {} }
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then mt.joints[d.Name] = d end
	end
	local scale = model:GetScale()
	local box, size = model:GetBoundingBox()
	local bottom = box.Position.Y - size.Y / 2
	local hip = mt.joints.LeftHip
	mt.legLength = hip and ((hip.Part0.CFrame * hip.C0).Position.Y - bottom) or 5 * scale
	mt.floor = bottom - model:GetPivot().Position.Y            -- (his root's height off the floor, negated)
	for _, side in { "Left", "Right" } do
		local arm = model:FindFirstChild(side .. "Arm")
		if arm then
			mt.fists[side] = { part = arm, offset = Vector3.new(0, -(arm.Size.Y / 2 - 0.9 * scale), -0.3 * scale) }
		end
	end
	s.mt = mt
end

local function fistAt(mt, side)
	local f = mt.fists[side]
	return f and (f.part.CFrame * f.offset) or nil
end

---------------------------------------------------------------- the pose, every frame
function animate.pose(model, s, dt)
	local mt = s.mt
	local j = mt.joints
	if not j.Root then return end
	mt.t += dt
	s.speed += ((s.targetSpeed or 0) - s.speed) * math.min(1, dt * 6)
	local speed = s.speed
	local move = math.clamp(speed / 4, 0, 1)
	local run = math.clamp(speed / FULL_SPEED, 0, 1)
	local L = mt.legLength
	mt.phase = (mt.phase + dt * speed / STRIDE) % 1
	local cycle = math.sin(mt.phase * math.pi * 2)
	mt.reach += ((s.mode == "chase" and 1 or 0) - mt.reach) * math.min(1, dt * REACH_EASE)
	local reach = mt.reach

	-- WALKING: the pose everything else starts from
	local legSwing = cycle * lerp(LEG_SWING, LEG_RUN, run) * move
	local hipL, hipR = legSwing, -legSwing
	local spreadL, spreadR = 0, 0
	local breathe = math.sin(mt.t * 1.8) * 0.06 * (1 - move)
	local y = breathe
	local pitch = -LEAN * run
	local roll = cycle * ROLL * move
	local yaw = legSwing * 0.12
	local neck, neckYaw = -HEAD_DOWN * reach + LEAN * run * 0.5, 0
	local armSwing = -cycle * ARM_SWING * move
	local idleSway = math.sin(mt.t * 1.1) * 0.05 * (1 - move)
	local shL = armSwing + idleSway + 0.25 * reach
	local shR = -armSwing - idleSway + 0.25 * reach
	local outL = ARMS_OUT + 0.25 * reach + breathe * 0.5
	local outR = ARMS_OUT + 0.25 * reach + breathe * 0.5

	-- TEAR ASUNDER: rear back, arms spread wide, then lunge with them closing
	local devourAt = model:GetAttribute("DevourAt")
	if devourAt and not s.killStart then
		local d = clock(devourAt, "DevourPreviewAt")
		local windup = model:GetAttribute("DevourWindup") or 0.3
		local go = model:GetAttribute("DevourGo")
		if go and go >= devourAt and go - devourAt < windup + 0.5 then windup = go - devourAt end
		local dashTime = model:GetAttribute("DevourTime") or 0.3
		local into = smooth((d - windup) / 0.08)
		local gather = smooth(d / math.max(windup, 0.01)) * (1 - into)
		local thrust = into * (1 - smooth((d - windup - dashTime - 0.2) / 0.35))
		if d < windup + dashTime + 0.6 then
			pitch = lerp(lerp(pitch, 0.18, gather), -0.32, thrust)
			neck = lerp(lerp(neck, 0.15, gather), -0.25, thrust)
			shL = lerp(lerp(shL, 1.7, gather), 1.35, thrust)
			shR = lerp(lerp(shR, 1.7, gather), 1.35, thrust)
			outL = lerp(lerp(outL, 0.75, gather), -0.12, thrust)
			outR = lerp(lerp(outR, 0.75, gather), -0.12, thrust)
			hipL = lerp(hipL, 0.4, thrust)
			hipR = lerp(hipR, -0.3, thrust)
		end
	end

	-- DEVASTATING CHARGE
	local now = workspace:GetServerTimeNow()
	local chargeAt = model:GetAttribute("ChargeAt")
	local chargeEnd = model:GetAttribute("ChargeEnd")
	if chargeAt and not s.killStart then
		local c = clock(chargeAt, "CastPreviewAt")
		local ended = chargeEnd and chargeEnd >= chargeAt
		local go = model:GetAttribute("ChargeGo")
		local running = go and go >= chargeAt and not ended
		local e = ended and (now - chargeEnd) or nil
		local recovery = model:GetAttribute("ChargeRecovery") or CHARGE.recovery
		-- head down, horns forward (windup and run, easing off once it's over)
		local lower = smooth(c / 0.25) * (ended and (1 - smooth(e / 0.25)) or 1)
		if lower > 0 then
			pitch = lerp(pitch, -0.45, lower)
			y = lerp(y, -0.5, lower)
			neck = lerp(neck, -0.55, lower)
			shL = lerp(shL, -0.75, lower)
			shR = lerp(shR, -0.75, lower)
			outL = lerp(outL, 0.45, lower)
			outR = lerp(outR, 0.45, lower)
			if running then
				-- galloping: legs thrashing far faster than his walk
				local g = math.sin((now - go) * GALLOP_RATE * math.pi * 2) * 0.75
				hipL, hipR = g, -g
				y -= L * (1 - math.cos(g)) + 0.1
				roll = g * 0.06
				pitch -= 0.08
			else
				-- the windup: one hoof planted, the other pawing the floor
				hipL = lerp(hipL, 0.25, lower)
				hipR = lerp(hipR, -0.35 + math.sin(c * math.pi * 2 * 2.2) * 0.4, lower)
				y -= L * (1 - math.cos(0.35)) * lower
			end
		end
		-- the impact: rocked back, shaking his head, arms flung out
		if ended and recovery > 0 and e < recovery + 0.4 then
			local reel = 1 - smooth((e - recovery) / 0.4)
			pitch = lerp(pitch, 0.25, reel)
			neck = lerp(neck, 0.2, reel)
			neckYaw = math.sin(e * 25) * 0.35 * reel * (1 - e / (recovery + 0.4))
			shL = lerp(shL, 0.5, reel)
			shR = lerp(shR, 0.5, reel)
			outL = lerp(outL, 0.65, reel)
			outR = lerp(outR, 0.65, reel)
		end
	end

	-- CRUSH: crouch, leap (arms going up overhead), slam them down as he lands
	local leapAt = model:GetAttribute("LeapAt")
	if leapAt and not s.killStart then
		local l = clock(leapAt, "CastPreviewAt")
		local windup = model:GetAttribute("LeapWindup") or CRUSH.windup
		local crouch = model:GetAttribute("LeapCrouch") or CRUSH.crouch
		local height = model:GetAttribute("LeapHeight") or CRUSH.height
		local recovery = model:GetAttribute("LeapRecovery") or CRUSH.recovery
		if l < windup + recovery + 0.4 then
			local air = windup - crouch
			local k = math.clamp((l - crouch) / air, 0, 1)
			local crouched = smooth(l / crouch) * (1 - smooth((l - crouch) / 0.1))
			local up = l >= crouch and l < windup
			local raise = up and smooth(k / 0.55) or 0                   -- arms going up...
			local slam = up and smooth((k - 0.75) / 0.25) or 0           -- ...and down as he lands
			local landed = l >= windup and 1 - smooth((l - windup) / (recovery + 0.4)) or 0
			-- crouched: legs spread, body down, arms back
			spreadL, spreadR = lerp(spreadL, -0.35, crouched), lerp(spreadR, 0.35, crouched)
			y = lerp(y, -L * (1 - math.cos(0.35)) - 0.2, crouched)
			pitch = lerp(pitch, -0.3, crouched)
			shL, shR = lerp(shL, -0.9, crouched), lerp(shR, -0.9, crouched)
			-- in the air: the arc (his whole body: the root rises), legs trailing
			if up then
				y = height * 4 * k * (1 - k)
				hipL, hipR = lerp(0, -0.35, smooth(k / 0.3)), lerp(0, -0.15, smooth(k / 0.3))
				pitch = lerp(0.1, -0.35, slam)
				shL = lerp(lerp(-0.9, 2.9, raise), 0.6, slam)
				shR = shL
				outL, outR = lerp(0.3, 0.05, raise), lerp(0.3, 0.05, raise)
				neck = lerp(0.1, -0.3, slam)
			end
			-- landed: crouched over the impact, arms down in front, getting up again
			if landed > 0 then
				spreadL, spreadR = lerp(spreadL, -0.35, landed), lerp(spreadR, 0.35, landed)
				y = lerp(y, -L * (1 - math.cos(0.35)) - 0.3, landed)
				pitch = lerp(pitch, -0.4, landed)
				shL, shR = lerp(shL, 0.6, landed), lerp(shR, 0.6, landed)
				outL, outR = lerp(outL, 0.15, landed), lerp(outR, 0.15, landed)
				neck = lerp(neck, -0.3, landed)
				hipL, hipR = lerp(hipL, 0, landed), lerp(hipR, 0, landed)
			end
		end
	end

	-- THE KILL: grab, lift overhead between his fists, tear them in two
	local k = s.killStart and clock(s.killStart, "KillPreviewAt") or nil
	if k and k < K.DONE + 0.4 then
		local settle = 1 - smooth((k - (K.RIP + 0.4)) / (K.DONE + 0.4 - K.RIP - 0.4))
		local grab = smooth(k / K.GRAB) * settle
		local hold = smooth((k - K.GRAB) / (K.LIFT - K.GRAB)) * settle
		local fling = smooth((k - K.RIP) / 0.12) * settle
		local struggle = math.clamp((k - K.LIFT) / (K.RIP - K.LIFT), 0, 1) * (1 - fling)
		local shake = math.sin(k * 45) * 0.07 * struggle
		local strain = math.clamp((k - K.LIFT) / (K.RIP - K.LIFT), 0, 1) * (1 - fling)
		-- grabbing: both arms out in front, closing
		shL, shR = lerp(shL, 1.35, grab), lerp(shR, 1.35, grab)
		outL, outR = lerp(outL, -0.1, grab), lerp(outR, -0.1, grab)
		-- holding them up: arms straight overhead, a little apart, pulling outward harder and harder
		shL, shR = lerp(shL, 2.75 + shake, hold), lerp(shR, 2.75 - shake, hold)
		outL, outR = lerp(outL, 0.12 + strain * 0.12, hold), lerp(outR, 0.12 + strain * 0.12, hold)
		-- the rip: arms flung down and out to the sides
		shL, shR = lerp(shL, 1.9, fling), lerp(shR, 1.9, fling)
		outL, outR = lerp(outL, 1.35, fling), lerp(outR, 1.35, fling)
		neck = lerp(neck, 0.55 * (1 - fling * 0.6), hold)
		pitch = lerp(pitch, 0.12 * (1 - fling), hold)
		roll = lerp(roll, 0, grab)
		yaw = lerp(yaw, 0, grab)
		hipL, hipR = lerp(hipL, 0, grab), lerp(hipR, 0, grab)
		spreadL, spreadR = lerp(spreadL, -0.12, hold), lerp(spreadR, 0.12, hold)
		y = lerp(y, -L * (1 - math.cos(0.12)), hold)
	end

	j.Root.Transform = CFrame.new(0, y, 0) * CFrame.Angles(pitch, yaw, roll)
	if j.Neck then j.Neck.Transform = CFrame.Angles(neck, neckYaw, 0) end
	if j.LeftShoulder then j.LeftShoulder.Transform = CFrame.Angles(shL, 0, -outL) end
	if j.RightShoulder then j.RightShoulder.Transform = CFrame.Angles(shR, 0, outR) end
	if j.LeftHip then j.LeftHip.Transform = CFrame.Angles(hipL, 0, spreadL) end
	if j.RightHip then j.RightHip.Transform = CFrame.Angles(hipR, 0, spreadR) end

	-- the victim struggling in his grip until the rip
	local v = mt.victim
	if v and v.joints and v.character.Parent and k and k < K.RIP then
		Victims.flail(v.joints, k, math.min(1, smooth(k / 0.3) * (0.7 + 0.3 * math.clamp((k - K.LIFT) / (K.RIP - K.LIFT), 0, 1))))
	end
end

---------------------------------------------------------------- the victim
-- Held overhead between his fists: lying across them, head toward his left fist, face up
local function gripFrame(mt)
	local l, r = fistAt(mt, "Left"), fistAt(mt, "Right")
	if not (l and r) then return nil end
	local along = (l - r).Magnitude > 0.1 and (l - r).Unit or Vector3.xAxis
	local back = -Vector3.yAxis - along * along:Dot(-Vector3.yAxis)
	back = back.Magnitude > 0.01 and back.Unit or Vector3.zAxis
	local at = (l + r) / 2 + Vector3.new(0, 1.2, 0) - along * 0.8   -- (the root sits at the hips, below the middle)
	return CFrame.fromMatrix(at, along:Cross(back), along, back), along
end

local function updateVictim(model, mt)
	local killStart = model:GetAttribute("KillStart")
	if killStart and killStart ~= mt.killSeen then
		mt.killSeen = killStart
		local character = Characters.of(model:GetAttribute("KillVictim"))
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			character.Archivable = true
			mt.victim = { character = character, root = root, from = root.CFrame, copy = character:Clone(),
				start = killStart, joints = Victims.joints(character) }
		end
	end
	local v = mt.victim
	if not v then return end
	local k = clock(v.start, "KillPreviewAt")
	local monsterHidden = model:GetAttribute("FogState") == "hidden"
	if k < K.RIP then
		if not v.root.Parent then return end
		if v.hidden ~= monsterHidden then
			v.hidden = monsterHidden
			Victims.hide(v.character, monsterHidden)
		end
		local grip, along = gripFrame(mt)
		if grip then
			v.root.CFrame = v.from:Lerp(grip, smooth(k / K.GRAB))
			v.side = along
		end
		return
	end
	if v.character.Parent and v.copy then
		if monsterHidden then
			Victims.hide(v.character)                   -- torn apart out of sight: no pieces to see
		else
			Victims.tear(v.character, v.copy, v.side or Vector3.xAxis, THROW_SPEED, REMAINS_TIME)
		end
	end
	mt.victim = nil
end

---------------------------------------------------------------- Charge: the lane, the dust, the impact
local function chargeEffects(model, mt)
	local now = workspace:GetServerTimeNow()
	local chargeAt, chargeEnd, go = model:GetAttribute("ChargeAt"), model:GetAttribute("ChargeEnd"), model:GetAttribute("ChargeGo")
	local ended = chargeAt and chargeEnd and chargeEnd >= chargeAt
	local running = chargeAt and go and go >= chargeAt and not ended
	local winding = chargeAt and not ended and not running and now - chargeAt < (model:GetAttribute("ChargeWindup") or 1) + 0.5
	local seen = model:GetAttribute("FogState") ~= "hidden" or onMonsterSide()

	-- THE LANE (the windup): from him along his path to where it ends, a charge's width across
	local dir, to = model:GetAttribute("ChargeDir"), model:GetAttribute("ChargeTo")
	if winding and seen and typeof(dir) == "Vector3" and typeof(to) == "Vector3" then
		if not mt.lane then
			mt.lane = {
				fill = part("ChargeLane", nil, RED, 0.75),
				left = part("ChargeEdge", nil, RED, 0.2),
				right = part("ChargeEdge", nil, RED, 0.2),
				front = part("ChargeEdge", nil, RED, 0.2),
			}
		end
		local y = floorY() + 0.12
		local from = model:GetPivot().Position
		local a = Vector3.new(from.X, y, from.Z)
		local b = Vector3.new(to.X, y, to.Z) + dir * CHARGE.bodyRadius
		if (b - a):Dot(dir) < 1 then b = a + dir end
		local side = Vector3.new(-dir.Z, 0, dir.X) * CHARGE.halfWidth
		local k = math.clamp((now - chargeAt) / (model:GetAttribute("ChargeWindup") or 1), 0, 1)
		local pulse = 0.5 + 0.5 * math.sin(now * (8 + 16 * k))
		bar(mt.lane.fill, a, b, CHARGE.halfWidth * 2)
		mt.lane.fill.Transparency = 0.82 - 0.12 * pulse * k
		bar(mt.lane.left, a + side, b + side, 0.35)
		bar(mt.lane.right, a - side, b - side, 0.35)
		bar(mt.lane.front, b - side, b + side, 0.35)
		for _, name in { "left", "right", "front" } do mt.lane[name].Transparency = 0.45 - 0.35 * k end
	elseif mt.lane then
		for _, p in mt.lane do p:Destroy() end
		mt.lane = nil
	end

	-- DUST kicked up while he runs
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and not mt.dust then
		local e = Instance.new("ParticleEmitter")
		e.Name = "ChargeDust"
		e.Texture = "rbxasset://textures/particles/smoke_main.dds"
		e.Color = ColorSequence.new(DUST)
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(1, 6) })
		e.Lifetime = NumberRange.new(0.5, 0.9)
		e.Speed = NumberRange.new(2, 5)
		e.SpreadAngle = Vector2.new(60, 20)
		e.Rate = 50
		e.Enabled = false
		local at = Instance.new("Attachment")
		at.Position = Vector3.new(0, mt.floor + 0.5, 1.5)
		at.Parent = root
		e.Parent = at
		mt.dust = e
	end
	if mt.dust then mt.dust.Enabled = running == true and model:GetAttribute("FogState") ~= "hidden" end

	-- THE IMPACT: a burst of dust against the wall
	if ended and chargeEnd ~= mt.impactSeen then
		mt.impactSeen = chargeEnd
		local stopAt = model:GetAttribute("ChargeStopAt")
		if now - chargeEnd < 0.6 and (model:GetAttribute("ChargeRecovery") or 0) > 0 and typeof(stopAt) == "Vector3"
			and typeof(dir) == "Vector3" and model:GetAttribute("FogState") ~= "hidden" then
			dustBurst(Vector3.new(stopAt.X, floorY() + 2, stopAt.Z) + dir * (CHARGE.bodyRadius + 0.5), 40, 18)
		end
	end
end

---------------------------------------------------------------- Crush: the ring
-- Who's shown it: his side, and survivors within its threatRange of the landing (fog or not)
local function threatened(at)
	if onMonsterSide() then return true end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and ((root.Position - at) * Vector3.new(1, 0, 1)).Magnitude <= CRUSH.threatRange
end

local RING_SEGMENTS = 48
local function crushEffects(model, mt)
	local leapAt, to = model:GetAttribute("LeapAt"), model:GetAttribute("LeapTo")
	local windup = model:GetAttribute("LeapWindup") or CRUSH.windup
	local left = leapAt and (windup - clock(leapAt, "CastPreviewAt")) or -1
	local show = typeof(to) == "Vector3" and left > 0 and left <= CRUSH.telegraph and threatened(to)
	if not show then
		if mt.ring then
			for _, p in mt.ring.edge do p:Destroy() end
			mt.ring.fill:Destroy()
			mt.ring = nil
		end
		return
	end
	if not mt.ring then
		local edge = {}
		for i = 1, RING_SEGMENTS do edge[i] = part("CrushEdge", nil, RED, 0.15) end
		local fill = part("CrushFill", nil, RED, 0.6)
		fill.Shape = Enum.PartType.Cylinder
		mt.ring = { edge = edge, fill = fill }
	end
	local y = floorY() + 0.1
	local lift = aboveFog(y)
	local center = Vector3.new(to.X, y, to.Z) + lift
	local r = CRUSH.radius
	for i, p in mt.ring.edge do
		local a1, a2 = (i - 1) / RING_SEGMENTS * math.pi * 2, i / RING_SEGMENTS * math.pi * 2
		bar(p, center + Vector3.new(math.cos(a1) * r, 0, math.sin(a1) * r), center + Vector3.new(math.cos(a2) * r, 0, math.sin(a2) * r), 0.5)
	end
	-- the fill grows to the edge as the impact comes
	local k = 1 - left / CRUSH.telegraph
	local fill = math.max(0.2, r * 2 * k)
	mt.ring.fill.Size = Vector3.new(0.1, fill, fill)
	mt.ring.fill.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2)
	mt.ring.fill.Transparency = 0.75 - 0.2 * k
end

function animate.victim(model, s)
	local mt = s.mt
	chargeEffects(model, mt)
	crushEffects(model, mt)
	updateVictim(model, mt)
end

---------------------------------------------------------------- the server's word
-- Crush's impact: a shockwave out over the ring (where it's shown) and dust (where you can see it)
local function crushImpact(at, radius)
	if not threatened(at) then return end
	local y = floorY() + 0.1
	local lift = aboveFog(y)
	local wave = part("CrushWave", Vector3.new(0.2, 2, 2), RED, 0.1)
	wave.Shape = Enum.PartType.Cylinder
	wave.CFrame = CFrame.new(Vector3.new(at.X, y, at.Z) + lift) * CFrame.Angles(0, 0, math.pi / 2)
	TweenService:Create(wave, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.2, radius * 2.4, radius * 2.4), Transparency = 1 }):Play()
	Debris:AddItem(wave, 0.6)
	dustBurst(Vector3.new(at.X, y + 1, at.Z), 50, 25)
end

-- Trampled by the charge: flung his way, up and aside, and dropping (unless you can't see them)
local function trampled(userId, dir)
	local character = Characters.of(userId)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	if character:GetAttribute("FogState") == "hidden" then
		Victims.hide(character)
		return
	end
	character.Archivable = true
	local copy = Victims.corpse(character, character:Clone(), HERO.CORPSE_TIME)
	local aside = Vector3.new(-dir.Z, 0, dir.X) * (math.random() < 0.5 and -1 or 1)
	for _, p in copy:GetDescendants() do
		if p:IsA("BasePart") then
			p.AssemblyLinearVelocity = dir * FLING_SPEED * (0.8 + math.random() * 0.3) + aside * 12
				+ Vector3.new(0, 22 + math.random() * 6, 0)
			p.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 18
		end
	end
	dustBurst(root.Position, 20, 12)
end

fxEvent.OnClientEvent:Connect(function(kind, userId, a, b)
	if kind == "Trampled" and typeof(a) == "Vector3" then
		trampled(userId, a)
	elseif kind == "CrushImpact" and typeof(a) == "Vector3" then
		crushImpact(a, b or CRUSH.radius)
	end
end)

---------------------------------------------------------------- aiming Crush (hold E)
local aimRange = part("CrushRange", nil, RED, 1)
aimRange.Shape = Enum.PartType.Cylinder
aimRange.Parent = nil
local aimSpot = part("CrushAim", nil, RED, 1)
aimSpot.Shape = Enum.PartType.Cylinder
aimSpot.Parent = nil

local UserInputService = game:GetService("UserInputService")
Minotaur.aim = {
	Ultimate = {
		update = function(_, def)
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not root then return end
			local y = floorY() + 0.1
			local at = Vector3.new(root.Position.X, y, root.Position.Z)
			aimRange.Size = Vector3.new(0.1, def.range * 2, def.range * 2)
			aimRange.CFrame = CFrame.new(at) * CFrame.Angles(0, 0, math.pi / 2)
			aimRange.Transparency = 0.9
			aimRange.Parent = folder
			-- where he'd land: the mouse on the floor, brought within range
			local target = at + root.CFrame.LookVector * Vector3.new(1, 0, 1) * def.range
			if UserInputService.MouseEnabled then
				local m = UserInputService:GetMouseLocation()
				local ray = workspace.CurrentCamera:ViewportPointToRay(m.X, m.Y)
				if math.abs(ray.Direction.Y) > 1e-4 then
					local t = (y - ray.Origin.Y) / ray.Direction.Y
					if t > 0 then target = ray.Origin + ray.Direction * t end
				end
			end
			local offset = (target - at) * Vector3.new(1, 0, 1)
			if offset.Magnitude > def.range then offset = offset.Unit * def.range end
			aimSpot.Size = Vector3.new(0.12, def.radius * 2, def.radius * 2)
			aimSpot.CFrame = CFrame.new(at + offset + Vector3.new(0, 0.02, 0)) * CFrame.Angles(0, 0, math.pi / 2)
			aimSpot.Transparency = 0.6
			aimSpot.Parent = folder
		end,
		hide = function()
			aimRange.Parent = nil
			aimSpot.Parent = nil
		end,
	},
}

return Minotaur
