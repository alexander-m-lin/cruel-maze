-- Controls for a monster played by a person: the LUNGE.
--
-- Left click (or the on-screen button on a touch screen, or the right trigger on a gamepad):
-- crouch for Config.LUNGE_WINDUP seconds (you can't move), then you're carried
-- Config.LUNGE_DISTANCE studs the way you face. The server decides whether it catches anyone
-- (PlayerMonster); this script only moves you, since your character's movement is simulated on
-- your own computer. After a miss you wait Config.LUNGE_COOLDOWN seconds to lunge again.
--
-- Only bound while you're a monster, so a left click does its usual job (collecting relics) for
-- everyone else.

local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Net = require(ReplicatedStorage:WaitForChild("Net"))

local player = Players.LocalPlayer
local match = ReplicatedStorage:WaitForChild("Match")
local lungeEvent = Net.event("Lunge")

local ACTION = "MonsterLunge"
local readyAt = 0     -- os.clock() when you can lunge again

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
	local attachment = Instance.new("Attachment")
	attachment.Parent = root
	local push = Instance.new("LinearVelocity")
	push.Attachment0 = attachment
	push.RelativeTo = Enum.ActuatorRelativeTo.World
	push.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane   -- only across the floor; gravity still works
	push.PrimaryTangentAxis = Vector3.xAxis
	push.SecondaryTangentAxis = Vector3.zAxis
	local velocity = facing.Unit * (Config.LUNGE_DISTANCE / Config.LUNGE_TIME)
	push.PlaneVelocity = Vector2.new(velocity.X, velocity.Z)
	push.MaxForce = 1e6
	push.Parent = root
	task.delay(Config.LUNGE_TIME, function()
		push:Destroy()
		attachment:Destroy()
	end)
end

local function onAction(_, inputState)
	if inputState == Enum.UserInputState.Begin then task.spawn(lunge) end
	return Enum.ContextActionResult.Sink
end

local bound = false
local function updateBinding()
	local isMonster = player:GetAttribute("Role") == Config.Roles.Monster
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
updateBinding()
