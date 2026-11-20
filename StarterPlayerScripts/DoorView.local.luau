-- Draws the maze's doors the way YOUR TEAM last saw them.
--
-- The real door parts (moved by the server, see Doors) are hidden on this computer. Each gets a
-- local copy, a "ghost", that follows the real door only while your team can see it (FogOfWar
-- decides, in FogState.doors). Out of view, the ghost stays as you last saw it: a door that shut
-- behind your back still looks open until you come back and look.
--
-- While you can see a door that's about to move, it RUMBLES (the warning): the slab shakes harder
-- and harder, and dust puffs up from the slot in the floor. A door that's down in the floor rises
-- just far enough for its top edge to rattle at floor level. The rumbling sound is in SoundEffects. The real parts still do all the blocking - of bodies, rays and sight -
-- since the ghosts can't be hit by anything.

local RunService = game:GetService("RunService")

local FogState = require(script.Parent:WaitForChild("FogState"))

local SHAKE_START = 0.06   -- studs the slab shakes at the start of the warning...
local SHAKE_END   = 0.22   -- ...building up to this just before it moves
local SHAKE_MOVE  = 0.08   -- ...and this while it moves
local SHAKE_SPEED = 28     -- how fast it shakes (higher = a finer rattle)
local PEEK        = 0.35   -- a door down in the floor rises this far out of it while rumbling
local DUST_RATE   = 55     -- dust puffs per second at the height of the rumble
local DUST_COLOR  = Color3.fromRGB(200, 188, 160)   -- pale, so it stands out against the dark floor

local folder = nil
local ghosts = {}     -- [real door part] = { part = ghost, dust (ParticleEmitter), seed }

local function clear()
	for _, g in ghosts do g.part:Destroy() g.dustPart:Destroy() end
	table.clear(ghosts)
	table.clear(FogState.doorGhosts)
end

local function addDoor(real)
	if ghosts[real] then return end
	local ghost = real:Clone()
	ghost.Name = "DoorGhost"
	ghost.Anchored = true
	ghost.CanCollide, ghost.CanQuery, ghost.CanTouch = false, false, false
	ghost:ClearAllChildren()
	ghost.Parent = folder

	-- Dust rises from the door's slot in the floor while it rumbles: an invisible strip along the
	-- slot that the dust is puffed out of
	local closedCF = real:GetAttribute("ClosedCFrame") or real.CFrame
	local slot = Instance.new("Part")
	slot.Name = "DoorDust"
	slot.Anchored = true
	slot.CanCollide, slot.CanQuery, slot.CanTouch = false, false, false
	slot.Transparency = 1
	slot.Size = Vector3.new(ghost.Size.X + (ghost.Size.X > ghost.Size.Z and 0 or 1.5), 0.2,
		ghost.Size.Z + (ghost.Size.Z > ghost.Size.X and 0 or 1.5))
	slot.CFrame = closedCF - Vector3.new(0, ghost.Size.Y / 2 - 0.1, 0)   -- on the floor
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Color = ColorSequence.new(DUST_COLOR)
	dust.LightEmission = 0.15
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 4) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.6, 0.55), NumberSequenceKeypoint.new(1, 1) })
	dust.Lifetime = NumberRange.new(0.8, 1.4)
	dust.Speed = NumberRange.new(2, 5)
	dust.SpreadAngle = Vector2.new(25, 25)
	dust.EmissionDirection = Enum.NormalId.Top
	dust.Rotation = NumberRange.new(0, 360)
	dust.RotSpeed = NumberRange.new(-40, 40)
	dust.Acceleration = Vector3.new(0, -1, 0)
	dust.Rate = 0
	dust.Parent = slot
	slot.Parent = folder

	ghosts[real] = { part = ghost, dustPart = slot, dust = dust, seed = math.random() * 100 }
	FogState.doorGhosts[real] = ghost
end

local function watchMaze(maze)
	clear()
	if folder then folder:Destroy() end
	folder = Instance.new("Folder")
	folder.Name = "DoorGhosts"
	folder.Parent = workspace
	for _, child in maze:GetChildren() do
		if child.Name == "Door" then addDoor(child) end
	end
end

workspace.ChildAdded:Connect(function(child)
	if child.Name == "Maze" and child:IsA("Model") then
		task.wait()   -- let its parts and attributes arrive
		watchMaze(child)
	end
end)
task.spawn(function()
	watchMaze(workspace:WaitForChild("Maze", math.huge))
end)

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	local serverNow = workspace:GetServerTimeNow()
	for real, g in ghosts do
		if not real.Parent then
			g.part:Destroy()
			g.dustPart:Destroy()
			ghosts[real] = nil
			FogState.doorGhosts[real] = nil
			continue
		end
		real.LocalTransparencyModifier = 1          -- only the ghost is drawn
		local entry = FogState.doors[real]
		local seen = entry == nil or entry.seen
		local cf
		if seen then
			cf = FogState.doorPose(real)
		else
			cf = entry.closed and real:GetAttribute("ClosedCFrame") or real:GetAttribute("OpenCFrame")
			cf = cf or real.CFrame
		end

		local state = real:GetAttribute("State")
		local warning = seen and state == "warning"
		local moving = seen and state == "moving"
		local shake, dustRate = 0, 0
		if warning then
			-- builds up from the start of the warning to the moment it moves
			local warnAt, moveAt = real:GetAttribute("WarnAt") or serverNow, real:GetAttribute("MoveAt") or serverNow
			local build = math.clamp((serverNow - warnAt) / math.max(0.1, moveAt - warnAt), 0, 1)
			shake = SHAKE_START + (SHAKE_END - SHAKE_START) * build
			dustRate = DUST_RATE * (0.4 + 0.6 * build)
			if real:GetAttribute("Open") == false then
				cf += Vector3.new(0, PEEK, 0)        -- down in the floor: rise until its top edge shows
			end
		elseif moving then
			shake, dustRate = SHAKE_MOVE, DUST_RATE * 0.6
			local openCF = real:GetAttribute("OpenCFrame")
			if real:GetAttribute("Open") == false and openCF and cf.Y < openCF.Y + PEEK then
				cf += Vector3.new(0, openCF.Y + PEEK - cf.Y, 0)   -- rising: carry on from where it peeked
			end
		end
		if shake > 0 then
			-- smooth random wobble (noise) rather than a fresh random spot each frame
			local t = now * SHAKE_SPEED
			cf += Vector3.new(math.noise(t, g.seed) * 2, math.noise(t, g.seed + 10) * 0.8, math.noise(t, g.seed + 20) * 2) * shake
		end
		g.dust.Rate = dustRate
		g.part.CFrame = cf
		-- for checking in Studio: what this player knows about the door
		if g.part:GetAttribute("Seen") ~= seen then g.part:SetAttribute("Seen", seen) end
		local shut = entry and entry.closed
		if g.part:GetAttribute("RememberedShut") ~= shut then g.part:SetAttribute("RememberedShut", shut) end
	end
end)
