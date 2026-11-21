-- Fixed isometric camera that follows the player.
-- Runs on each player's own computer (LocalScript), because the camera is client-side.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Config"))
local FogState = require(script.Parent:WaitForChild("FogState"))   -- for the doors' ghosts (DoorView)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Direction from the player to the camera (set in Config, shared with the fog).
-- Try (-1, 2, -1) there for a steeper, more top-down view.
local DIRECTION = Config.CAMERA_DIRECTION
local DISTANCE = 210   -- far away...
local FOV = 22         -- ...with a narrow lens: looks flatter, like classic isometric games
local FADE = 0.75      -- how see-through walls become when they block the view

local faded = {}       -- walls we've made transparent this frame

local function fadeBlockingWalls(fromPos, toPos, character)
	-- Un-fade last frame's walls
	for part in faded do
		part.LocalTransparencyModifier = 0
	end
	table.clear(faded)

	-- Raycast from player toward the camera. A ray stops at the first thing it hits,
	-- so after each hit we ignore that part and cast again to find the next one.
	local ignore = { character }
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	for _ = 1, 6 do
		params.FilterDescendantsInstances = ignore
		local result = workspace:Raycast(fromPos, toPos - fromPos, params)
		if not result then break end
		local part = result.Instance
		if part.Name == "Wall" then
			part.LocalTransparencyModifier = FADE
			faded[part] = true
		elseif part.Name == "Door" then
			-- the real door is never drawn here; fade the copy that is
			local ghost = FogState.doorGhosts[part]
			if ghost then
				ghost.LocalTransparencyModifier = FADE
				faded[ghost] = true
			end
		end
		table.insert(ignore, part)
	end
end

local function aliveRoot(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then return character:FindFirstChild("HumanoidRootPart") end
	return nil
end

-- Who to watch when you have no character (choosing a spawn room, or out of lives):
-- a teammate who's still alive (a player, or a survivor bot), sticking with the same one while
-- they are. People first, then bots.
local watching = nil   -- the character being watched
local function teammateRoot()
	local myRole = player:GetAttribute("Role")
	if watching and watching.Parent and aliveRoot(watching) then
		return aliveRoot(watching), watching
	end
	watching = nil
	if not myRole then return nil end
	for _, other in Players:GetPlayers() do
		if other ~= player and other:GetAttribute("Role") == myRole and aliveRoot(other.Character) then
			watching = other.Character
			return aliveRoot(watching), watching
		end
	end
	if myRole == Config.Roles.Survivor then
		for _, bot in CollectionService:GetTagged("SurvivorBot") do
			if bot:IsDescendantOf(workspace) and aliveRoot(bot) then
				watching = bot
				return aliveRoot(bot), bot
			end
		end
	end
	return nil
end

local lastFocus = nil

-- THE MAZE MASTER has no character: their camera pans freely over the maze. WASD or the arrow
-- keys move it across the screen (up on the screen is +X+Z in the world, since the camera looks
-- from the -X-Z corner). It starts over the middle and can't leave the maze.
local PAN_SPEED = 90   -- studs per second (scaled with zoom)
local ZOOM_MIN, ZOOM_MAX = 0.65, 1.6 -- the Maze Master zooms (mouse wheel, or pinch) between these times DISTANCE
-- Why only 1.6: lower graphics settings stop drawing parts a few hundred studs from the camera
-- (about 480 in one Studio test window), and scripts can't change that. The top of the screen is
-- about 1.4x the camera's distance away, so past ~1.6x the far walls vanish. (Widening the lens
-- instead would avoid that, but it bends the isometric look too much.)
local ZOOM_STEP = 1.15               -- per wheel notch
local zoom = 1
local atmosphere = game:GetService("Lighting"):FindFirstChildOfClass("Atmosphere")
local baseDensity = atmosphere and atmosphere.Density or 0
local panFocus = nil
local panMaze = nil
local PAN_KEYS = {
	[Enum.KeyCode.W] = Vector2.new(0, 1), [Enum.KeyCode.Up] = Vector2.new(0, 1),
	[Enum.KeyCode.S] = Vector2.new(0, -1), [Enum.KeyCode.Down] = Vector2.new(0, -1),
	[Enum.KeyCode.A] = Vector2.new(-1, 0), [Enum.KeyCode.Left] = Vector2.new(-1, 0),
	[Enum.KeyCode.D] = Vector2.new(1, 0), [Enum.KeyCode.Right] = Vector2.new(1, 0),
}
local function isMazeMaster() return player:GetAttribute("Role") == Config.Roles.MazeMaster end
UserInputService.InputChanged:Connect(function(input, processed)
	if processed or not isMazeMaster() then return end
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		zoom = math.clamp(zoom * (input.Position.Z > 0 and 1 / ZOOM_STEP or ZOOM_STEP), ZOOM_MIN, ZOOM_MAX)
	end
end)
UserInputService.TouchPinch:Connect(function(_, scale, _, _, processed)
	if processed or not isMazeMaster() then return end
	if scale and scale > 0 then zoom = math.clamp(zoom / scale ^ 0.05, ZOOM_MIN, ZOOM_MAX) end
end)

local function mazeMasterFocus(dt)
	local maze = workspace:FindFirstChild("Maze")
	if not maze then return panFocus end
	local half = (maze:GetAttribute("Cells") or 15) * (maze:GetAttribute("CellSize") or 20) / 2
	local floorY = maze:GetAttribute("FloorY") or 0
	if panMaze ~= maze or not panFocus then
		panMaze = maze
		panFocus = Vector3.new(0, floorY, 0)
	end
	local input = Vector2.zero
	if not UserInputService:GetFocusedTextBox() then
		for key, v in PAN_KEYS do
			if UserInputService:IsKeyDown(key) then input += v end
		end
	end
	if input.Magnitude > 0 then
		-- screen right and screen up, flattened onto the floor
		local right = camera.CFrame.RightVector * Vector3.new(1, 0, 1)
		local up = camera.CFrame.UpVector * Vector3.new(1, 0, 1)
		local move = (right.Unit * input.X + up.Unit * input.Y)
		panFocus += move.Unit * PAN_SPEED * zoom * dt
		panFocus = Vector3.new(math.clamp(panFocus.X, -half, half), floorY, math.clamp(panFocus.Z, -half, half))
	end
	return panFocus
end

-- BindToRenderStep runs right before each frame is drawn, after Roblox's default camera
RunService:BindToRenderStep("IsometricCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = FOV

	local character = player.Character
	local root = aliveRoot(character)
	local focus
	if player:GetAttribute("Role") == Config.Roles.MazeMaster then
		character = nil
		focus = mazeMasterFocus(dt)
	else
		if not root then
			root, character = teammateRoot()  -- watch a teammate instead
		end
		focus = root and root.Position or lastFocus
	end
	if not focus then return end
	lastFocus = focus

	local zoomed = isMazeMaster() and zoom or 1
	local camPos = focus + DIRECTION * DISTANCE * zoomed
	camera.CFrame = CFrame.lookAt(camPos, focus)
	-- The atmosphere's haze builds up with distance from the camera, so zooming out would wash the
	-- maze out. Thin it (on this computer only) by as much as the camera moved away.
	if atmosphere then atmosphere.Density = baseDensity / zoomed end
	camera.Focus = CFrame.new(focus)        -- what we're looking at (sounds are heard from here: SoundEffects)

	if character then fadeBlockingWalls(focus, camPos, character) end
end)
