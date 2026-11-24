-- Controls for a monster played by a person: the stand-in's LUNGE, and carrying you through a hero's
-- DASH (Fear Eater's Devour). A hero's abilities themselves are used from the ability bar
-- (AbilityControls: left click, Q, E for monsters).
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
-- THE DASH: when the server starts a Devour it puts "DevourAt" (server time) and "DevourAim" (the
-- way to the target) on your monster body: you're turned to face them and held still. When the
-- windup is over it sets "DevourGo", with the final "DevourAim" (direction times distance) and
-- "DevourTime": you're carried along it here (your movement is simulated on your own computer).
-- The server decides whether it catches.
--
-- THE MINOTAUR'S CHARGE: "ChargeAt" on your body: you're turned the way it goes ("ChargeDir") and
-- held there; "ChargeGo": you're carried toward "ChargeTo" at the charge's speed (steered at it
-- every frame, so you end where the server planned, even if your computer was a little off);
-- "ChargeEnd": carried on to where the server's charge stopped ("ChargeStopAt") if you're not
-- there yet (you set off a moment after it did), for at most 0.35 s, then stopped dead. The server decides who it tramples.
--
-- THE MINOTAUR'S CRUSH (a leap): "LeapAt": crouched for "LeapCrouch" seconds, then carried in an
-- arc ("LeapHeight" studs up, over the walls) to "LeapTo", landing "LeapWindup" seconds after
-- "LeapAt". Your character is placed along the arc every frame (no walls in the way up there).

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Net = require(ReplicatedStorage:WaitForChild("Net"))
local Heroes = require(ReplicatedStorage:WaitForChild("Heroes"))
local Characters = require(ReplicatedStorage:WaitForChild("Characters"))
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local match = ReplicatedStorage:WaitForChild("Match")
local lungeEvent = Net.event("Lunge")

local ACTION = "MonsterLunge"
local readyAt = 0     -- os.clock() when you can lunge again

-- Carry your character `distance` studs along `direction` in `seconds` (gravity still works).
-- Catching someone ends it on the spot (the kill plays where you caught them).
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
	local stopped = false
	local caught
	local function stop()
		if stopped then return end
		stopped = true
		if caught then caught:Disconnect() end
		push:Destroy()
		attachment:Destroy()
		if root.Parent then root.AssemblyLinearVelocity *= Vector3.new(0, 1, 0) end   -- stop dead, don't slide on
	end
	caught = player:GetAttributeChangedSignal("Killing"):Connect(function()
		if player:GetAttribute("Killing") then stop() end
	end)
	task.delay(seconds, stop)
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

-- A hero's dash, started by the server on your monster body. From the windup until the lunge is
-- over you're held ("Lunging": no walking, no turning to the mouse) and kept turned toward the
-- victim ("DevourVictim" on the body, a UserId), every frame.
local devourToken = nil

local function faceVictim(model)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local victim = Characters.of(model:GetAttribute("DevourVictim"))
	local theirs = victim and victim:FindFirstChild("HumanoidRootPart")
	if not (root and theirs) then return end
	local flat = (theirs.Position - root.Position) * Vector3.new(1, 0, 1)
	if flat.Magnitude > 0.5 then root.CFrame = CFrame.lookAt(root.Position, root.Position + flat) end
end

local function endDevour(token)
	if devourToken ~= token then return end
	devourToken = nil
	player:SetAttribute("Lunging", nil)
end

local function startDevour(model)
	local token = {}
	devourToken = token
	player:SetAttribute("Lunging", true)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then humanoid.AutoRotate = false end   -- (Controls sets it back afterwards)
	RunService:UnbindFromRenderStep("DevourFacing")
	RunService:BindToRenderStep("DevourFacing", Enum.RenderPriority.Camera.Value + 3, function()
		if devourToken ~= token then
			RunService:UnbindFromRenderStep("DevourFacing")
			return
		end
		faceVictim(model)
		-- caught them: the kill holds you from here, still turned toward them
		if player:GetAttribute("Killing") then endDevour(token) end
	end)
	return token
end

-- ...first held still for the windup...
local function hold(model)
	local token = startDevour(model)
	faceVictim(model)
	local windup = model:GetAttribute("DevourWindup") or 0.3
	task.delay(windup + 0.6, function() if not model:GetAttribute("DevourGo") or model:GetAttribute("DevourGo") < (model:GetAttribute("DevourAt") or 0) then endDevour(token) end end)
end

-- ...then the lunge itself (still facing them)
local function dash(model)
	local token = devourToken or startDevour(model)
	local aim, seconds = model:GetAttribute("DevourAim"), model:GetAttribute("DevourTime")
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local flat = typeof(aim) == "Vector3" and aim * Vector3.new(1, 0, 1) or Vector3.zero
	if not root or not seconds or player:GetAttribute("Killing") or flat.Magnitude < 0.1 then
		task.delay(0.15, endDevour, token)
		return
	end
	spring(root, flat, flat.Magnitude, seconds)
	-- held until the server's catch arrives (it waits for you to reach them), or a miss is clear
	task.delay(seconds + 0.6, endDevour, token)
end

-- THE CHARGE
local charge = nil   -- { model, dir, push, attachment, to, speed } while one is under way

local function rootAndHumanoid()
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart"), character and character:FindFirstChildOfClass("Humanoid")
end

local function stopCharge()
	if not charge then return end
	if charge.push then charge.push:Destroy() end
	if charge.attachment then charge.attachment:Destroy() end
	local root = rootAndHumanoid()
	if root then root.AssemblyLinearVelocity *= Vector3.new(0, 1, 0) end
	charge = nil
end

local function chargeWindup(model)
	stopCharge()
	local dir = model:GetAttribute("ChargeDir")
	if typeof(dir) ~= "Vector3" then return end
	local token = { model = model, dir = dir }
	charge = token
	local _, humanoid = rootAndHumanoid()
	if humanoid then humanoid.AutoRotate = false end
	RunService:UnbindFromRenderStep("ChargeFacing")
	RunService:BindToRenderStep("ChargeFacing", Enum.RenderPriority.Camera.Value + 3, function()
		local root = rootAndHumanoid()
		if charge ~= token or not root then
			RunService:UnbindFromRenderStep("ChargeFacing")
			return
		end
		root.CFrame = CFrame.lookAt(root.Position, root.Position + token.dir)
		-- carried toward where it ends, at the charge's speed
		if token.push and token.to then
			local left = (token.to - root.Position) * Vector3.new(1, 0, 1)
			if token.finishBy and (left.Magnitude < 0.5 or left:Dot(token.dir) < 0 or os.clock() > token.finishBy) then
				stopCharge()                                -- (over, and he's got there)
				return
			end
			if left.Magnitude < 0.5 or left:Dot(token.dir) < 0 then
				token.push.PlaneVelocity = Vector2.zero
			else
				local v = left.Unit * token.speed
				token.push.PlaneVelocity = Vector2.new(v.X, v.Z)
			end
		end
	end)
	-- (if the server never says go - a stun in the windup - ChargeEnd still comes)
end

local function chargeGo(model)
	local root = rootAndHumanoid()
	if not root then return end
	if not charge or charge.model ~= model then chargeWindup(model) end
	local token = charge
	if not token then return end
	local from, to, time = model:GetAttribute("ChargeFrom"), model:GetAttribute("ChargeTo"), model:GetAttribute("ChargeTime")
	if typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" or not time then return end
	token.to = Vector3.new(to.X, root.Position.Y, to.Z)
	token.speed = (to - from).Magnitude / math.max(time, 0.01)
	if not token.push then
		local attachment = Instance.new("Attachment")
		attachment.Parent = root
		local push = Instance.new("LinearVelocity")
		push.Attachment0 = attachment
		push.RelativeTo = Enum.ActuatorRelativeTo.World
		push.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane   -- only across the floor; gravity still works
		push.PrimaryTangentAxis = Vector3.xAxis
		push.SecondaryTangentAxis = Vector3.zAxis
		push.MaxForce = 1e6
		push.Parent = root
		token.push, token.attachment = push, attachment
	end
end

-- THE LEAP
local leapToken = nil
local function leap(model)
	local token = {}
	leapToken = token
	stopCharge()
	local root, humanoid = rootAndHumanoid()
	local at, to = model:GetAttribute("LeapAt"), model:GetAttribute("LeapTo")
	if not (root and humanoid and at and typeof(to) == "Vector3") then return end
	local crouch = model:GetAttribute("LeapCrouch") or 0.3
	local windup = model:GetAttribute("LeapWindup") or 1.5
	local height = model:GetAttribute("LeapHeight") or 16
	humanoid.AutoRotate = false
	local from = root.Position
	local target = Vector3.new(to.X, from.Y, to.Z)
	local flat = (target - from) * Vector3.new(1, 0, 1)
	local facing = flat.Magnitude > 0.5 and flat.Unit or root.CFrame.LookVector * Vector3.new(1, 0, 1)
	local takeoff, land = at + crouch, at + windup
	while leapToken == token and root.Parent do
		local now = workspace:GetServerTimeNow()
		local k = math.clamp((now - takeoff) / math.max(land - takeoff, 0.01), 0, 1)
		if now >= takeoff then
			local p = from:Lerp(target, k) + Vector3.yAxis * height * 4 * k * (1 - k)
			root.CFrame = CFrame.lookAt(p, p + facing)
			root.AssemblyLinearVelocity = Vector3.zero
		else
			root.CFrame = CFrame.lookAt(root.Position, root.Position + facing)
		end
		if k >= 1 then break end
		RunService.RenderStepped:Wait()
	end
	if leapToken == token then leapToken = nil end
end

local function watchBody(model)
	if model:GetAttribute("OwnerUserId") ~= player.UserId then return end
	model:GetAttributeChangedSignal("DevourAt"):Connect(function() hold(model) end)
	model:GetAttributeChangedSignal("DevourGo"):Connect(function() task.spawn(dash, model) end)
	model:GetAttributeChangedSignal("ChargeAt"):Connect(function() chargeWindup(model) end)
	model:GetAttributeChangedSignal("ChargeGo"):Connect(function() chargeGo(model) end)
	-- over: your computer started a moment after the server (the news takes a while to arrive), so
	-- you may not be there yet - carried on to where it stopped ("ChargeStopAt"), briefly, then stopped
	model:GetAttributeChangedSignal("ChargeEnd"):Connect(function()
		if not (charge and charge.model == model) then return end
		local stopAt = model:GetAttribute("ChargeStopAt")
		local root = rootAndHumanoid()
		if charge.push and typeof(stopAt) == "Vector3" and root then
			charge.to = Vector3.new(stopAt.X, root.Position.Y, stopAt.Z)
			charge.finishBy = os.clock() + 0.35
		else
			stopCharge()
		end
	end)
	model:GetAttributeChangedSignal("LeapAt"):Connect(function() task.spawn(leap, model) end)
	model.Destroying:Connect(function()
		if charge and charge.model == model then stopCharge() end
	end)
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
