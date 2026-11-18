-- Player controls.
--
-- MOVEMENT: Roblox's built-in controls move you relative to the camera, and our camera never
-- turns, so W/A/S/D already move you up/left/down/right on the screen. Nothing to do here.
--
-- FACING: with a mouse, your character always faces the point on the floor under the cursor -
-- and since the fog's vision cone follows the way you face, the mouse aims where you look.
-- With touch or a gamepad (no mouse to aim), you face the way you're moving, as normal.
-- (Proper touch/gamepad aiming comes later, with mobile controls.)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

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
	if not aimWithMouse then return end

	local target = mouseOnPlane(root.Position.Y)
	if not target then return end
	local flat = (target - root.Position) * Vector3.new(1, 0, 1)
	if flat.Magnitude < 0.5 then return end   -- cursor right on top of you: keep the current facing
	root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
end)
