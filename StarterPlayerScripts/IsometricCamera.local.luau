-- Fixed isometric camera that follows the player.
-- Runs on each player's own computer (LocalScript), because the camera is client-side.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Config"))

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
		end
		table.insert(ignore, part)
	end
end

-- BindToRenderStep runs right before each frame is drawn, after Roblox's default camera
RunService:BindToRenderStep("IsometricCamera", Enum.RenderPriority.Camera.Value + 1, function()
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = FOV

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local focus = root.Position
	local camPos = focus + DIRECTION * DISTANCE
	camera.CFrame = CFrame.lookAt(camPos, focus)

	fadeBlockingWalls(focus, camPos, character)
end)
