-- Helpers for drawing a monster's victim on players' computers (MonsterAnimate, HeroVisuals):
-- hiding their body, finding its joints, making it struggle, and turning a copy of it into a limp
-- body that drops to the floor. Everything here exists only on this computer.
--
--   Victims.hide(character, hidden)          -- hide (or show again) a body
--   Victims.joints(character)                -- its limb joints by name (for flail / limp)
--   Victims.flail(joints, k, power)          -- thrash (k: seconds, for the rhythm; power 0..1)
--   Victims.limp(joints, amount)             -- hang limp (amount 0..1)
--   Victims.corpse(character, copy, lifetime) -- `copy` (a clone made earlier) takes the body's
--                                             -- place, posed the same, and falls loose; it fades
--                                             -- after `lifetime` seconds

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local Victims = {}

function Victims.hide(character, hidden)
	if hidden == nil then hidden = true end
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then d.LocalTransparencyModifier = hidden and 1 or 0 end
	end
end

-- The victim's limb joints (classic Motor6Ds or newer AnimationConstraints), by name
local FLAIL_JOINTS = { "LeftShoulder", "RightShoulder", "LeftElbow", "RightElbow", "LeftHip", "RightHip",
	"LeftKnee", "RightKnee", "Neck" }
function Victims.joints(character)
	local found = {}
	for _, d in character:GetDescendants() do
		if (d:IsA("Motor6D") or d:IsA("AnimationConstraint")) and table.find(FLAIL_JOINTS, d.Name) then
			found[d.Name] = d
		end
	end
	return found
end

-- Struggling: arms and legs thrash, each on its own rhythm, and the head shakes side to side
function Victims.flail(j, k, power)
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

-- Hanging limp: arms dangle a little out, knees slightly bent, head lolling forward
function Victims.limp(j, amount)
	local function set(name, cf) if j[name] then j[name].Transform = j[name].Transform:Lerp(cf, amount) end end
	set("LeftShoulder", CFrame.Angles(0.15, 0, -0.12))
	set("RightShoulder", CFrame.Angles(0.1, 0, 0.12))
	set("LeftElbow", CFrame.Angles(0.25, 0, 0))
	set("RightElbow", CFrame.Angles(0.3, 0, 0))
	set("LeftHip", CFrame.Angles(0.1, 0, 0))
	set("RightHip", CFrame.Angles(0.05, 0, 0))
	set("LeftKnee", CFrame.Angles(-0.3, 0, 0))
	set("RightKnee", CFrame.Angles(-0.25, 0, 0))
	set("Neck", CFrame.Angles(-0.6, 0.2, 0.15))
end

-- THE BODY: the copy is posed exactly like the victim, its joints swapped for loose ball-and-socket
-- joints (so it stays in one piece but flops), and dropped. The Humanoid stays (it's what shows
-- their clothes), but it stops arms and legs colliding, so each piece gets an invisible solid box
-- of its own, welded on; boxes joined to each other don't collide (they'd shove each other apart).
function Victims.corpse(character, copy, lifetime)
	for _, part in copy:GetDescendants() do
		if part:IsA("BasePart") then
			local original = character:FindFirstChild(part.Name, true)
			if original and original:IsA("BasePart") then part.CFrame = original.CFrame end
		end
	end
	for _, d in copy:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("IKControl") or d:IsA("Sound")
			or d:IsA("BallSocketConstraint") or d:IsA("HingeConstraint") then
			d:Destroy()
		end
	end
	local copyRoot = copy:FindFirstChild("HumanoidRootPart")
	local sockets = {}
	for _, d in copy:GetDescendants() do
		if d:IsA("Motor6D") or d:IsA("AnimationConstraint") then
			local p0 = d:IsA("Motor6D") and d.Part0 or (d.Attachment0 and d.Attachment0.Parent)
			local p1 = d:IsA("Motor6D") and d.Part1 or (d.Attachment1 and d.Attachment1.Parent)
			if p0 and p1 and p0 ~= copyRoot and p1 ~= copyRoot then
				local a0, a1
				if d:IsA("AnimationConstraint") then
					a0, a1 = d.Attachment0, d.Attachment1
				else
					a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
					a0.CFrame, a1.CFrame = d.C0, d.C1
					a0.Parent, a1.Parent = p0, p1
				end
				local socket = Instance.new("BallSocketConstraint")
				socket.Attachment0, socket.Attachment1 = a0, a1
				socket.LimitsEnabled = true
				socket.UpperAngle = 50
				socket.TwistLimitsEnabled = true
				socket.TwistLowerAngle, socket.TwistUpperAngle = -30, 30
				socket.Parent = p0
				table.insert(sockets, { p0, p1 })
			end
			d:Destroy()
		end
	end
	local humanoid = copy:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.EvaluateStateMachine = false
		humanoid.RequiresNeck = false
		humanoid.BreakJointsOnDeath = false
		humanoid.PlatformStand = true
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	if copyRoot then copyRoot:Destroy() end

	local boxes, parts = {}, {}
	for _, part in copy:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanQuery, part.CanTouch = false, false
			part.CanCollide = false
			table.insert(parts, part)
			if part:FindFirstAncestorOfClass("Accessory") then continue end   -- hats stay welded to the head
			local box = Instance.new("Part")
			box.Name = "Collider"
			box.Size, box.CFrame = part.Size * 0.85, part.CFrame
			box.Transparency = 1
			box.CanQuery, box.CanTouch = false, false
			box.CastShadow = false
			box.Massless = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1 = part, box
			weld.Parent = box
			box.Parent = part
			boxes[part] = box
		end
	end
	for _, pair in sockets do
		local a, b = boxes[pair[1]], boxes[pair[2]]
		if a and b then
			local nc = Instance.new("NoCollisionConstraint")
			nc.Part0, nc.Part1 = a, b
			nc.Parent = a
		end
	end
	copy.Name = "Corpse"
	copy.Parent = workspace
	Victims.hide(character)
	for _, part in parts do
		part.AssemblyLinearVelocity = Vector3.new(0, -2, 0)
		part.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 2
	end

	-- after `lifetime`: fade out over a second, then gone
	task.delay(lifetime, function()
		if not copy.Parent then return end
		local started = os.clock()
		local connection
		connection = RunService.RenderStepped:Connect(function()
			local t = math.clamp((os.clock() - started) / 1, 0, 1)
			for _, part in parts do
				if part.Parent then part.LocalTransparencyModifier = t end
			end
			for _, d in copy:GetDescendants() do
				if d:IsA("Decal") then d.LocalTransparencyModifier = t end
			end
			if t >= 1 then
				connection:Disconnect()
				copy:Destroy()
			end
		end)
	end)
	Debris:AddItem(copy, lifetime + 3)
	return copy
end

return Victims
