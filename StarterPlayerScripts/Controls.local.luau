-- Player controls.
--
-- MOVEMENT: Roblox's built-in controls move you relative to the camera, and our camera never
-- turns, so W/A/S/D already move you up/left/down/right on the screen. Nothing to do here.
--
-- FACING: with a mouse, your character always faces the point on the floor under the cursor -
-- and since the fog's vision cone follows the way you face, the mouse aims where you look.
-- With touch or a gamepad (no mouse to aim), you face the way you're moving, as normal.
-- (Proper touch/gamepad aiming comes later, with mobile controls.)
--
-- SPEED: moving a different way from where you face slows you down (cone sizes and speeds are in
-- Config). The server sets your base speed (the player's "BaseSpeed" attribute, e.g. 0 during the
-- countdown); this script scales it each frame. Your character's movement is simulated on your
-- own computer, so setting WalkSpeed here is what takes effect.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Config"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Speed multiplier for moving at `angle` degrees away from where you face:
-- full inside the front cone, slightly slower on the sides, much slower backwards.
-- Each change blends in over Config.FACING_BLEND degrees just past the zone's edge, so each zone
-- keeps its full speed right up to its edge (a sideways strafe at 90° gets the side speed).
local function facingSpeed(angle)
	local frontEdge = Config.FACING_FULL_CONE / 2                 -- 50°
	local sideEdge = frontEdge + Config.FACING_SIDE_CONE          -- 90°
	local blend = Config.FACING_BLEND
	local toSide = math.clamp((angle - frontEdge) / blend, 0, 1)
	local toBack = math.clamp((angle - sideEdge) / blend, 0, 1)
	local side = 1 + (Config.FACING_SIDE_SPEED - 1) * toSide
	return side + (Config.FACING_BACK_SPEED - side) * toBack
end

local MOUSE_INPUTS = {
	[Enum.UserInputType.MouseMovement] = true,
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.MouseButton2] = true,
	[Enum.UserInputType.MouseWheel] = true,
	[Enum.UserInputType.Keyboard] = true,
}

-- Aim with the mouse if the last thing used was the mouse or keyboard
local aimWithMouse = UserInputService.MouseEnabled
UserInputService.LastInputTypeChanged:Connect(function(inputType)
	if MOUSE_INPUTS[inputType] then
		aimWithMouse = true
	elseif inputType == Enum.UserInputType.Touch or inputType.Name:find("Gamepad") then
		aimWithMouse = false
	end
end)

-- Where the mouse points, on a flat plane at height y
local function mouseOnPlane(y)
	local m = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(m.X, m.Y)
	if math.abs(ray.Direction.Y) < 1e-4 then return nil end
	local t = (y - ray.Origin.Y) / ray.Direction.Y
	if t < 0 then return nil end
	return ray.Origin + ray.Direction * t
end

-- Runs after the camera script has placed the camera for this frame
RunService:BindToRenderStep("FaceMouse", Enum.RenderPriority.Camera.Value + 2, function()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root) or humanoid.Health <= 0 then return end

	humanoid.AutoRotate = not aimWithMouse   -- Roblox turns you toward your movement only when not aiming

	if aimWithMouse then
		local target = mouseOnPlane(root.Position.Y)
		local flat = target and (target - root.Position) * Vector3.new(1, 0, 1)
		if flat and flat.Magnitude >= 0.5 then   -- cursor right on top of you: keep the current facing
			root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
		end
	end

	-- Speed: scale the server's base speed by how far your movement is from your facing
	local base = player:GetAttribute("BaseSpeed") or Config.PLAYER_SPEED
	local move = humanoid.MoveDirection * Vector3.new(1, 0, 1)
	local multiplier = 1
	if aimWithMouse and move.Magnitude > 0.1 then
		local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
		local angle = math.deg(math.acos(math.clamp(move.Unit:Dot(look.Unit), -1, 1)))
		multiplier = facingSpeed(angle)
	end
	humanoid.WalkSpeed = base * multiplier
end)
