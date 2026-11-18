-- Fog of war + line of sight.
-- Runs on each player's computer, so every player has their own fog.
--
-- The maze is covered by a grid of small fog TILES. Each tile is in one of these modes:
--   "box"      - never seen, far from anything seen -> a solid black BOX (hides walls and everything)
--   "fringe"   - never seen, but within a few tiles of something seen -> two dark see-through
--                SHEETS (one on the floor, one up at fog-top height). Looking down through two dim
--                layers gives a soft shadow, so the edge of the fog fades gradually instead of
--                being a black wall.
--   "explored" - seen before -> a thin dark sheet on the floor (and on the wall top for wall tiles).
--                Clear while in view, dimmed when not.
--
-- Why sheets instead of see-through boxes: see-through boxes side by side show their inner faces,
-- which stack up into visible grid lines. Opaque boxes merge seamlessly, and flat sheets that don't
-- overlap read as one smooth layer - so we use each where it looks right.
--
-- Vision is a CONE in the direction your avatar faces (plus a small circle around you).
-- Line of sight = one raycast from the player to the centre of each nearby tile in that cone.
-- Anything tagged "HiddenByFog" (like the monster) is only shown while its tile is in view,
-- or when it's close with no wall between (then the fog clears in a small circle around it).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer

local TILE         = 2      -- fog tile size in studs. Smaller = smoother but more parts/raycasts (2.5 = good balance, 2 = PC limit)
local VIEW_RANGE   = 80     -- how far you can see (studs)
local SOFT_EDGE    = 0.35   -- outer 35% of the view range fades gradually instead of a hard edge
local CONE_ANGLE   = 110    -- total width of the vision cone in degrees (360 = see all around)
local CONE_SOFT    = 20     -- the outer this-many degrees of the cone fade gradually
local NEAR_RADIUS  = 12     -- you always sense tiles this close, even behind you
local SENSE_RANGE  = 45     -- tagged objects (the monster) this close with no wall between are shown even outside your view
local SENSE_REVEAL = 10     -- ...by clearing the fog in a circle this many studs around them
local UPDATE_EVERY = 0.05   -- seconds between line-of-sight checks
local EYE_HEIGHT   = 3      -- rays are cast at this height above the floor
local FADE_SPEED   = 10     -- how fast tiles fade in/out
local POCKET_MAX   = 12     -- forgiveness: unseen pockets up to this many tiles, fully surrounded by seen tiles, get revealed too (0 = off)

local FOG_COLOR  = Color3.fromRGB(8, 8, 14)
local T_HIDDEN   = 0        -- transparency for each state (0 = black, 1 = clear)
local T_EXPLORED = 0.5      -- higher = brighter remembered areas
local T_VISIBLE  = 1
local T_PEEK     = 0.7      -- hidden fog between the camera and you is see-through, so it never hides your character
local FRINGE     = { 0.55, 0.3, 0.12 }  -- how see-through the unseen tiles 1, 2, 3 tiles away from seen ones are ({} = off)
local SHEET      = 0.005    -- thickness of sheets (paper-thin so their edges don't show as grid lines)
local RING_CLEAR = 0       -- outside the near (bottom-of-screen) walls: this many studs stay fully clear...
local RING_NOISE = 4        -- how far (studs) the fog's edge wobbles in and out, so it isn't a straight line (0 = straight)
local RING_FADE  = 10      -- ...then the fog fades in over this many studs (keep CLEAR + FADE <= the maze's BORDER, or the fade runs past the floor's edge)

-- Where the camera sits relative to the player (shared with the IsometricCamera script)
local CAMERA_DIRECTION = require(game:GetService("ReplicatedStorage"):WaitForChild("Config")).CAMERA_DIRECTION

local NEIGHBOURS4 = { {1, 0}, {-1, 0}, {0, 1}, {0, -1} }
local NEIGHBOURS8 = { {1, 0}, {-1, 0}, {0, 1}, {0, -1}, {1, 1}, {1, -1}, {-1, 1}, {-1, -1} }

local maze, fogFolder
local tiles = {}            -- tiles[x][z] = { x, z, block, top, center, onWall, mode, ring, explored, target, current }
local animating = {}        -- tiles currently fading (so we don't touch all of them every frame)
local lastVisible = {}      -- tiles that were visible (or peeked) on the previous update
local newlyRevealed = {}    -- tiles revealed since the last fringe update
local count, floorY, wallH, half = 0, 0, 0, 0
local ready = false
local buildId = 0           -- bumps every rebuild, so an older unfinished build stops

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include  -- rays only hit the maze

local function setTarget(tile, t)
	if tile.target ~= t then
		tile.target = t
		animating[tile] = true
	end
end

-- The tile's resting transparency when it's not in view
local function restingState(tile)
	if tile.explored then return T_EXPLORED end
	if tile.ring then return FRINGE[tile.ring] end
	return T_HIDDEN
end

-- Apply a transparency value to a tile's part(s), depending on its mode
local function applyTransparency(tile)
	local t = tile.current
	if tile.mode == "fringe" then
		-- light passes through two sheets, so each gets the square root (0.5 * 0.5 = 0.25 etc.)
		local each = math.sqrt(t)
		tile.block.Transparency = each
		tile.top.Transparency = each
	else
		tile.block.Transparency = t
		if tile.top then tile.top.Transparency = t end
	end
end

local function makeSheet(tile, height)
	local sheet = tile.block:Clone()
	sheet.Size = Vector3.new(TILE, SHEET, TILE)
	sheet.Position = tile.center + Vector3.new(0, height + SHEET / 2 + 0.02, 0)
	sheet.Parent = fogFolder
	return sheet
end

local function flattenBlock(tile)
	tile.block.Size = Vector3.new(TILE, SHEET, TILE)
	tile.block.Position = tile.center + Vector3.new(0, SHEET / 2 + 0.02, 0)
end

-- Unseen tile near something seen: box -> two sheets (floor + fog-top height)
local function toFringe(tile)
	tile.mode = "fringe"
	flattenBlock(tile)
	tile.top = tile.top or makeSheet(tile, wallH + 1 - SHEET)
	applyTransparency(tile)
end

-- First time a tile is seen: a sheet on the floor (+ one on the wall top for wall tiles)
local function reveal(tile)
	tile.explored = true
	tile.ring = nil
	tile.mode = "explored"
	flattenBlock(tile)
	if tile.onWall then
		tile.top = tile.top or makeSheet(tile, wallH)
		tile.top.Position = tile.center + Vector3.new(0, wallH + SHEET / 2 + 0.02, 0)
	elseif tile.top then
		tile.top:Destroy()
		tile.top = nil
	end
	applyTransparency(tile)
	table.insert(newlyRevealed, tile)
end

local function tileRange(minV, maxV)
	-- indices of tiles overlapping [minV, maxV] along one axis
	local a = math.max(1, math.floor((minV + half) / TILE) + 1)
	local b = math.min(count, math.ceil((maxV + half) / TILE))
	return a, b
end

local function buildFog(newMaze)
	if newMaze == maze and fogFolder and fogFolder.Parent then return end -- already built for this maze
	buildId += 1
	local myId = buildId
	ready = false
	if fogFolder then fogFolder:Destroy() end
	table.clear(animating)
	table.clear(lastVisible)
	table.clear(newlyRevealed)

	maze = newMaze
	local n, S = maze:GetAttribute("Cells"), maze:GetAttribute("CellSize")
	wallH, floorY = maze:GetAttribute("WallHeight"), maze:GetAttribute("FloorY")
	half = n * S / 2
	count = math.ceil(n * S / TILE)
	rayParams.FilterDescendantsInstances = { maze }

	-- Parts created by a LocalScript only exist on this player's screen
	fogFolder = Instance.new("Folder")
	fogFolder.Name = "FogOfWar"
	fogFolder.Parent = workspace

	tiles = {}
	for x = 1, count do
		tiles[x] = {}
		for z = 1, count do
			local center = Vector3.new((x - 0.5) * TILE - half, floorY, (z - 0.5) * TILE - half)
			local block = Instance.new("Part")
			block.Name = "Fog"
			block.Anchored = true
			block.CanCollide, block.CanQuery, block.CanTouch = false, false, false
			block.CastShadow = false
			block.Material = Enum.Material.SmoothPlastic
			block.Color = FOG_COLOR
			block.Size = Vector3.new(TILE, wallH + 1, TILE)
			block.Position = center + Vector3.new(0, (wallH + 1) / 2, 0)
			block.Parent = fogFolder
			tiles[x][z] = { x = x, z = z, block = block, center = center, onWall = false, mode = "box",
				explored = false, target = T_HIDDEN, current = T_HIDDEN }
		end
		if x % 10 == 0 then
			task.wait()  -- build in chunks so the game doesn't freeze
			if myId ~= buildId then return end  -- a newer maze arrived; abandon this build
		end
	end

	-- OUTSIDE THE MAZE.
	-- The camera looks from the -X/-Z corner, so the -X and -Z borders are the NEAR ones (bottom of
	-- the screen) and the +X and +Z borders the FAR ones (top of the screen).
	--   far borders:  fog blocks (same colour/height as unexplored fog) right up against the outer
	--                 wall, so there's nothing to see past them
	--   near borders: a clear strip by the wall (RING_CLEAR studs), then the fog fades in over
	--                 RING_FADE studs, then solid fog. The fade is made of small floor tiles whose
	--                 darkness depends on distance from the wall PLUS some smooth random "noise", so
	--                 the edge of the fog wobbles instead of running in a straight line. These are
	--                 flat sheets on the floor: tall blocks on the camera's side would hide the fade.
	local wallFace = half + 1                    -- the outer walls stick out about 1 stud past the grid
	local outer = half + 850                     -- far enough to fill the view (parts max 2048 wide)
	local fogH = wallH + 1

	local function outsidePart(x1, x2, z1, z2, height, transparency)
		local p = Instance.new("Part")
		p.Name = "OutsideFog"
		p.Anchored = true
		p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
		p.CastShadow = false
		p.Material = Enum.Material.SmoothPlastic
		p.Color = FOG_COLOR
		p.Transparency = transparency
		p.Size = Vector3.new(x2 - x1, height, z2 - z1)
		p.Position = Vector3.new((x1 + x2) / 2, floorY + 0.02 + height / 2, (z1 + z2) / 2)
		p.Parent = fogFolder
	end
	-- An L-shaped band (west strip + north strip) covering distances d1..d2 out from the near walls
	-- (measured the "square" way, so the corner is filled too), running up to the far fog at +half
	local function nearBand(d1, d2, height, transparency)
		outsidePart(-d2, -d1, -d2, half, height, transparency)   -- west side, including the corner
		outsidePart(-d1, half, -d2, -d1, height, transparency)   -- north side
	end

	-- far borders: blocks from the edge of the grid outwards
	outsidePart(half, outer, -outer, outer, fogH, 0)        -- east (+X), full length
	outsidePart(-outer, half, half, outer, fogH, 0)         -- south (+Z)
	-- near borders: a noisy fade made of TILE-sized floor tiles, then solid.
	-- math.noise gives smooth random values (roughly -0.5..0.5) that change gradually with position;
	-- we add two layers - big gentle bulges plus smaller wiggles - and use the result to push each
	-- tile's distance out or in by up to RING_NOISE studs.
	local seed = math.random() * 1000            -- a different pattern every maze
	local function wobble(x, z)
		local n = math.noise(x * 0.06 + seed, z * 0.06 - seed) * 2
			+ math.noise(x * 0.2 - seed, z * 0.2 + seed) * 0.8
		return math.clamp(n, -1, 1) * RING_NOISE
	end
	local rowsOut = math.ceil((RING_CLEAR + RING_FADE + RING_NOISE) / TILE) + 1  -- +1 so it's fully dark before the solid part
	local bandOuter = wallFace + rowsOut * TILE  -- the noisy band ends here; solid fog beyond
	local rowsIn = math.ceil((wallFace + half) / TILE)   -- tiles from the wall face across to the far side
	local made = 0
	for i = -rowsOut, rowsIn - 1 do
		for k = -rowsOut, rowsIn - 1 do
			if i >= 0 and k >= 0 then continue end          -- inside the walls: not ours
			local x1, z1 = -wallFace + i * TILE, -wallFace + k * TILE
			local cx, cz = x1 + TILE / 2, z1 + TILE / 2
			local d = math.max(-cx, -cz) - wallFace          -- how far outside the near walls
			local darkness = math.clamp((d - RING_CLEAR + wobble(cx, cz)) / RING_FADE, 0, 1)
			if darkness > 0.01 then
				outsidePart(x1, x1 + TILE, z1, z1 + TILE, SHEET, darkness > 0.99 and 0 or 1 - darkness)
				made += 1
				if made % 400 == 0 then
					task.wait()   -- build in chunks so the game doesn't freeze
					if myId ~= buildId then return end
				end
			end
		end
	end
	nearBand(bandOuter, outer, SHEET, 0)

	-- Mark which tiles overlap a wall
	for _, part in maze:GetChildren() do
		if part.Name == "Wall" then
			local p, s = part.Position, part.Size
			local x1, x2 = tileRange(p.X - s.X / 2, p.X + s.X / 2)
			local z1, z2 = tileRange(p.Z - s.Z / 2, p.Z + s.Z / 2)
			for x = x1, x2 do
				for z = z1, z2 do
					tiles[x][z].onWall = true
				end
			end
		end
	end
	ready = true
end

local function tileIndex(pos)
	return math.floor((pos.X + half) / TILE) + 1, math.floor((pos.Z + half) / TILE) + 1
end

-- FORGIVENESS: find small groups of unseen tiles that are completely surrounded by seen tiles
-- (e.g. a corner a ray just missed) and reveal them, so revealing looks smooth instead of speckled.
-- Uses a "flood fill": start at an unseen tile, spread to unseen neighbours, and give up as soon
-- as the group gets bigger than POCKET_MAX or touches a group we already know is big.
local function fillPockets(cx, cz, r, visibleNow)
	if POCKET_MAX <= 0 then return end
	local big = {}    -- unseen tiles known to belong to a large (real) unexplored area
	for x = math.max(1, cx - r), math.min(count, cx + r) do
		for z = math.max(1, cz - r), math.min(count, cz + r) do
			local start = tiles[x][z]
			if start.explored or big[start] then continue end

			local group, inGroup = {}, { [start] = true }
			local stack = { start }
			local open = false
			while #stack > 0 and not open do
				local t = table.remove(stack)
				table.insert(group, t)
				if #group > POCKET_MAX then open = true break end
				for _, d in NEIGHBOURS4 do
					local nt = tiles[t.x + d[1]] and tiles[t.x + d[1]][t.z + d[2]]
					if nt and not nt.explored and not inGroup[nt] then
						if big[nt] then open = true break end
						inGroup[nt] = true
						table.insert(stack, nt)
					end
				end
			end

			if open then
				for t in inGroup do big[t] = true end
			else
				-- A closed pocket: reveal it, matching the brightness of the tiles around it
				local sum, n, nearVisible = 0, 0, false
				for t in inGroup do
					for _, d in NEIGHBOURS4 do
						local nt = tiles[t.x + d[1]] and tiles[t.x + d[1]][t.z + d[2]]
						if nt and not inGroup[nt] then
							sum += nt.target
							n += 1
							if visibleNow[nt] then nearVisible = true end
						end
					end
				end
				local fill = n > 0 and sum / n or T_EXPLORED
				for t in inGroup do
					reveal(t)
					setTarget(t, fill)
					if nearVisible then visibleNow[t] = true end -- so it dims again when you look away
				end
			end
		end
	end
end

-- SOFT FOG EDGE: unseen tiles 1..#FRINGE steps away from a seen tile become see-through sheets.
-- Only spreads out from tiles revealed since last time, so it's cheap. It doesn't spread past
-- wall tiles, so it can't leak a view into the next corridor.
local function updateFringe(visibleNow)
	if #FRINGE == 0 then table.clear(newlyRevealed) return end
	local queue = {}
	local function setRing(t, ring)
		t.ring = ring
		if t.mode == "box" then toFringe(t) end
		if not visibleNow[t] then setTarget(t, FRINGE[ring]) end
		table.insert(queue, t)
	end
	for _, t in newlyRevealed do
		for _, d in NEIGHBOURS8 do
			local nt = tiles[t.x + d[1]] and tiles[t.x + d[1]][t.z + d[2]]
			if nt and not nt.explored and (nt.ring == nil or nt.ring > 1) then setRing(nt, 1) end
		end
	end
	table.clear(newlyRevealed)
	local i = 1
	while i <= #queue do
		local t = queue[i]
		i += 1
		if t.ring < #FRINGE and not t.onWall and not t.explored then
			for _, d in NEIGHBOURS8 do
				local nt = tiles[t.x + d[1]] and tiles[t.x + d[1]][t.z + d[2]]
				if nt and not nt.explored and (nt.ring == nil or nt.ring > t.ring + 1) then
					setRing(nt, t.ring + 1)
				end
			end
		end
	end
end

-- Things tagged "HiddenByFog" (e.g. the monster) are hidden unless you can see them. Three states:
--   "seen"   - its tile is in your view: drawn normally
--   "sensed" - outside your view, but close (SENSE_RANGE) with no wall between: the fog clears in a
--              small circle (SENSE_REVEAL) around it, so you can see it even behind you. Only for
--              now - the area isn't added to your map.
--   "hidden" - not drawn at all (its light is switched off too)
-- Sets a local "VisibleToMe" attribute other scripts can read (e.g. the monster ping).

-- Clear the fog around a point, for this update only (tiles behind a wall from it stay fogged)
local function revealAround(p, visibleNow)
	local from = Vector3.new(p.X, floorY + EYE_HEIGHT, p.Z)
	local x1, x2 = tileRange(p.X - SENSE_REVEAL, p.X + SENSE_REVEAL)
	local z1, z2 = tileRange(p.Z - SENSE_REVEAL, p.Z + SENSE_REVEAL)
	for x = x1, x2 do
		for z = z1, z2 do
			local tile = tiles[x][z]
			local to = tile.center + Vector3.new(0, EYE_HEIGHT, 0)
			local offset = to - from
			if offset.Magnitude <= SENSE_REVEAL and (offset.Magnitude < 0.6 or workspace:Raycast(from, offset - offset.Unit * 0.5, rayParams) == nil) then
				setTarget(tile, T_VISIBLE)
				visibleNow[tile] = true   -- so it goes back to fog once the monster moves on
			end
		end
	end
end

local function updateHiddenObjects(visibleNow, eye)
	for _, obj in CollectionService:GetTagged("HiddenByFog") do
		local ok, pivot = pcall(obj.GetPivot, obj)
		if not ok then continue end
		local p = pivot.Position
		local tx, tz = tileIndex(p)
		local tile = tiles[tx] and tiles[tx][tz]

		local state = "hidden"
		if tile and visibleNow[tile] and tile.explored and tile.target > T_EXPLORED + 0.1 then
			state = "seen"
		else
			local target = Vector3.new(p.X, eye.Y, p.Z)
			if (target - eye).Magnitude <= SENSE_RANGE and workspace:Raycast(eye, target - eye, rayParams) == nil then
				state = "sensed"
			end
		end

		if state == "sensed" then revealAround(p, visibleNow) end

		if obj:GetAttribute("FogState") ~= state then
			obj:SetAttribute("FogState", state)                 -- set on this computer only; not shared
			obj:SetAttribute("VisibleToMe", state ~= "hidden")
			for _, d in obj:GetDescendants() do
				if d:IsA("BasePart") then
					d.LocalTransparencyModifier = state == "hidden" and 1 or 0
				elseif d:IsA("Light") then
					d.Enabled = state ~= "hidden"
				end
			end
		end
	end
end

local function updateVisibility()
	if not ready or not (maze and maze.Parent) then return end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local eye = Vector3.new(root.Position.X, floorY + EYE_HEIGHT, root.Position.Z)
	local visibleNow = {}

	-- Which way the avatar is facing, flattened onto the ground
	local facing = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	facing = facing.Magnitude > 0.01 and facing.Unit or Vector3.new(0, 0, -1)
	local halfAngle = CONE_ANGLE / 2
	local edgeStart = VIEW_RANGE * (1 - SOFT_EDGE)

	-- Only check tiles inside a square around the player (not the whole grid)
	local cx, cz = tileIndex(eye)
	local r = math.ceil(VIEW_RANGE / TILE)
	for x = math.max(1, cx - r), math.min(count, cx + r) do
		for z = math.max(1, cz - r), math.min(count, cz + r) do
			local tile = tiles[x][z]
			local target = tile.center + Vector3.new(0, EYE_HEIGHT, 0)
			local offset = target - eye
			local dist = offset.Magnitude
			if dist > VIEW_RANGE then continue end

			-- 1. Is it inside the vision cone? (cheap maths, done before the raycast)
			local coneFade = 0
			if dist > NEAR_RADIUS then
				local angle = math.deg(math.acos(math.clamp(offset.Unit:Dot(facing), -1, 1)))
				if angle > halfAngle then continue end
				coneFade = math.clamp((angle - (halfAngle - CONE_SOFT)) / CONE_SOFT, 0, 1)
			end

			-- 2. Is there a wall in the way? (stop the ray 0.5 studs short, so tiles whose
			--    centre sits right on a wall's surface still count as visible)
			if dist < 0.6 or workspace:Raycast(eye, offset - offset.Unit * 0.5, rayParams) == nil then
				visibleNow[tile] = true
				if not tile.explored then reveal(tile) end
				-- Fade toward "explored" near the edge of the range or the edge of the cone
				local distFade = math.clamp((dist - edgeStart) / (VIEW_RANGE - edgeStart), 0, 1)
				local k = math.max(distFade, coneFade)
				setTarget(tile, T_VISIBLE + (T_EXPLORED - T_VISIBLE) * k)
			end
		end
	end

	-- Forgiveness: reveal small unseen pockets surrounded by seen tiles
	fillPockets(cx, cz, r + 2, visibleNow)

	-- Soft edge around everything seen
	updateFringe(visibleNow)

	-- Unseen fog between the camera and the player becomes see-through (explored sheets never block the view)
	for d = 0, 14, 2 do
		local px, pz = tileIndex(eye + CAMERA_DIRECTION * d)
		for dx = -1, 1 do
			for dz = -1, 1 do
				local tile = tiles[px + dx] and tiles[px + dx][pz + dz]
				if tile and not tile.explored and not visibleNow[tile] then
					setTarget(tile, math.max(restingState(tile), T_PEEK))
					visibleNow[tile] = true -- so it gets reset next update once we move away
				end
			end
		end
	end

	-- The monster etc. (before the reset below, since sensing one clears fog around it)
	updateHiddenObjects(visibleNow, eye)

	-- Anything that was visible/peeked last time but isn't now goes back to its resting state
	for tile in lastVisible do
		if not visibleNow[tile] then setTarget(tile, restingState(tile)) end
	end

	lastVisible = visibleNow
end

-- Rebuild the fog whenever the server builds a new maze
workspace.ChildAdded:Connect(function(child)
	if child.Name == "Maze" and child:IsA("Model") then
		task.wait() -- let attributes arrive
		buildFog(child)
	end
end)
task.spawn(buildFog, workspace:WaitForChild("Maze"))

-- Line-of-sight checks many times a second
task.spawn(function()
	while true do
		updateVisibility()
		task.wait(UPDATE_EVERY)
	end
end)

-- Smooth fading: only touches tiles that are mid-fade
RunService.RenderStepped:Connect(function(dt)
	local alpha = math.min(1, dt * FADE_SPEED)
	for tile in animating do
		tile.current += (tile.target - tile.current) * alpha
		if math.abs(tile.target - tile.current) < 0.01 then
			tile.current = tile.target
			animating[tile] = nil
		end
		applyTransparency(tile)
	end
end)
