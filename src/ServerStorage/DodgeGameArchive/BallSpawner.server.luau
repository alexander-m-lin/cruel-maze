-- Spawns dodgeballs that roll across the arena or fall from the sky.
-- Gets harder over time: more balls, faster balls.

local Debris = game:GetService("Debris")

local floor = workspace.Arena.Floor
local ballsFolder = workspace.Balls
local HALF = floor.Size.X / 2 - 3       -- stay just inside the walls
local FLOOR_TOP = floor.Position.Y + floor.Size.Y / 2

local startTime = os.clock()

local COLORS = {
	Color3.fromRGB(255, 80, 80), Color3.fromRGB(255, 170, 60),
	Color3.fromRGB(255, 240, 90), Color3.fromRGB(120, 255, 120),
	Color3.fromRGB(110, 170, 255), Color3.fromRGB(220, 120, 255),
}

-- Difficulty goes from 0 to 1 over 2 minutes
local function difficulty()
	return math.clamp((os.clock() - startTime) / 120, 0, 1)
end

-- Anything with a Humanoid that touches a ball is knocked out
local function onTouched(ball, hit)
	local humanoid = hit.Parent and hit.Parent:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 and not hit.Parent:FindFirstChildOfClass("ForceField") then
		humanoid.Health = 0
	end
end

local function makeBall(size)
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(size, size, size)
	ball.Color = COLORS[math.random(#COLORS)]
	ball.Material = Enum.Material.Neon
	ball.CustomPhysicalProperties = PhysicalProperties.new(1, 0.3, 0.6) -- density, friction, bounciness
	ball.Touched:Connect(function(hit) onTouched(ball, hit) end)
	return ball
end

-- A ball that starts at one edge and rolls across the arena
local function spawnRoller()
	local d = difficulty()
	local size = math.random(4, 8)
	local ball = makeBall(size)

	-- pick a random edge and a random target point on the far side
	local side = math.random(4)
	local along = math.random(-HALF, HALF)
	local startPos
	if side == 1 then startPos = Vector3.new(along, 0, -HALF)
	elseif side == 2 then startPos = Vector3.new(along, 0, HALF)
	elseif side == 3 then startPos = Vector3.new(-HALF, 0, along)
	else startPos = Vector3.new(HALF, 0, along) end
	startPos += Vector3.new(0, FLOOR_TOP + size / 2, 0)

	local target = Vector3.new(math.random(-HALF, HALF) * 0.5, startPos.Y, math.random(-HALF, HALF) * 0.5)
	local speed = 25 + 45 * d + math.random() * 10

	ball.Position = startPos
	ball.Parent = ballsFolder
	ball:SetNetworkOwner(nil) -- server controls physics so it can't be cheated
	ball.AssemblyLinearVelocity = (target - startPos).Unit * speed
	Debris:AddItem(ball, 8)
end

-- A ball that drops from above, with a warning marker on the floor
local function spawnDropper()
	local size = math.random(6, 10)
	local x, z = math.random(-HALF, HALF), math.random(-HALF, HALF)

	local marker = Instance.new("Part")
	marker.Shape = Enum.PartType.Cylinder
	marker.Size = Vector3.new(0.2, size, size)
	marker.CFrame = CFrame.new(x, FLOOR_TOP + 0.1, z) * CFrame.Angles(0, 0, math.rad(90))
	marker.Anchored, marker.CanCollide, marker.CanQuery, marker.CanTouch = true, false, false, false
	marker.Color = Color3.fromRGB(255, 50, 50)
	marker.Material = Enum.Material.Neon
	marker.Transparency = 0.4
	marker.Parent = ballsFolder
	Debris:AddItem(marker, 1.5)

	local ball = makeBall(size)
	ball.Position = Vector3.new(x, FLOOR_TOP + 60, z)
	ball.Parent = ballsFolder
	ball:SetNetworkOwner(nil)
	ball.AssemblyLinearVelocity = Vector3.new(0, -20, 0)
	Debris:AddItem(ball, 7)
end

-- Main loop
while true do
	local d = difficulty()
	if math.random() < 0.25 + 0.15 * d then
		spawnDropper()
	else
		spawnRoller()
	end
	task.wait(1.2 - 0.85 * d + math.random() * 0.3) -- ~1.3s between balls at start, ~0.5s at max
end
