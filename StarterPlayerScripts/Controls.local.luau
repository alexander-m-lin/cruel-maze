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
--
-- COLLECTING A RELIC: while you're collecting one, you face it (so your vision cone stays on it)
-- and move at the backwards speed whichever way you go.
--
-- BACKWARDS RUNNING: when you move away from where you face, the walk/run animation plays in
-- reverse, so your legs match your movement instead of moonwalking.
--
-- FALSE RELIC: clicking one slows you to Config.FALSE_RELIC_SLOW for a few seconds ("SlowUntil").
--
-- HELD BY A MONSTER (the "Seized" attribute): no control at all until it's over. The same while
-- a monster player is killing someone ("Killing") or crouched to lunge ("Lunging", set by
-- MonsterControls on this computer).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Config"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local match = game:GetService("ReplicatedStorage"):WaitForChild("Match")

local BACKWARDS_FROM = 100   -- moving more than this many degrees from your facing plays the run backwards
local GEM_HEIGHT = 3.4       -- how high a relic's gem sits above the floor (see MazeBuilder)

-- The relic you're collecting right now, if any: its gem's position
local function collectingAt()
	local relics = match:FindFirstChild("Relics")
	if not relics then return nil end
	for _, info in relics:GetChildren() do
		if info:GetAttribute("Collector") == player.UserId then
			return info:GetAttribute("Center") + Vector3.new(0, GEM_HEIGHT, 0)
		end
	end
	return nil
end

-- Play the walk/run animation forwards or backwards. Roblox's Animate script keeps setting its
-- speed (always positive) as you speed up and slow down, so this flips the sign every frame.
local RUN_TRACKS = { RunAnim = true, WalkAnim = true }
local function setRunBackwards(humanoid, backwards)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then return end
	for _, track in animator:GetPlayingAnimationTracks() do
		if RUN_TRACKS[track.Name] or (track.Animation and RUN_TRACKS[track.Animation.Name]) then
			local speed = track.Speed
			if (backwards and speed > 0) or (not backwards and speed < 0) then track:AdjustSpeed(-speed) end
		end
	end
end

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
	-- held by a monster, killing someone (monster players), or crouched to lunge: can't move
	if player:GetAttribute("Seized") or player:GetAttribute("Killing") or player:GetAttribute("Lunging") then
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

	-- Speed: scale the server's base speed by how far your movement is from your facing
	local base = player:GetAttribute("BaseSpeed") or Config.PLAYER_SPEED
	local move = humanoid.MoveDirection * Vector3.new(1, 0, 1)
	local multiplier = 1
	local angle = 0
	if move.Magnitude > 0.1 then
		local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
		angle = math.deg(math.acos(math.clamp(move.Unit:Dot(look.Unit), -1, 1)))
	end
	if relic then
		multiplier = Config.FACING_BACK_SPEED
	elseif aimWithMouse and move.Magnitude > 0.1 then
		multiplier = facingSpeed(angle)
	end
	-- tricked by a false relic: slowed for a while
	if (player:GetAttribute("SlowUntil") or 0) > workspace:GetServerTimeNow() then
		multiplier *= Config.FALSE_RELIC_SLOW
	end
	humanoid.WalkSpeed = base * multiplier
	setRunBackwards(humanoid, angle > BACKWARDS_FROM)
end)
