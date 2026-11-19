-- The relic-collecting effect: whoever is collecting a relic reaches out a hand toward it, and a
-- beam of light runs from their hand to the relic.
-- Runs on every player's computer, for every collector, so everyone sees it (the server says who
-- is collecting each relic in its "Collector" attribute; see Objectives). Everything made here
-- exists only on this computer.
--
-- The reaching arm uses an IKControl ("inverse kinematics"): Roblox bends the shoulder, elbow and
-- wrist so the hand points at the target, on top of whatever animation is playing.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local match = ReplicatedStorage:WaitForChild("Match")

local BEAM_COLOR = Color3.fromRGB(255, 214, 120)
local REACH_SPEED = 0.12      -- seconds the arm takes to swing up to the relic

local effects = {}   -- [relic info] = { character, ik, beam, light, parts... }

local function clear(info)
	local e = effects[info]
	if not e then return end
	for _, thing in e.cleanup do thing:Destroy() end
	effects[info] = nil
end

local function make(info, character, gem)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if not (humanoid and hand) then return nil end
	local cleanup = {}

	-- the arm: reach the hand toward the gem (R15 avatars; R6 arms can't bend, so they just glow)
	local upperArm = character:FindFirstChild("RightUpperArm")
	if upperArm then
		local ik = Instance.new("IKControl")
		ik.Name = "ReachForRelic"
		ik.Type = Enum.IKControlType.Position
		ik.ChainRoot = upperArm
		ik.EndEffector = hand
		ik.Target = gem
		ik.SmoothTime = REACH_SPEED
		ik.Weight = 1
		ik.Parent = humanoid
		table.insert(cleanup, ik)
	end

	-- the beam: from the palm to the gem
	local from = Instance.new("Attachment")
	from.Name = "RelicBeamStart"
	from.Position = Vector3.new(0, -hand.Size.Y / 2, 0)
	from.Parent = hand
	local to = Instance.new("Attachment")
	to.Name = "RelicBeamEnd"
	to.Parent = gem
	local beam = Instance.new("Beam")
	beam.Attachment0, beam.Attachment1 = from, to
	beam.Color = ColorSequence.new(BEAM_COLOR)
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Width0, beam.Width1 = 0.25, 0.7
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(0.5, 0.1), NumberSequenceKeypoint.new(1, 0.25) })
	beam.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	beam.TextureMode = Enum.TextureMode.Wrap
	beam.TextureLength = 1.5
	beam.TextureSpeed = 2.5
	beam.Segments = 12
	beam.Parent = gem
	local light = Instance.new("PointLight")
	light.Color = BEAM_COLOR
	light.Range = 8
	light.Brightness = 2
	light.Parent = hand
	for _, thing in { from, to, beam, light } do table.insert(cleanup, thing) end

	return { character = character, gem = gem, cleanup = cleanup }
end

RunService.Heartbeat:Connect(function()
	local relics = match:FindFirstChild("Relics")
	local maze = workspace:FindFirstChild("Maze")
	local wanted = {}
	if relics and maze then
		for _, info in relics:GetChildren() do
			local userId = info:GetAttribute("Collector")
			local collector = userId and Players:GetPlayerByUserId(userId)
			local character = collector and collector.Character
			local relicModel = maze:FindFirstChild("Relic" .. tostring(info:GetAttribute("Id")))
			local gem = relicModel and relicModel:FindFirstChild("Gem")
			if character and gem and not info:GetAttribute("Collected") then
				wanted[info] = true
				local e = effects[info]
				if e and (e.character ~= character or e.gem ~= gem) then
					clear(info)
					e = nil
				end
				if not e then effects[info] = make(info, character, gem) end
			end
		end
	end
	for info in effects do
		if not wanted[info] then clear(info) end
	end
end)
