-- Moves and animates the monster's body on each player's computer.
--
-- (Monsters played by people get the same body and the same treatment: see PlayerMonster.)
--
-- A HERO monster (its body has a "Hero" attribute, e.g. Fear Eater) is moved here (1, below) but
-- posed by its own module, StarterPlayerScripts.HeroVisuals.<hero>, which exports
--   animate.setup(model, s)      -- once, when the body appears (s: this script's state for it)
--   animate.pose(model, s, dt)   -- every frame: set the joints (s.targetSpeed, s.mode, s.killStart)
--   animate.victim(model, s)     -- every frame, after it's in place: carry a victim
-- Everything below about the gait and the kill is the stand-in monster's.
--
-- 1. SMOOTH MOVEMENT. The server publishes where the monster is in a "Pivot" attribute, about 30
--    times a second. Jumping straight to each update would look jittery (the screen draws 60+
--    times a second), so we show the monster slightly in the past - INTERP_DELAY seconds - and
--    slide it between the two updates either side of that moment ("interpolation").
-- 2. PROCEDURAL ANIMATION (no animation file). Every frame we work out an angle for each joint
--    and set the joint's Transform (the extra rotation it applies on top of its rest pose). The
--    stride advances with distance travelled, so the feet don't slide, and the gait gets bigger
--    and more frantic as the monster speeds up during a chase.
-- 3. THE KILL. When it catches someone (the server sets KillStart/KillVictim on the model) the
--    arms lift overhead, and the victim's body is shown held between its hands, thrashing and
--    shaking its head. At the rip the body is swapped for a copy that tears at the waist: the top
--    half is flung one way and the legs the other, along with the arms, and every limb comes
--    loose and scatters. All of this exists only on this computer.
--
-- Joint axes (R15, facing -Z): rotating about X swings a limb forward/back, about Z swings it out
-- to the side, about Y twists it.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Characters = require(game:GetService("ReplicatedStorage"):WaitForChild("Characters"))
local heroVisuals = script.Parent:WaitForChild("HeroVisuals")
local Victims = require(script.Parent:WaitForChild("Victims"))

---------------------------------------------------------------- tuning
local LIMP        = 0.35   -- 0 = even steps, higher = the right foot lifts less and drags its toes
local LEAN_WALK    = 0.10   -- extra forward lean (radians) when walking...
local LEAN_RUN     = 0.40   -- ...and at full sprint
local RUN_SPEED    = 24     -- speed counted as "full sprint" for lean/arm swing
local TWITCH_EVERY = { 1.5, 4 }  -- seconds between sudden head twitches (random in this range)
local REACH_ANGLE  = 0.75   -- when chasing, how far the arms raise forward (radians; ~0.7 = level)
local REACH_SPREAD = 0.15  -- ...and how far apart they spread
local REACH_EASE   = 4      -- how quickly it raises/lowers its arms when a chase starts/ends
local INTERP_DELAY = 0.08  -- show the monster this many seconds in the past, to move it smoothly
-- The kill (timing must match MonsterAI.KILL on the server): arms lift the victim overhead, hold
-- them shaking, then fling apart as they're torn in two
local KILL_LIFT, KILL_RIP, KILL_DONE = 0.7, 1.7, 2.6
local OVERHEAD    = 2.75   -- shoulder angle with the arms straight up (radians)
local FLING       = 1.5    -- how far the arms fling out to the sides at the rip
local GRIP_HALF   = 1.9    -- when holding someone, each hand is this far from the middle (studs)
local THROW_SPEED = 18     -- how fast the torn halves are flung apart (studs per second)
local REMAINS_TIME = 6     -- seconds the pieces lie about

---------------------------------------------------------------- helpers
local JOINT_NAMES = { "Root", "Waist", "Neck", "LeftShoulder", "RightShoulder", "LeftElbow",
	"RightElbow", "LeftWrist", "RightWrist", "LeftHip", "RightHip", "LeftKnee", "RightKnee",
	"LeftAnkle", "RightAnkle" }

local function findJoints(model)
	local joints = {}
	for _, d in model:GetDescendants() do
		if (d:IsA("Motor6D") or d:IsA("AnimationConstraint")) and table.find(JOINT_NAMES, d.Name) then
			joints[d.Name] = d
		end
	end
	return joints
end

local function lerp(a, b, t) return a + (b - a) * t end
local function rx(a) return CFrame.Angles(a, 0, 0) end

---------------------------------------------------------------- per-monster state
local monsters = {}  -- [model] = { samples, joints?, legLength, phase, speed, t, twitch... }

local function track(model)
	if monsters[model] then return end
	local s = { samples = {}, phase = 0, speed = 0, targetSpeed = 0, reach = 0, t = math.random() * 10,
		twitch = Vector2.zero, twitchTarget = Vector2.zero, twitchAt = 0 }

	-- Record each position update with the time it arrived
	local function record()
		local cf = model:GetAttribute("Pivot")
		if typeof(cf) ~= "CFrame" then return end
		table.insert(s.samples, { t = os.clock(), cf = cf })
		if #s.samples > 20 then table.remove(s.samples, 1) end
	end
	record()
	model:GetAttributeChangedSignal("Pivot"):Connect(record)

	-- A hero's body is posed by its own module
	local heroId = model:GetAttribute("Hero")
	local module = heroId and heroVisuals:FindFirstChild(heroId)
	local visuals = module and require(module)
	if visuals and visuals.animate then
		s.animator = visuals.animate
		s.animator.setup(model, s)
		monsters[model] = s
		return
	end

	-- Rigs get animated limbs; the fallback orb is only moved
	local joints = findJoints(model)
	if joints.LeftHip then
		s.joints = joints
		-- Leg length: hip joint to ankle joint (the part of the leg that swings; the foot below the
		-- ankle is kept flat, so it doesn't count)
		local function jointPos(joint)
			if joint:IsA("AnimationConstraint") then return joint.Attachment0.WorldPosition end
			return (joint.Part0.CFrame * joint.C0).Position
		end
		s.legLength = joints.LeftAnkle and (jointPos(joints.LeftHip) - jointPos(joints.LeftAnkle)).Magnitude or 3
		-- How far to angle the arms when holding someone, so the hands end up GRIP_HALF from the
		-- middle. Measured in the rest pose (before any animation): shoulders are w out from the
		-- middle, a hand is armLength from its shoulder, and the arms already hang outward at an
		-- angle (restOut) that has to be taken back off.
		s.leftHand = model:FindFirstChild("LeftHand", true)
		s.rightHand = model:FindFirstChild("RightHand", true)
		if joints.LeftShoulder and joints.RightShoulder and s.leftHand then
			local pivot = model:GetPivot()
			local sL = pivot:PointToObjectSpace(jointPos(joints.LeftShoulder))
			local sR = pivot:PointToObjectSpace(jointPos(joints.RightShoulder))
			local hL = pivot:PointToObjectSpace(s.leftHand.Position)
			local w = math.abs(sL.X - sR.X) / 2
			local armLength = (sL - hL).Magnitude
			local restOut = math.asin(math.clamp((math.abs(hL.X) - w) / armLength, -1, 1))
			local wanted = math.asin(math.clamp((GRIP_HALF - w) / armLength, -1, 1))
			s.holdOut = wanted - restOut
		end
	end
	monsters[model] = s
end

-- Where the monster should be shown right now: between the two updates either side of
-- (now - INTERP_DELAY). If updates stop (it's standing still), it stays at the last one.
local function smoothPivot(s)
	local samples = s.samples
	local n = #samples
	if n == 0 then return nil end
	local at = os.clock() - INTERP_DELAY
	if at >= samples[n].t then return samples[n].cf end
	for i = n - 1, 1, -1 do
		local a, b = samples[i], samples[i + 1]
		if at >= a.t then
			if (b.cf.Position - a.cf.Position).Magnitude > 20 then return b.cf end  -- teleported (new maze): don't slide
			return a.cf:Lerp(b.cf, (at - a.t) / (b.t - a.t))
		end
	end
	return samples[1].cf
end

CollectionService:GetInstanceAddedSignal("Monster"):Connect(function(m) task.defer(track, m) end)
CollectionService:GetInstanceRemovedSignal("Monster"):Connect(function(m) monsters[m] = nil end)
for _, m in CollectionService:GetTagged("Monster") do track(m) end

---------------------------------------------------------------- the gait
local function pose(s, dt)
	local j = s.joints
	s.t += dt
	s.speed += ((s.targetSpeed or 0) - s.speed) * math.min(1, dt * 6)
	local speed = s.speed

	local move = math.clamp(speed / 4, 0, 1)            -- 0 = standing still, 1 = walking
	local run = math.clamp(speed / RUN_SPEED, 0, 1)     -- 0 = walking, 1 = sprinting
	local amp = lerp(0.3, 0.55, run) * move             -- how far the legs swing (radians)

	-- LEGS. Each foot goes round a loop (its position relative to the hip):
	--   planted (first half of the cycle): slides straight back from +reach to -reach. Since the
	--     cycle advances by distance travelled, it moves back exactly as fast as the body moves
	--     forward - so in the world it stays put on the floor.
	--   swinging (second half): arcs forward, lifted off the floor, back to +reach.
	-- Then we work out the hip and knee angles that put the foot there ("inverse kinematics"),
	-- treating thigh and shin as equal halves of the leg.
	local L = s.legLength
	local reach = L * math.sin(amp)                     -- how far ahead/behind the hip a foot gets
	local stride = math.max(1, 4 * reach)               -- distance travelled per full cycle
	s.phase = (s.phase + dt * speed / stride) % 1
	local lift = lerp(0.5, 0.9, run) * move             -- how high a swinging foot lifts

	local function footAt(phase)  -- -> forward offset, height above floor
		if phase < 0.5 then
			return reach * (1 - 4 * phase), 0
		end
		local q = (phase - 0.5) / 0.5
		return -reach * math.cos(math.pi * q), math.sin(math.pi * q)
	end
	local phaseL, phaseR = s.phase, (s.phase + 0.5) % 1
	local xL, upL = footAt(phaseL)
	local xR, upR = footAt(phaseR)
	upL *= lift
	upR *= lift * (1 - LIMP)                            -- the right foot drags low

	-- The planted leg is straight, so the hip sits at height sqrt(L² - x²) - lower the body to match
	local xPlanted = phaseL < 0.5 and xL or xR
	local hipHeight = math.sqrt(math.max(0, L * L - xPlanted * xPlanted))

	local function legAngles(x, up)  -- -> hip angle, knee angle
		local down = hipHeight - up
		local dist = math.min(L, math.sqrt(x * x + down * down))
		local bend = 2 * math.acos(dist / L)              -- knee bend that shortens the leg to dist
		return math.atan2(x, down) + bend / 2, -bend
	end
	local hipL, kneeL = legAngles(xL, upL)
	local hipR, kneeR = legAngles(xR, upR)
	j.LeftHip.Transform = rx(hipL)
	j.RightHip.Transform = rx(hipR)
	j.LeftKnee.Transform = rx(kneeL)
	j.RightKnee.Transform = rx(kneeR)
	-- Ankles keep the foot flat (undo the hip + knee rotation); the dragging right foot's toes scuff
	if j.LeftAnkle then j.LeftAnkle.Transform = rx(-(hipL + kneeL)) end
	if j.RightAnkle then j.RightAnkle.Transform = rx(-(hipR + kneeR) - LIMP * 0.5 * upR / math.max(lift, 0.01)) end

	-- p: the cycle as an angle, with sin(p) = 1 when the left foot is furthest forward (for arms etc.)
	local p = s.phase * math.pi * 2 + math.pi / 2

	-- Body: drops to keep the planted foot on the floor, rolls side to side, leans in harder the
	-- faster it goes, and slowly "breathes" when standing
	local bob = L - hipHeight
	local breathe = math.sin(s.t * 1.6) * 0.03 * (1 - move)
	local lean = lerp(0, lerp(LEAN_WALK, LEAN_RUN, run), move)
	local roll = math.sin(p) * 0.08 * move
	-- (lean only at the waist: tilting the root would tilt the hips and lift the feet)
	j.Root.Transform = CFrame.new(0, -bob, 0) * CFrame.Angles(0, 0, roll)

	-- Arms. Two poses, blended by s.reach (0 = not chasing, 1 = chasing; eases between them):
	--   loose: long arms swing opposite the legs but lag behind, flop outward a little, and sway
	--          gently when standing
	--   reaching: raised forward toward you, spread apart, alternately clawing at the air
	local reachTarget = s.mode == "chase" and 1 or 0
	s.reach += (reachTarget - s.reach) * math.min(1, dt * REACH_EASE)
	local reach = s.reach

	local armAmp = lerp(0.15, 0.4, run) * move   -- small: the arms already hang forward at rest
	local lag = 0.6
	local idleSway = math.sin(s.t * 1.1) * 0.06 * (1 - move)
	local looseL = math.sin(p + math.pi - lag) * armAmp + idleSway - lean * 0.6
	local looseR = math.sin(p - lag) * armAmp - idleSway - lean * 0.6
	local claw = s.t * 7                         -- clawing rhythm, independent of the legs
	local reachL = REACH_ANGLE + math.sin(claw) * 0.12 + math.sin(p + math.pi) * 0.06
	local reachR = REACH_ANGLE + math.sin(claw + math.pi) * 0.12 + math.sin(p) * 0.06
	local shL = lerp(looseL, reachL, reach)
	local shR = lerp(looseR, reachR, reach)
	-- how far apart the arms spread
	local outward = lerp(0.08 + 0.1 * run, REACH_SPREAD, reach)
	local outL, outR = outward, outward
	-- Elbows: bend more on the forward swing; when reaching, nearly straight and flexing as it claws
	local elbowL = lerp(math.max(0, looseL) * 0.5 + 0.1, 0.15 + math.max(0, -math.sin(claw)) * 0.35, reach)
	local elbowR = lerp(math.max(0, looseR) * 0.5 + 0.1, 0.15 + math.max(0, math.sin(claw)) * 0.35, reach)
	-- Wrists: flop with the swing; when reaching, claws cock back then snap forward
	local wristL = lerp(math.sin(p + math.pi - lag * 2) * 0.3 * move, -0.35 + math.sin(claw - 0.8) * 0.35, reach)
	local wristR = lerp(math.sin(p - lag * 2) * 0.3 * move, -0.35 + math.sin(claw + math.pi - 0.8) * 0.35, reach)
	local lookUp, leanBack = 0, 0

	-- THE KILL: blend from the normal pose to "holding someone overhead", then to "arms flung apart"
	local k = s.killStart and (workspace:GetServerTimeNow() - s.killStart) or nil
	if k and k < KILL_DONE + 0.5 then
		local function smooth(x) x = math.clamp(x, 0, 1) return x * x * (3 - 2 * x) end
		local settle = 1 - smooth((k - (KILL_RIP + 0.5)) / (KILL_DONE + 0.5 - KILL_RIP - 0.5))  -- back to normal at the end
		local hold = smooth(k / KILL_LIFT) * settle
		local fling = smooth((k - KILL_RIP) / 0.12) * settle
		local struggle = math.clamp((k - KILL_LIFT) / (KILL_RIP - KILL_LIFT), 0, 1) * (1 - fling)
		local shake = math.sin(k * 45) * 0.08 * struggle
		-- holding: both arms straight up, slightly apart, elbows a little bent around the body
		shL = lerp(shL, OVERHEAD + shake, hold)
		shR = lerp(shR, OVERHEAD - shake, hold)
		outL = lerp(outL, s.holdOut or 0.2, hold)
		outR = lerp(outR, s.holdOut or 0.2, hold)
		elbowL = lerp(elbowL, 0.35, hold)
		elbowR = lerp(elbowR, 0.35, hold)
		wristL = lerp(wristL, 0, hold)
		wristR = lerp(wristR, 0, hold)
		-- the rip: arms swing down and out to the sides, straight
		shL = lerp(shL, 1.9, fling)
		shR = lerp(shR, 1.9, fling)
		outL = lerp(outL, FLING, fling)
		outR = lerp(outR, FLING, fling)
		elbowL = lerp(elbowL, 0.05, fling)
		elbowR = lerp(elbowR, 0.05, fling)
		-- looks up at its victim and leans back under the weight
		lookUp = 0.6 * hold * (1 - fling * 0.6)
		leanBack = 0.18 * hold * (1 - fling)
	end

	-- spread: rotating about Z moves the left arm out with a negative angle, the right with positive
	if j.LeftShoulder then j.LeftShoulder.Transform = CFrame.Angles(shL, 0, -outL) end
	if j.RightShoulder then j.RightShoulder.Transform = CFrame.Angles(shR, 0, outR) end
	if j.LeftElbow then j.LeftElbow.Transform = rx(elbowL) end
	if j.RightElbow then j.RightElbow.Transform = rx(elbowR) end
	if j.LeftWrist then j.LeftWrist.Transform = rx(wristL) end
	if j.RightWrist then j.RightWrist.Transform = rx(wristR) end
	j.Waist.Transform = CFrame.Angles(lean + breathe - leanBack, -math.sin(p) * 0.15 * move, -roll * 0.5)

	-- Head: stays level-ish against the bob, and every few seconds snaps to a new angle (a twitch),
	-- which reads as unsettling
	if s.t >= s.twitchAt then
		s.twitchAt = s.t + lerp(TWITCH_EVERY[1], TWITCH_EVERY[2], math.random())
		s.twitchTarget = Vector2.new((math.random() - 0.5) * 0.9, (math.random() - 0.5) * 0.5)
	end
	s.twitch = s.twitch:Lerp(s.twitchTarget, math.min(1, dt * 25))  -- fast = jerky
	j.Neck.Transform = CFrame.Angles(-lean * 0.7 + bob * 0.5 + s.twitch.Y - lookUp, s.twitch.X, s.twitch.X * 0.4)
end

---------------------------------------------------------------- the victim
local function smooth01(x) x = math.clamp(x, 0, 1) return x * x * (3 - 2 * x) end

-- Lying across the hands: head toward the left hand, face up, resting on the palms
local function gripFrame(s)
	local l, r = s.leftHand.Position, s.rightHand.Position
	local up = (l - r).Magnitude > 0.1 and (l - r).Unit or Vector3.xAxis
	local back = -Vector3.yAxis - up * up:Dot(-Vector3.yAxis)
	back = back.Magnitude > 0.01 and back.Unit or Vector3.zAxis
	local at = (l + r) / 2 + Vector3.new(0, 0.8, 0) - up * 0.8   -- the root sits at the hips, below the middle
	return CFrame.fromMatrix(at, up:Cross(back), up, back)
end

local function hide(character, hidden)
	if hidden == nil then hidden = true end
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then d.LocalTransparencyModifier = hidden and 1 or 0 end
	end
end

-- The victim's limb joints (classic Motor6Ds or newer AnimationConstraints), by name
local FLAIL_JOINTS = { "LeftShoulder", "RightShoulder", "LeftElbow", "RightElbow", "LeftHip", "RightHip",
	"LeftKnee", "RightKnee", "Neck" }
local function victimJoints(character)
	local found = {}
	for _, d in character:GetDescendants() do
		if (d:IsA("Motor6D") or d:IsA("AnimationConstraint")) and table.find(FLAIL_JOINTS, d.Name) then
			found[d.Name] = d
		end
	end
	return found
end

-- Struggling in its grip: arms and legs thrash, each on its own rhythm, and the head shakes side
-- to side. It builds up as they're lifted and gets wilder toward the rip.
local function flail(v, k)
	local j = v.joints
	local power = smooth01(k / KILL_LIFT) * (0.7 + 0.3 * math.clamp((k - KILL_LIFT) / (KILL_RIP - KILL_LIFT), 0, 1))
	local function set(name, cf) if j[name] then j[name].Transform = cf end end
	local function wave(speed, phase) return math.sin(k * speed + phase) end
	-- arms: windmilling forward and back, flung out to the sides, elbows bending
	set("LeftShoulder", CFrame.Angles(wave(13, 0) * 1.3 * power, 0, -(0.5 + wave(9, 1) * 0.5) * power))
	set("RightShoulder", CFrame.Angles(wave(14, 2.1) * 1.3 * power, 0, (0.5 + wave(10, 0.4) * 0.5) * power))
	set("LeftElbow", CFrame.Angles((0.7 + wave(17, 0.5) * 0.6) * power, 0, 0))
	set("RightElbow", CFrame.Angles((0.7 + wave(16, 2.7) * 0.6) * power, 0, 0))
	-- legs: kicking, out of step with each other
	set("LeftHip", CFrame.Angles(wave(15, 0) * 1.0 * power, 0, -0.2 * power))
	set("RightHip", CFrame.Angles(wave(15, math.pi) * 1.0 * power, 0, 0.2 * power))
	set("LeftKnee", CFrame.Angles(-(0.6 + wave(15, 0.8) * 0.6) * power, 0, 0))
	set("RightKnee", CFrame.Angles(-(0.6 + wave(15, math.pi + 0.8) * 0.6) * power, 0, 0))
	-- head: shaking side to side
	set("Neck", CFrame.Angles(0, wave(22, 0) * 0.7 * power, 0))
end

-- The rip: the body torn at the waist, the halves thrown apart the way the arms fling (Victims.tear)
local function rip(s, v)
	local side = v.side or (s.leftHand.Position - s.rightHand.Position).Unit
	Victims.tear(v.character, v.copy, side, THROW_SPEED, REMAINS_TIME)
end

local function updateVictim(model, s)
	local killStart = model:GetAttribute("KillStart")
	if killStart and killStart ~= s.killSeen and s.leftHand and s.rightHand then
		s.killSeen = killStart
		local userId = model:GetAttribute("KillVictim")
		local character = Characters.of(userId)   -- a player or a survivor bot
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			character.Archivable = true
			s.victim = { character = character, root = root, from = root.CFrame, copy = character:Clone(), start = killStart,
				joints = victimJoints(character) }
		end
	end
	local v = s.victim
	if not v then return end
	local k = workspace:GetServerTimeNow() - v.start
	-- The victim is only seen if the monster holding them is: otherwise (the monster hidden in the
	-- fog) a teammate would float up into the air on their own
	local monsterHidden = model:GetAttribute("FogState") == "hidden"
	if k < KILL_RIP then
		if v.root.Parent and v.hidden ~= monsterHidden then
			v.hidden = monsterHidden
			hide(v.character, monsterHidden)
		end
		-- held: from where they stood into the hands, then wherever the hands go
		if v.root.Parent then
			local grip = gripFrame(s)
			v.root.CFrame = v.from:Lerp(grip, smooth01(k / 0.3))
			v.side = grip.UpVector             -- head-ward: the way the top half gets thrown
		end
		return
	end
	if v.character.Parent then
		if monsterHidden then
			hide(v.character)                      -- torn apart out of sight: no pieces to see
		else
			rip(s, v)                              -- (if the body is already gone, there's nothing to tear)
		end
	end
	s.victim = nil
end

-- Every frame before drawing: slide each monster to its smoothed position, and measure how fast
-- it's moving (for the gait)
RunService.RenderStepped:Connect(function(dt)
	for model, s in monsters do
		if not model.Parent then
			monsters[model] = nil
			continue
		end
		local cf = smoothPivot(s)
		-- Your own monster body (you're playing a monster): follow your character directly, so it
		-- never lags behind your controls. Mid-kill it stays where your character is but faces the
		-- way the server says (its victim); the server's position lags behind, and mid-dash that
		-- would make the body jump back as the kill starts.
		if cf and model:GetAttribute("OwnerUserId") == Players.LocalPlayer.UserId then
			local character = Players.LocalPlayer.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root then
				local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
				if model:GetAttribute("KillStart") or look.Magnitude < 0.01 then look = cf.LookVector end
				local at = Vector3.new(root.Position.X, cf.Position.Y, root.Position.Z)
				cf = CFrame.lookAt(at, at + look.Unit)
			end
		end
		if cf then
			if s.shown and dt > 0 then
				local moved = (cf.Position - s.shown.Position) * Vector3.new(1, 0, 1)
				s.targetSpeed = math.min(moved.Magnitude / dt, 60)  -- capped, so a teleport isn't a "sprint"
			end
			s.shown = cf
			model:PivotTo(cf)
		end
		if s.animator then
			s.animator.victim(model, s)
		else
			updateVictim(model, s)
		end
	end
end)

-- Joint angles. PreSimulation runs after Roblox's own animation step, so they aren't overwritten.
RunService.PreSimulation:Connect(function(dt)
	for model, s in monsters do
		if s.animator and model.Parent then
			s.mode = model:GetAttribute("Mode")
			s.killStart = model:GetAttribute("KillStart")
			s.animator.pose(model, s, dt)
			continue
		end
		if s.joints and model.Parent then
			s.mode = model:GetAttribute("Mode")
			s.killStart = model:GetAttribute("KillStart")
			pose(s, dt)
		end
		-- the victim struggling (until the rip)
		local v = s.victim
		if v and v.joints and v.character.Parent then
			local k = workspace:GetServerTimeNow() - v.start
			if k < KILL_RIP then flail(v, k) end
		end
	end
end)
