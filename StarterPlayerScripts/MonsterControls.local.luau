-- Controls for a monster played by a person: the stand-in's LUNGE, and carrying you through a hero's
-- DASH (Fear Eater's Devour). A hero's abilities themselves are used from the ability bar
-- (AbilityControls: right click, Q, E).
--
-- THE LUNGE (the stand-in monster only; a hero like Fear Eater has no left-click action):
-- Left click (or the on-screen button on a touch screen, or the right trigger on a gamepad):
-- crouch for Config.LUNGE_WINDUP seconds (you can't move), then you're carried
-- Config.LUNGE_DISTANCE studs the way you face. The server decides whether it catches anyone
-- (PlayerMonster); this script only moves you, since your character's movement is simulated on
-- your own computer. After a miss you wait Config.LUNGE_COOLDOWN seconds to lunge again.
--
-- Only bound while you're a monster, so a left click does its usual job (collecting relics) for
-- everyone else.
--
-- THE DASH: when the server starts a Devour it puts "DevourAt" (server time), "DevourAim"
-- (direction times distance), "DevourWindup" and "DevourTime" on your monster body. Your character
-- is held still for the windup, then carried along the dash here (your movement is simulated on
-- your own computer); the server checks for a catch.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Net = require(ReplicatedStorage:WaitForChild("Net"))
local Heroes = require(ReplicatedStorage:WaitForChild("Heroes"))

local player = Players.LocalPlayer
local match = ReplicatedStorage:WaitForChild("Match")
local lungeEvent = Net.event("Lunge")

local ACTION = "MonsterLunge"
local readyAt = 0     -- os.clock() when you can lunge again

-- Carry your character `distance` studs along `direction` in `seconds` (gravity still works)
local function spring(root, direction, distance, seconds)
	local attachment = Instance.new("Attachment")
	attachment.Parent = root
	local push = Instance.new("LinearVelocity")
	push.Attachment0 = attachment
	push.RelativeTo = Enum.ActuatorRelativeTo.World
	push.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane   -- only across the floor; gravity still works
	push.PrimaryTangentAxis = Vector3.xAxis
	push.SecondaryTangentAxis = Vector3.zAxis
	local velocity = direction.Unit * (distance / seconds)
	push.PlaneVelocity = Vector2.new(velocity.X, velocity.Z)
	push.MaxForce = 1e6
	push.Parent = root
	task.delay(seconds, function()
		push:Destroy()
		attachment:Destroy()
		if root.Parent then root.AssemblyLinearVelocity *= Vector3.new(0, 1, 0) end   -- stop dead, don't slide on
	end)
end

local function lunge()
	local now = os.clock()
	if now < readyAt or match:GetAttribute("State") ~= Config.States.Playing then return end
	if player:GetAttribute("Killing") then return end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and humanoid and humanoid.Health > 0) then return end
	readyAt = now + Config.LUNGE_WINDUP + Config.LUNGE_TIME + Config.LUNGE_COOLDOWN
	lungeEvent:FireServer()

	-- crouch...
	player:SetAttribute("Lunging", true)
	task.wait(Config.LUNGE_WINDUP)
	player:SetAttribute("Lunging", nil)
	if not root.Parent or player:GetAttribute("Killing") then return end

	-- ...then spring forward the way you face
	local facing = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	if facing.Magnitude < 0.01 then return end
	spring(root, facing, Config.LUNGE_DISTANCE, Config.LUNGE_TIME)
end

-- A hero's dash, started by the server on your monster body
local function dash(model)
	local aim, windup, seconds = model:GetAttribute("DevourAim"), model:GetAttribute("DevourWindup"), model:GetAttribute("DevourTime")
	local startedAt = model:GetAttribute("DevourAt")
	if typeof(aim) ~= "Vector3" or not windup or not seconds or not startedAt then return end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or aim.Magnitude < 0.1 then return end
	-- held still for the windup (less however long the news took to arrive)
	player:SetAttribute("Lunging", true)
	task.wait(math.max(0, startedAt + windup - workspace:GetServerTimeNow()))
	player:SetAttribute("Lunging", nil)
	if not root.Parent or player:GetAttribute("Killing") then return end
	-- face the way it goes, then go
	local flat = aim * Vector3.new(1, 0, 1)
	root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
	spring(root, flat, aim.Magnitude, seconds)
end

local function watchBody(model)
	if model:GetAttribute("OwnerUserId") ~= player.UserId then return end
	model:GetAttributeChangedSignal("DevourAt"):Connect(function() task.spawn(dash, model) end)
end
CollectionService:GetInstanceAddedSignal("Monster"):Connect(function(model) task.defer(watchBody, model) end)
for _, model in CollectionService:GetTagged("Monster") do watchBody(model) end

local function onAction(_, inputState)
	if inputState == Enum.UserInputState.Begin then task.spawn(lunge) end
	return Enum.ContextActionResult.Sink
end

local bound = false
local function updateBinding()
	local hero = Heroes.get(player:GetAttribute("Hero"))
	local isMonster = player:GetAttribute("Role") == Config.Roles.Monster and not (hero and hero.lunge == false)
	if isMonster and not bound then
		ContextActionService:BindAction(ACTION, onAction, true, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)
		ContextActionService:SetTitle(ACTION, "Lunge")
		bound = true
	elseif not isMonster and bound then
		ContextActionService:UnbindAction(ACTION)
		bound = false
	end
end
player:GetAttributeChangedSignal("Role"):Connect(updateBinding)
player:GetAttributeChangedSignal("Hero"):Connect(updateBinding)
updateBinding()
