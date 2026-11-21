-- FEAR EATER on players' computers: how his body moves (MonsterAnimate slides it into place and
-- calls `animate` here every frame). Everything is procedural (no animation files): each frame
-- works out the joints' Transforms. His numbers and the kill's timing are in HeroData.FearEater.
--
--   FLOATING - he hovers, rising and sinking slowly; moving, he glides level, sways side to side
--              and tips forward the faster he goes. The forearms drift and the claws flex.
--   HUNTING  - while chasing he raises his hands, spread a little, claws working, and bobs with
--              each "stride" (by distance travelled, so it keeps pace with his speed).
--   DEVOUR   - gathers himself (leans back, arms drawn back), then throws himself forward with
--              both hands thrust out ("DevourAt" etc. on the body, from the server).
--   INSTILL FEAR - ("CastKind"/"CastAt") he rears up, arms flung wide, and a dark ring sweeps
--              out across the floor from him.
--   LIVING NIGHTMARE - he hunches in on himself, then for its duration ("NightmareUntil") turns
--              half see-through, trailing dark mist.
--   (These two are stand-ins, to be replaced by full animations.)
--   THE KILL - ("KillStart"/"KillVictim") his hands close on the victim, held off their feet in
--              front of him facing away, flailing. He winds his head back, lifting them, then
--              brings their head up into his hood and tips forward over them, laid flat; they keep
--              struggling in there until it dies away; he draws them back out and lets go, and the
--              body drops to the floor, lies there a few seconds, fades.
--
-- Joints (ServerStorage.FearEaterRig): Root (the root to the cloak), Left/Right Shoulder, Elbow,
-- Wrist, all Motor6Ds whose frames are lined up with the body, so Transform angles are in body
-- axes: about X tips forward (negative) or back, about Y turns, about Z rolls. The upper arms are
-- hidden inside the sleeves; the forearms move at the elbows, at the sleeve openings.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Heroes = require(ReplicatedStorage:WaitForChild("Heroes"))
local Characters = require(ReplicatedStorage:WaitForChild("Characters"))
local Victims = require(script.Parent.Parent:WaitForChild("Victims"))

local HERO = Heroes.list.FearEater
local K = HERO.kill

---------------------------------------------------------------- tuning
local HOVER_BOB    = 0.25    -- studs he rises and sinks while hovering in place...
local HOVER_RATE   = 0.45    -- ...cycles per second
local MOVE_BOB     = 0.2     -- studs of bob while chasing (none while just moving)...
local MOVE_STRIDE  = 9       -- ...once every this many studs travelled
local FULL_SPEED   = 24      -- speed that counts as "full speed" for leaning
local LEAN         = 0.16    -- radians he tips forward at full speed
local SWAY         = 0.05    -- radians he rolls side to side while moving
local REACH_EASE   = 4       -- how quickly his hands rise/fall when a chase starts/ends
-- the kill: where the victim is held (studs, from his root: x right, y up, z back)
local HOLD_AT      = Vector3.new(0, -0.1, -3.5)    -- in front of him, feet just off the floor
local RAISE_AT     = Vector3.new(0, 1.2, -3.0)     -- lifted as he winds back
local HEAD_TILT    = 1.35    -- radians the victim is tipped back once their head is in his hood (nearly flat, face up)
local HEAD_IN      = Vector3.new(0, -0.1, 0.25)   -- ...their head this far inside the hood's opening
local WIND_BACK    = 0.35    -- radians he tips back, winding his head back
local ENGULF_TIP   = -0.22   -- ...then forward, over them
-- THE GRIP: each palm on the side of the victim's chest, from grab to drop. The elbow and wrist
-- bend together (two-joint "inverse kinematics") so the palm lands there with the wrist behind
-- and outside them, and the claws wrap round to their front.
local GRIP_OUT     = 0.15    -- studs out from the side of their chest
local GRIP_UP      = 0.1     -- studs up from its middle
local WRIST_BACK   = 1.0     -- the wrist sits this much behind them...
local WRIST_OUT    = 0.6     -- ...and out to the side, so the hand comes round

local function lerp(a, b, t) return a + (b - a) * t end
local function smooth(x) x = math.clamp(x, 0, 1) return x * x * (3 - 2 * x) end

-- Seconds since `start` (server time). In Studio, the Workspace attribute `hold` (a number of
-- seconds) freezes every Fear Eater at that moment instead, for screenshots:
-- "KillPreviewAt" for the kill, "DevourPreviewAt" for the dash.
local IS_STUDIO = RunService:IsStudio()
local function clock(start, hold)
	local held = IS_STUDIO and workspace:GetAttribute(hold)
	if typeof(held) == "number" then return held end
	return workspace:GetServerTimeNow() - start
end

local FearEater = {}
local animate = {}
FearEater.animate = animate

---------------------------------------------------------------- setup
-- Measured in the rest pose (before any Transform): where the hood, elbows and wrists are, and
-- where each hand's grip is, in his own space (relative to his root).
function animate.setup(model, s)
	local fe = { joints = {}, t = math.random() * 10, stride = 0, sway = 0, reach = 0, arms = {} }
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then fe.joints[d.Name] = d end
	end
	local pivot = model:GetPivot()
	local cloak = model:FindFirstChild("Cloak")
	local hood = cloak and cloak:FindFirstChild("Hood")
	fe.hood = hood and pivot:PointToObjectSpace(hood.WorldPosition) or Vector3.new(0, 3.7, -0.3)
	fe.floor = -(model:GetAttribute("GroundOffset") or 4)
	for _, side in { "Left", "Right" } do
		local elbow, wrist = fe.joints[side .. "Elbow"], fe.joints[side .. "Wrist"]
		local hand = model:FindFirstChild(side .. "Hand")
		local grip = hand and hand:FindFirstChild("Grip")
		if elbow and wrist and grip then
			local e = pivot:PointToObjectSpace((elbow.Part0.CFrame * elbow.C0).Position)
			local w = pivot:PointToObjectSpace((wrist.Part0.CFrame * wrist.C0).Position)
			local g = pivot:PointToObjectSpace(grip.WorldPosition)
			fe.arms[side] = { elbow = e, forearm = w - e, hand = g - w, sx = side == "Left" and -1 or 1 }
		end
	end
	s.fe = fe
end

-- Elbow and wrist rotations that put the hand's grip on `target`, with the wrist bent out toward
-- `pole` (both in his own space). Forearm and hand are two straight pieces: the triangle they make
-- with the line to the target gives the forearm's angle off that line (the law of cosines).
local function grip(fe, side, target, pole)
	local arm = fe.arms[side]
	local L1, L2 = arm.forearm.Magnitude, arm.hand.Magnitude
	local toTarget = target - arm.elbow
	if toTarget.Magnitude < 0.1 then return CFrame.identity, CFrame.identity end
	local u = toTarget.Unit
	local d = math.clamp(toTarget.Magnitude, math.abs(L1 - L2) + 0.05, L1 + L2 - 0.05)
	local a = math.acos(math.clamp((L1 * L1 + d * d - L2 * L2) / (2 * L1 * d), -1, 1))
	local p = pole - u * pole:Dot(u)
	if p.Magnitude < 0.01 then p = Vector3.yAxis - u * u.Y end
	p = p.Unit
	local forearm = u * math.cos(a) + p * math.sin(a)
	local elbowRot = CFrame.fromRotationBetweenVectors(arm.forearm, forearm)
	local wristAt = arm.elbow + forearm * L1
	-- the wrist's frame turns with the forearm, so the hand's direction is worked out in that frame
	local handDir = elbowRot:VectorToObjectSpace(target - wristAt)
	if handDir.Magnitude < 0.01 then return elbowRot, CFrame.identity end
	return elbowRot, CFrame.fromRotationBetweenVectors(arm.hand, handDir)
end

---------------------------------------------------------------- the pose, every frame
function animate.pose(model, s, dt)
	local fe = s.fe
	local j = fe.joints
	if not j.Root then return end
	fe.t += dt
	s.speed += ((s.targetSpeed or 0) - s.speed) * math.min(1, dt * 6)
	local speed = s.speed
	local move = math.clamp(speed / 4, 0, 1)
	local run = math.clamp(speed / FULL_SPEED, 0, 1)
	fe.stride = (fe.stride + dt * speed / MOVE_STRIDE) % 1
	fe.sway = (fe.sway + dt * speed / (MOVE_STRIDE * 2)) % 1

	-- FLOATING: hover bob standing still; moving, level (or a stride bob while chasing); tipping
	-- forward with speed
	fe.reach += ((s.mode == "chase" and 1 or 0) - fe.reach) * math.min(1, dt * REACH_EASE)
	local hover = math.sin(fe.t * math.pi * 2 * HOVER_RATE) * HOVER_BOB
	local strideBob = (math.sin(fe.stride * math.pi * 2) * MOVE_BOB + hover * 0.4) * fe.reach
	local bob = lerp(hover, strideBob, move)
	local pitch = -LEAN * run
	local roll = math.sin(fe.sway * math.pi * 2) * SWAY * move
	local yaw = math.sin(fe.sway * math.pi * 2 + 0.6) * 0.04 * move

	-- ARMS. elbowPitch > 0 raises the hands; elbowIn > 0 brings them together; wrist < 0 curls the claws
	local reach = fe.reach
	local arms = {}
	for side, arm in fe.arms do
		local phase = arm.sx * 1.3
		local drift = math.sin(fe.t * 1.2 + phase) * 0.06 * (1 - move)
		local trail = 0.1 * run                                   -- moving fast, the hands lift a little
		local claw = math.sin(fe.t * 7 + phase * 2)
		arms[side] = {
			pitch = drift + trail + reach * (0.3 + claw * 0.05),
			inward = math.sin(fe.t * 0.9 + phase) * 0.04 - reach * 0.08,
			wrist = math.sin(fe.t * 1.5 + phase) * 0.1 * (1 - reach) + reach * (-0.15 + claw * 0.3),
		}
	end

	-- DEVOUR: gather (lean back, arms drawn back), then thrust forward, then ease back to normal
	local devourAt = model:GetAttribute("DevourAt")
	if devourAt and not s.killStart then
		local d = clock(devourAt, "DevourPreviewAt")
		local windup = model:GetAttribute("DevourWindup") or 0.15
		local dashTime = model:GetAttribute("DevourTime") or 0.3
		local into = smooth((d - windup) / 0.08)
		local gather = smooth(d / math.max(windup, 0.01)) * (1 - into)
		local thrust = into * (1 - smooth((d - windup - dashTime - 0.15) / 0.35))
		if d < windup + dashTime + 0.6 then
			pitch = lerp(lerp(pitch, 0.18, gather), -0.38, thrust)
			bob = lerp(bob, 0.3, thrust)
			for _, a in arms do
				a.pitch = lerp(lerp(a.pitch, 0.3, gather), 0.45, thrust)
				a.inward = lerp(lerp(a.inward, -0.25, gather), 0.12, thrust)
				a.wrist = lerp(lerp(a.wrist, 0.2, gather), 0.35, thrust)
			end
		end
	end

	-- CASTS: Instill Fear (rearing up, arms flung wide) and Living Nightmare (hunching in)
	local castAt = model:GetAttribute("CastAt")
	if castAt and not s.killStart then
		local c = clock(castAt, "CastPreviewAt")
		local kind = model:GetAttribute("CastKind")
		if kind == "InstillFear" and c < 1.2 then
			local up = smooth(c / 0.2) * (1 - smooth((c - 0.6) / 0.4))
			pitch = lerp(pitch, 0.25, up)
			bob = lerp(bob, 0.6, up)
			for _, a in arms do
				a.pitch = lerp(a.pitch, 0.9, up)
				a.inward = lerp(a.inward, -0.5, up)
				a.wrist = lerp(a.wrist, 0.5, up)
			end
		elseif kind == "LivingNightmare" and c < 1 then
			local hunch = smooth(c / 0.15) * (1 - smooth((c - 0.35) / 0.4))
			pitch = lerp(pitch, -0.45, hunch)
			bob = lerp(bob, -0.6, hunch)
			for _, a in arms do
				a.pitch = lerp(a.pitch, -0.2, hunch)
				a.inward = lerp(a.inward, 0.3, hunch)
				a.wrist = lerp(a.wrist, -0.6, hunch)
			end
		end
	end

	local elbows, wrists = {}, {}
	for side, a in arms do
		local arm = fe.arms[side]
		elbows[side] = CFrame.Angles(a.pitch, a.inward * arm.sx, 0)
	end

	-- THE KILL
	local k = s.killStart and clock(s.killStart, "KillPreviewAt") or nil
	local v = fe.victim
	if k and k < K.DONE + 0.4 then
		local grab = smooth(k / K.GRAB)
		local settle = 1 - smooth((k - K.RELEASE) / (K.DONE + 0.4 - K.RELEASE))   -- back to normal at the end
		local wind = smooth((k - K.WIND) / (K.ENGULF - K.WIND))
		local engulf = smooth((k - K.ENGULF) / 0.3)
		local w = grab * settle
		local out = smooth((k - K.OUT) / 0.4)
		local killPitch = (wind * WIND_BACK * (1 - engulf) + engulf * ENGULF_TIP) * (1 - out * 0.7)
		pitch = lerp(pitch, killPitch, w)
		bob = lerp(bob, 0.3 + math.sin(k * 3) * 0.05, w)
		roll = lerp(roll, 0, w)
		yaw = lerp(yaw, 0, w)
		-- hands gripping the sides of their chest, wherever they're being held; letting go and
		-- opening at the release
		local open = smooth((k - K.RELEASE) / 0.25)
		for side, arm in fe.arms do
			local heldElbow, heldWrist = elbows[side], CFrame.Angles(arms[side].wrist, 0, 0)
			if v and v.local_ then
				-- their chest's frame, in his space: x their right, z their back
				local chest = v.local_ * CFrame.new(v.chest)
				local target = chest * Vector3.new(arm.sx * (v.chestHalf + GRIP_OUT), GRIP_UP, 0)
				local pole = chest:VectorToWorldSpace(Vector3.new(arm.sx * WRIST_OUT, 0, WRIST_BACK))
				heldElbow, heldWrist = grip(fe, side, target, pole)
			end
			-- a shudder while they struggle
			local struggle = 1 - smooth((k - K.FADE) / (K.STILL - K.FADE))
			heldElbow = heldElbow * CFrame.Angles(math.sin(k * 31 + arm.sx) * 0.03 * struggle, 0, 0)
			local released = CFrame.Angles(0.2, -0.35 * arm.sx, 0)
			elbows[side] = elbows[side]:Lerp(heldElbow:Lerp(released, open), w)
			wrists[side] = CFrame.Angles(arms[side].wrist, 0, 0):Lerp(heldWrist:Lerp(CFrame.Angles(0.3, 0, 0), open), w)
		end
	end

	j.Root.Transform = CFrame.new(0, bob, 0) * CFrame.Angles(pitch, yaw, roll)
	for side, cf in elbows do
		if j[side .. "Elbow"] then j[side .. "Elbow"].Transform = cf end
		if j[side .. "Wrist"] then j[side .. "Wrist"].Transform = wrists[side] or CFrame.Angles(arms[side].wrist, 0, 0) end
	end

	-- the victim struggling in his grip, wilder as they're lifted to the hood and inside it, until
	-- it dies away and they hang still
	if v and v.joints and v.character.Parent and k and k < K.RELEASE then
		local dying = smooth((k - K.FADE) / (K.STILL - K.FADE))
		local power = smooth(k / 0.3) * (1 - dying)
		power *= 1 + 0.4 * smooth((k - K.WIND) / (K.ENGULF - K.WIND))
		Victims.flail(v.joints, k, math.min(power, 1.3))
		Victims.limp(v.joints, dying, true)
		-- dead weight: as he draws them out of the hood the limp arms, legs and head swing
		local swing = math.sin(math.pi * math.clamp((k - K.OUT) / 0.7, 0, 1))
		if swing > 0 then
			for name, phase in { LeftShoulder = 0, RightShoulder = 1.3, LeftHip = 0.6, RightHip = 2.0, Neck = 0.9 } do
				local joint = v.joints[name]
				if joint then joint.Transform *= CFrame.Angles(math.sin(k * 7 + phase) * 0.25 * swing, 0, 0) end
			end
		end
	end
end

---------------------------------------------------------------- the victim
-- Where the victim is held, in his own space, k seconds into the kill
local function heldAt(fe, v, k)
	local hold = CFrame.new(HOLD_AT.X, math.max(HOLD_AT.Y, fe.floor + v.standHeight + 0.6), HOLD_AT.Z)
	local raise = CFrame.new(RAISE_AT) * CFrame.Angles(0.15, 0, 0)
	-- head in the hood: their head where the hood is, leaning back toward him
	local engulf = CFrame.new(fe.hood + HEAD_IN) * CFrame.Angles(HEAD_TILT, 0, 0)
		* CFrame.new(-v.headOffset)
	-- drawn back out: still flat, lower and further out in front
	local out = CFrame.new(0, -0.9, -1.8) * engulf
	local cf = v.from:Lerp(hold, smooth(k / K.GRAB))
	cf = cf:Lerp(raise, smooth((k - K.WIND) / (K.ENGULF - K.WIND)))
	cf = cf:Lerp(engulf, smooth((k - K.ENGULF) / 0.3))
	return cf:Lerp(out, smooth((k - K.OUT) / 0.4))
end

-- Every frame, after his body is in place: carry the victim in his hands, and at the release
-- swap them for a body that drops (or nothing, if he's hidden in the fog)
---------------------------------------------------------------- casts' effects
-- Instill Fear: a dark ring sweeping out across the floor from him
local function fearRing(model, fe)
	local floorAt = model:GetPivot().Position + Vector3.new(0, fe.floor + 0.25, 0)
	local ring = Instance.new("Part")
	ring.Name = "FearRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored, ring.CanCollide, ring.CanQuery, ring.CanTouch = true, false, false, false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(70, 20, 110)
	ring.Transparency = 0.25
	ring.Size = Vector3.new(0.2, 4, 4)
	ring.CFrame = CFrame.new(floorAt) * CFrame.Angles(0, 0, math.pi / 2)   -- (a cylinder's axis is X: stood on end)
	ring.Parent = workspace
	local tween = TweenService:Create(ring, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.2, 140, 140), Transparency = 1 })
	tween:Play()
	tween.Completed:Connect(function() ring:Destroy() end)
end

-- Living Nightmare: half see-through, trailing dark mist, while it lasts
local function setGhost(model, fe, on)
	if (fe.ghost or false) == on then return end
	fe.ghost = on
	if on then
		fe.solid = {}
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and part.Transparency < 1 then
				fe.solid[part] = part.Transparency
				part.Transparency = 0.55
			end
		end
		local root = model:FindFirstChild("HumanoidRootPart")
		if root then
			local mist = Instance.new("ParticleEmitter")
			mist.Name = "NightmareMist"
			mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
			mist.Color = ColorSequence.new(Color3.fromRGB(25, 10, 35))
			mist.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
			mist.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 7) })
			mist.Lifetime = NumberRange.new(0.8, 1.3)
			mist.Rate = 30
			mist.Speed = NumberRange.new(0.5, 1.5)
			mist.SpreadAngle = Vector2.new(180, 180)
			mist.LightEmission = 0
			mist.Parent = root
			fe.mist = mist
		end
	else
		for part, t in fe.solid or {} do
			if part.Parent then part.Transparency = t end
		end
		fe.solid = nil
		if fe.mist then fe.mist:Destroy() fe.mist = nil end
	end
end

local function effects(model, fe)
	local castAt = model:GetAttribute("CastAt")
	if castAt and castAt ~= fe.castSeen then
		fe.castSeen = castAt
		local fresh = workspace:GetServerTimeNow() - castAt < 1
		if fresh and model:GetAttribute("CastKind") == "InstillFear" and model:GetAttribute("FogState") ~= "hidden" then
			fearRing(model, fe)
		end
	end
	setGhost(model, fe, (model:GetAttribute("NightmareUntil") or 0) > workspace:GetServerTimeNow())
	if fe.mist then fe.mist.Enabled = model:GetAttribute("FogState") ~= "hidden" end   -- (no giving him away through the fog)
end

function animate.victim(model, s)
	local fe = s.fe
	effects(model, fe)
	local killStart = model:GetAttribute("KillStart")
	if killStart and killStart ~= fe.killSeen then
		fe.killSeen = killStart
		local character = Characters.of(model:GetAttribute("KillVictim"))
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			character.Archivable = true
			local head = character:FindFirstChild("Head")
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			-- their head and everything on it (hair, hats), hidden once it's inside the hood
			local headParts = {}
			if head then
				table.insert(headParts, head)
				for _, d in character:GetChildren() do
					-- (accessories are held on by welds or rigid constraints: just go by where they are)
					local handle = d:IsA("Accessory") and d:FindFirstChild("Handle")
					if handle and handle:IsA("BasePart") and (handle.Position - head.Position).Magnitude < 2.5 then
						table.insert(headParts, handle)
					end
				end
				for _, d in head:GetDescendants() do
					if d:IsA("Decal") then table.insert(headParts, d) end
				end
			end
			-- their chest: where it is from their root, and half its width (for the grip)
			local chest = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso") or root
			fe.victim = {
				character = character, root = root, start = killStart, copy = character:Clone(), headParts = headParts,
				chest = root.CFrame:PointToObjectSpace(chest.Position), chestHalf = chest.Size.X / 2,
				joints = Victims.joints(character),
				headOffset = head and root.CFrame:PointToObjectSpace(head.Position) or Vector3.new(0, 1.6, 0),
				standHeight = (humanoid and humanoid.HipHeight or 2) + root.Size.Y / 2,
			}
		end
	end
	local v = fe.victim
	if not v then return end
	local k = clock(v.start, "KillPreviewAt")
	local frame = model:GetPivot() * (fe.joints.Root and fe.joints.Root.Transform or CFrame.identity)
	local monsterHidden = model:GetAttribute("FogState") == "hidden"
	if k < K.RELEASE then
		if not v.root.Parent then return end
		if v.hidden ~= monsterHidden then
			v.hidden = monsterHidden
			Victims.hide(v.character, monsterHidden)
		end
		if not v.from then v.from = frame:ToObjectSpace(v.root.CFrame) end   -- where they were, in his space
		v.local_ = heldAt(fe, v, k)
		v.root.CFrame = frame * v.local_
		-- head swallowed by the hood (until it's drawn back out)
		local swallowed = k > K.ENGULF + 0.2 and k < K.OUT + 0.15
		if swallowed or v.swallowed then
			for _, part in v.headParts do part.LocalTransparencyModifier = (swallowed or monsterHidden) and 1 or 0 end
		end
		v.swallowed = swallowed
		return
	end
	-- the release
	if v.character.Parent and v.copy then
		if monsterHidden then
			Victims.hide(v.character)
		else
			Victims.corpse(v.character, v.copy, HERO.CORPSE_TIME)
		end
	end
	fe.victim = nil
end

return FearEater
