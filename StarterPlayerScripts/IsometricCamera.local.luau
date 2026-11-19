-- Fixed isometric camera that follows the player.
-- Runs on each player's own computer (LocalScript), because the camera is client-side.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

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
-- a teammate who's still alive, sticking with the same one while they are
local watching = nil
local function teammateRoot()
	local myRole = player:GetAttribute("Role")
	if watching and watching.Parent and aliveRoot(watching.Character) then
		return aliveRoot(watching.Character), watching.Character
	end
	watching = nil
	for _, other in Players:GetPlayers() do
		if other ~= player and myRole and other:GetAttribute("Role") == myRole and aliveRoot(other.Character) then
			watching = other
			return aliveRoot(other.Character), other.Character
		end
	end
	return nil
end

local lastFocus = nil

-- BindToRenderStep runs right before each frame is drawn, after Roblox's default camera
RunService:BindToRenderStep("IsometricCamera", Enum.RenderPriority.Camera.Value + 1, function()
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = FOV

	local character = player.Character
	local root = aliveRoot(character)
	if not root then
		root, character = teammateRoot()      -- watch a teammate instead
	end
	local focus = root and root.Position or lastFocus
	if not focus then return end
	lastFocus = focus

	local camPos = focus + DIRECTION * DISTANCE
	camera.CFrame = CFrame.lookAt(camPos, focus)
	camera.Focus = CFrame.new(focus)        -- what we're looking at (sounds are heard from here: SoundEffects)

	if character then fadeBlockingWalls(focus, camPos, character) end
end)
