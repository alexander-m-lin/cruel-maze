-- WARDS on this computer (the Maze Master's floating eyes; see WardEyes on the server):
--   - each eye bobs gently and peers slowly around, now and then darting to a new direction
--   - for the monster side: while a survivor is destroying one, a purple ring pulses out from it
--     every half second, drawn over the fog and walls (like MonsterPing), so you know where
-- Whether you can see a ward at all is FogOfWar's job.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local match = ReplicatedStorage:WaitForChild("Match")

local BOB_HEIGHT = 0.3       -- studs up and down
local BOB_TIME = 2.2         -- seconds per bob
local LOOK_EVERY = 1.6       -- seconds (roughly) between darting to a new direction
local LOOK_SPEED = 6         -- how quickly it turns to look (higher = snappier)
local PING_EVERY = 0.5       -- seconds between pulses while a ward is being destroyed
local PING_LIFETIME = 1.2
local PING_RADIUS = 14       -- studs the pulse spreads to
local SEGMENTS = 40
local PURPLE = Color3.fromRGB(190, 90, 255)

---------------------------------------------------------------- the eyes
local eyes = {}   -- [model] = { base = Vector3, parts = { {part, offset} }, yaw, wantYaw, nextLook, phase }

RunService.RenderStepped:Connect(function(dt)
	local t = os.clock()
	for _, model in CollectionService:GetTagged("WardEye") do
		local eye = model:FindFirstChild("Eye")
		if not eye then continue end
		local e = eyes[model]
		if not e then
			e = { base = eye.Position, parts = {}, yaw = math.random() * 2 * math.pi, nextLook = t, phase = math.random() * 10 }
			e.wantYaw = e.yaw
			for _, part in model:GetChildren() do
				if part:IsA("BasePart") then table.insert(e.parts, { part, eye.CFrame:Inverse() * part.CFrame }) end
			end
			eyes[model] = e
			model.Destroying:Once(function() eyes[model] = nil end)
		end
		if t >= e.nextLook then
			e.wantYaw = e.yaw + (math.random() - 0.5) * math.rad(220)
			e.nextLook = t + LOOK_EVERY * (0.6 + 0.8 * math.random())
		end
		e.yaw += (e.wantYaw - e.yaw) * math.min(1, dt * LOOK_SPEED)
		local lift = math.sin((t / BOB_TIME) * 2 * math.pi + e.phase) * BOB_HEIGHT
		local tilt = math.sin(t * 0.7 + e.phase) * math.rad(12)      -- looking a little up and down
		local cf = CFrame.new(e.base + Vector3.new(0, lift, 0)) * CFrame.Angles(0, e.yaw, 0) * CFrame.Angles(tilt, 0, 0)
		for _, p in e.parts do p[1].CFrame = cf * p[2] end
	end
end)

---------------------------------------------------------------- the alarm (monster side)
local screen = Instance.new("ScreenGui")
screen.Name = "WardAlarms"
screen.IgnoreGuiInset = true
screen.ResetOnSpawn = false
screen.Parent = player:WaitForChild("PlayerGui")

local function toScreen(p)
	local v = camera:WorldToViewportPoint(p)
	return Vector2.new(v.X, v.Y)
end

local function pulse(center)
	local segs = {}
	for i = 1, SEGMENTS do
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BorderSizePixel = 0
		f.BackgroundColor3 = PURPLE
		f.Parent = screen
		segs[i] = f
	end
	local start = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local k = (os.clock() - start) / PING_LIFETIME
		if k >= 1 then
			conn:Disconnect()
			for _, f in segs do f:Destroy() end
			return
		end
		local eased = 1 - (1 - k) ^ 2
		local radius = 1 + (PING_RADIUS - 1) * eased
		local pps = (toScreen(center + camera.CFrame.RightVector) - toScreen(center)).Magnitude
		local prev = toScreen(center + Vector3.new(radius, 0, 0))
		for i, seg in segs do
			local a = i / SEGMENTS * 2 * math.pi
			local nextPt = toScreen(center + Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius))
			local d = nextPt - prev
			seg.Position = UDim2.fromOffset((prev.X + nextPt.X) / 2, (prev.Y + nextPt.Y) / 2)
			seg.Size = UDim2.fromOffset(d.Magnitude + 1.5, math.max(2, 0.6 * pps))
			seg.Rotation = math.deg(math.atan2(d.Y, d.X))
			seg.BackgroundTransparency = 0.1 + 0.9 * eased
			prev = nextPt
		end
	end)
end

local function onMonsterSide()
	local role = player:GetAttribute("Role")
	return role == Config.Roles.Monster or role == Config.Roles.MazeMaster
end

while true do
	task.wait(PING_EVERY)
	local folder = match:FindFirstChild("WardEyes")
	if folder and onMonsterSide() then
		for _, info in folder:GetChildren() do
			if info:GetAttribute("CollectSince") then
				local c = info:GetAttribute("Center")
				pulse(c + Vector3.new(0, 0.1, 0))
			end
		end
	end
end
