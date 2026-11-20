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
-- Config; the rules themselves are in the Movement module, shared with survivor bots). The server sets your base speed (the player's "BaseSpeed" attribute, e.g. 0 during the
-- countdown); this script scales it each frame. Your character's movement is simulated on your
-- own computer, so setting WalkSpeed here is what takes effect.
--
-- COLLECTING A RELIC (or destroying a ward): while you're collecting one, you face it (so your vision cone stays on it)
-- and move at the backwards speed whichever way you go.
--
-- BACKWARDS RUNNING: when you move away from where you face, the walk/run animation plays in
-- reverse, so your legs match your movement instead of moonwalking.
--
-- PULLED (Sara's whip) or STUNNED: carried along / held still (see Movement.held, Pull).
--
-- FALSE RELIC: clicking one slows you to Config.FALSE_RELIC_SLOW for a few seconds ("SlowUntil").
--
-- HELD BY A MONSTER (the "Seized" attribute): no control at all until it's over. The same while
-- a monster player is killing someone ("Killing") or crouched to lunge ("Lunging", set by
-- MonsterControls on this computer).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Movement = require(game:GetService("ReplicatedStorage"):WaitForChild("Movement"))   -- the speed rules (shared with bots)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local match = game:GetService("ReplicatedStorage"):WaitForChild("Match")

local GEM_HEIGHT = 3.4       -- how high a relic's gem sits above the floor (see MazeBuilder)

-- The relic you're collecting (or ward you're destroying) right now, if any: its gem's or eye's position
local function collectingAt()
	for _, name in { "Relics", "WardEyes" } do
		local folder = match:FindFirstChild(name)
		for _, info in folder and folder:GetChildren() or {} do
			if info:GetAttribute("Collector") == player.UserId then
				return info:GetAttribute("Eye") or info:GetAttribute("Center") + Vector3.new(0, GEM_HEIGHT, 0)
			end
		end
	end
	return nil
end

local pullHeardAt = nil      -- os.clock() when we heard about the latest pull (see PULLED below)
player:GetAttributeChangedSignal("PullAt"):Connect(function()
	pullHeardAt = player:GetAttribute("PullAt") and os.clock() or nil
end)

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
	if player:GetAttribute("Seized") or player:GetAttribute("Killing") or player:GetAttribute("Lunging") then
		humanoid.WalkSpeed = 0              -- (Movement says the same; no turning to face either)
		return
	end

	-- PULLED (a whip; see Pull on the server): the server says from where to where and for how
	-- long; your character is yours to move, so it's carried along here. Timed from when the news
	-- arrives (pulls are short: by the server's clock, a late one would already be over).
	if pullHeardAt then
		local k = (os.clock() - pullHeardAt) / math.max(0.01, player:GetAttribute("PullTime") or 0)
		local from, to = player:GetAttribute("PullFrom"), player:GetAttribute("PullTo")
		if k >= 0 and k < 1.05 and from and to then
			local at = from:Lerp(to, math.min(k, 1))
			root.CFrame = CFrame.new(Vector3.new(at.X, root.Position.Y, at.Z)) * root.CFrame.Rotation
			root.AssemblyLinearVelocity = Vector3.zero
			humanoid.WalkSpeed = 0
			return
		end
	end
	if Movement.held(player) then          -- stunned
		humanoid.WalkSpeed = 0
		return
	end

	local relic = collectingAt()
	humanoid.AutoRotate = not (aimWithMouse or relic)   -- Roblox turns you toward your movement only when not aiming

	if relic then
		local flat = (relic - root.Position) * Vector3.new(1, 0, 1)
		if flat.Magnitude >= 0.5 then
			root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
		end
	elseif aimWithMouse then
		local target = mouseOnPlane(root.Position.Y)
		local flat = target and (target - root.Position) * Vector3.new(1, 0, 1)
		if flat and flat.Magnitude >= 0.5 then   -- cursor right on top of you: keep the current facing
			root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
		end
	end

	-- Speed: the shared rules (Movement), with your facing coming from the mouse
	local speed, angle = Movement.walkSpeed(player, humanoid, root, { aiming = aimWithMouse, collecting = relic ~= nil })
	humanoid.WalkSpeed = speed
	Movement.setRunBackwards(humanoid, angle > Movement.BACKWARDS_FROM)
end)
