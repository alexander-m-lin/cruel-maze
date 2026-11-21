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
-- Line of sight = a FAN of rays from your eyes, spread across the cone. Each ray stops at the first
-- wall, and every tile it passes over on the way is in view. (The old way, one ray per tile, is
-- kept as SIGHT_MODE = "tiles" for comparison; it cast about ten times as many rays.)
-- Anything tagged "HiddenByFog" (like the monster) is only shown while its tile is in view,
-- or when it's close with no wall between (then the fog clears in a small circle around it).
--
-- TEAMS: survivors share sight with each other. Monsters and the Maze Master are one team: they
-- share the sight of every monster, the AI ones too, plus the Maze Master's WARDS (all round each
-- floating eye), every CRUSHING WALL (its cell and a little past it each way), HAUNTED
-- survivors' cones (see Haunt in MazeMaster), and a small ring round every REVEALED survivor. The Maze Master has no eyes of their own,
-- but knows the whole layout (all of it shows as explored) and how every door stands. Enemies -
-- monsters for survivors, survivors for the monster team - are hidden unless your team sees them;
-- your own side is always shown.
--
-- DOORS: your map remembers each door the way your team last saw it. A door's tiles count as wall
-- (for the minimap and the fog's wall-top sheets) while you remember it shut, and only change
-- when the door is in view again. DoorView draws the door itself the same way.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer
local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Config"))
local FogState = require(script.Parent:WaitForChild("FogState"))   -- shared with the minimap

local TILE         = 2      -- fog tile size in studs. Smaller = smoother but more parts/raycasts (2.5 = good balance, 2 = PC limit)
local VIEW_RANGE   = Config.VIEW_RANGE   -- how far you can see (studs; set in Config)
local SOFT_EDGE    = 0.35   -- outer 35% of the view range fades gradually instead of a hard edge
local CONE_ANGLE   = Config.VIEW_CONE    -- total width of the vision cone in degrees (360 = see all around)
local CONE_SOFT    = 20     -- the outer this-many degrees of the cone fade gradually
local NEAR_RADIUS  = Config.VIEW_NEAR    -- you always sense tiles this close, even behind you
local SENSE_RANGE  = 45     -- tagged objects (the monster) this close with no wall between are shown even outside your view
local SENSE_REVEAL = 10     -- ...by clearing the fog in a circle this many studs around them
local UPDATE_EVERY = 0.05   -- seconds between line-of-sight checks
local TEAM_UPDATE_EVERY = 0.05  -- seconds between refreshes of each teammate's sight (shared vision).
                                -- Same as your own: one sight pass costs ~1.3 ms on PC. Raise it
                                -- (e.g. 0.1-0.15) if phones struggle - teammates' fog gets steppier.
local EYE_HEIGHT   = 3      -- rays are cast at this height above the floor
local FADE_SPEED   = 10     -- how fast tiles fade in/out
local POCKET_MAX   = 12     -- forgiveness: unseen pockets up to this many tiles, fully surrounded by seen tiles, get revealed too (0 = off)
local SIGHT_MODE   = "fan"  -- "fan": rays spread across the view; "tiles": one ray per tile (old, ~10x the rays)
local FAN_SPACING  = 2      -- fan: studs between neighbouring rays at the far end of their reach (smaller = more rays, fewer gaps; 3 starts to miss ~2% of tiles)
local MARCH_STEP   = TILE / 2  -- fan: how far apart (studs) the points are where a ray's tiles get marked

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
local CAMERA_DIRECTION = Config.CAMERA_DIRECTION

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
local doorVersion = 0       -- bumps whenever a door starts or stops moving (relic rings re-check their sight)

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include  -- rays only hit the maze

-- Cost counters (shown as attributes on the local player in Studio; see the end of this script)
local stats = { rays = 0, sightTime = 0, pocketTime = 0, updateTime = 0, updates = 0 }
local function raycast(from, offset)
	stats.rays += 1
	return workspace:Raycast(from, offset, rayParams)
end

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
	FogState.doors = {}

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
					tiles[x][z].fixedWall = true
				end
			end
		end
	end
	-- ...and which overlap a door (where its slab stands when shut). Remembered as built.
	for _, part in maze:GetChildren() do
		if part.Name == "Door" then
			local cf = part:GetAttribute("ClosedCFrame") or part.CFrame
			local p, s = cf.Position, part.Size
			local x1, x2 = tileRange(p.X - s.X / 2, p.X + s.X / 2)
			local z1, z2 = tileRange(p.Z - s.Z / 2, p.Z + s.Z / 2)
			local entry = { closed = part:GetAttribute("Open") ~= true, seen = false, tiles = {} }
			for x = x1, x2 do
				for z = z1, z2 do
					local tile = tiles[x][z]
					if not tile.fixedWall then
						table.insert(entry.tiles, tile)
						tile.onWall = entry.closed
					end
				end
			end
			FogState.doors[part] = entry
			part:GetAttributeChangedSignal("State"):Connect(function() doorVersion += 1 end)
		end
	end
	ready = true
	FogState.tiles, FogState.count, FogState.tileSize, FogState.half = tiles, count, TILE, half
	FogState.visible = {}
	FogState.maze = maze
end

-- A remembered door changed: its tiles become wall or floor (with or without a wall-top sheet)
local function rememberDoor(entry, closed)
	entry.closed = closed
	for _, tile in entry.tiles do
		tile.onWall = closed
		if tile.mode == "explored" then
			if closed then
				tile.top = tile.top or makeSheet(tile, wallH)
				tile.top.Position = tile.center + Vector3.new(0, wallH + SHEET / 2 + 0.02, 0)
			elseif tile.top then
				tile.top:Destroy()
				tile.top = nil
			end
			applyTransparency(tile)
		end
	end
end

local function tileIndex(pos)
	return math.floor((pos.X + half) / TILE) + 1, math.floor((pos.Z + half) / TILE) + 1
end

-- FORGIVENESS: find small groups of unseen tiles that are completely surrounded by seen tiles
-- (e.g. a corner a ray just missed) and reveal them, so revealing looks smooth instead of speckled.
-- Uses a "flood fill": start at an unseen tile, spread to unseen neighbours, and give up as soon
-- as the group gets bigger than POCKET_MAX or touches a group we already know is big.
-- A pocket can only become closed when a tile next to it is revealed, so the search starts only
-- from the unseen neighbours of tiles revealed since the last update.
local function fillPockets(visibleNow)
	if POCKET_MAX <= 0 then return end
	local big = {}    -- unseen tiles known to belong to a large (real) unexplored area
	local starts = {}
	for i = 1, #newlyRevealed do
		local t = newlyRevealed[i]
		for _, d in NEIGHBOURS4 do
			local nt = tiles[t.x + d[1]] and tiles[t.x + d[1]][t.z + d[2]]
			if nt and not nt.explored then table.insert(starts, nt) end
		end
	end
	for _, start in starts do
		do
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

-- Which side a role is on: "survivors", or "monsters" (monsters and the Maze Master)
local function sideOf(role)
	if role == Config.Roles.Monster or role == Config.Roles.MazeMaster then return "monsters" end
	if role == Config.Roles.Survivor then return "survivors" end
	return nil
end

-- Clear the fog around a point, for this update only (tiles behind a wall from it stay fogged).
-- Defined after sightFrom (it uses the same fan of rays).
local revealAround

-- Is this point inside a sanctuary? (The monster side never sees survivors in one.)
local function inSanctuary(p)
	local status = game:GetService("ReplicatedStorage"):FindFirstChild("Match")
	local folder = status and status:FindFirstChild("Sanctuaries")
	if not folder then return false end
	for _, info in folder:GetChildren() do
		local lo, hi = info:GetAttribute("Min"), info:GetAttribute("Max")
		if lo and hi and p.X >= lo.X and p.X <= hi.X and p.Z >= lo.Z and p.Z <= hi.Z then return true end
	end
	return false
end

-- eyes: the eye positions of you and your teammates (anyone of them can sense it)
local function updateHiddenObjects(visibleNow, eyes)
	local mySide = sideOf(player:GetAttribute("Role"))
	-- Things that can be hidden: anything tagged (the monsters' bodies), and - for the monster
	-- side - the survivors' characters
	local objects = {}
	local sheltered = {}    -- survivors in a sanctuary: always hidden from the monster side
	for _, obj in CollectionService:GetTagged("HiddenByFog") do
		-- monster bodies are on the monster side: always shown to it
		objects[obj] = mySide == "monsters" and CollectionService:HasTag(obj, "Monster")
	end
	if mySide == "monsters" then
		local now = workspace:GetServerTimeNow()
		for _, other in Players:GetPlayers() do
			if other.Character and other:GetAttribute("Role") == Config.Roles.Survivor then
				-- revealed (by a false relic): shown wherever they are, like a teammate
				objects[other.Character] = (other:GetAttribute("RevealedUntil") or 0) > now
				local root = other.Character:FindFirstChild("HumanoidRootPart")
				if root and inSanctuary(root.Position) then sheltered[other.Character] = true end
			end
		end
		for _, bot in CollectionService:GetTagged("SurvivorBot") do   -- survivor bots (attributes on the model)
			objects[bot] = (bot:GetAttribute("RevealedUntil") or 0) > now
			local root = bot:FindFirstChild("HumanoidRootPart")
			if root and inSanctuary(root.Position) then sheltered[bot] = true end
		end
	end
	-- wards: the monster side's own; survivors see one like anything else, and always once spotted
	local wardInfo = game:GetService("ReplicatedStorage"):FindFirstChild("Match")
	wardInfo = wardInfo and wardInfo:FindFirstChild("WardEyes")
	for _, ward in CollectionService:GetTagged("WardEye") do
		local info = wardInfo and wardInfo:FindFirstChild(ward.Name)
		objects[ward] = mySide == "monsters" or (info ~= nil and info:GetAttribute("Discovered") == true)
	end
	for _, other in Players:GetPlayers() do   -- characters that aren't enemies (any more): show them
		local character = other.Character
		if character and objects[character] == nil and character:GetAttribute("FogState") then objects[character] = true end
	end

	for obj, ally in objects do
		local ok, pivot = pcall(obj.GetPivot, obj)
		if not ok then continue end
		local p = pivot.Position
		local tx, tz = tileIndex(p)
		local tile = tiles[tx] and tiles[tx][tz]

		local state = "hidden"
		if sheltered[obj] then
			state = "hidden"
		elseif ally then
			state = "seen"
		elseif tile and visibleNow[tile] and tile.explored and tile.target > T_EXPLORED + 0.1 then
			state = "seen"
		else
			for _, eye in eyes do
				local target = Vector3.new(p.X, eye.Y, p.Z)
				if (target - eye).Magnitude <= SENSE_RANGE and raycast(eye, target - eye) == nil then
					state = "sensed"
					break
				end
			end
		end

		if state == "sensed" then revealAround(p, visibleNow) end

		if obj:GetAttribute("FogState") ~= state then
			obj:SetAttribute("FogState", state)                 -- set on this computer only; not shared
			obj:SetAttribute("VisibleToMe", state ~= "hidden")
			for _, d in obj:GetDescendants() do
				if d:IsA("BasePart") or d:IsA("Decal") then
					d.LocalTransparencyModifier = state == "hidden" and 1 or 0
				elseif d:IsA("Light") then
					d.Enabled = state ~= "hidden"
				elseif d:IsA("Humanoid") then
					-- a player's name tag would give them away
					d.DisplayDistanceType = state == "hidden" and Enum.HumanoidDisplayDistanceType.None
						or Enum.HumanoidDisplayDistanceType.Viewer
				end
			end
		end
	end
end

-- What one pair of eyes can see: a cone in the direction `facing` (plus a small circle around
-- the eyes), with walls blocking the view. Returns { [tile] = how clear it should look }.
-- Tiles seen for the first time become explored (part of your map) - this is what makes vision
-- shared: whatever a teammate sees is added to your map too.
-- range: how far (default VIEW_RANGE). facing = nil sees all the way around (relic watch rings).

-- How clear a tile looks from these eyes: fading toward "explored" near the edge of the range
-- or the edge of the cone. nil = outside the range or the cone.
local function clearness(tile, eye, facing, range)
	local offset = tile.center + Vector3.new(0, EYE_HEIGHT, 0) - eye
	local dist = offset.Magnitude
	if dist > range then return nil end
	local coneFade = 0
	if facing and dist > NEAR_RADIUS then
		local halfAngle = CONE_ANGLE / 2
		local angle = math.deg(math.acos(math.clamp(offset.Unit:Dot(facing), -1, 1)))
		if angle > halfAngle then return nil end
		coneFade = math.clamp((angle - (halfAngle - CONE_SOFT)) / CONE_SOFT, 0, 1)
	end
	local edgeStart = range * (1 - SOFT_EDGE)
	local distFade = math.clamp((dist - edgeStart) / (range - edgeStart), 0, 1)
	return T_VISIBLE + (T_EXPLORED - T_VISIBLE) * math.max(distFade, coneFade)
end

local function see(seen, tile, value)
	if not tile.explored then reveal(tile) end
	if not seen[tile] or value > seen[tile] then seen[tile] = value end
end

-- THE OLD WAY: one ray to the centre of every tile in range and in the cone. Each ray stops 0.5
-- studs short, so tiles whose centre sits right on a wall's surface still count as visible.
local function sightTiles(eye, facing, range)
	local seen = {}
	local cx, cz = tileIndex(eye)
	local r = math.ceil(range / TILE)
	for x = math.max(1, cx - r), math.min(count, cx + r) do
		for z = math.max(1, cz - r), math.min(count, cz + r) do
			local tile = tiles[x][z]
			local value = clearness(tile, eye, facing, range)   -- (cheap maths before the raycast)
			if value then
				local offset = tile.center + Vector3.new(0, EYE_HEIGHT, 0) - eye
				if offset.Magnitude < 0.6 or raycast(eye, offset - offset.Unit * 0.5) == nil then
					see(seen, tile, value)
				end
			end
		end
	end
	return seen
end

-- THE FAN: rays spread evenly from angle a1 to a2 (radians, around the Y axis), FAN_SPACING studs
-- apart where they end. Each ray runs until it hits a wall (or reaches `reachMax`); every tile it
-- passes over is in view, plus the tile just past where it hit (the wall's near face).
-- sightRange: the range used for fading (the cone's, even for the short rays round the back).
local function fan(seen, eye, facing, reachMax, a1, a2, sightRange)
	local steps = math.max(1, math.ceil((a2 - a1) * reachMax / FAN_SPACING))
	for i = 0, steps do
		local a = a1 + (a2 - a1) * i / steps
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local hit = raycast(eye, dir * reachMax)
		local reach = math.min(reachMax, (hit and hit.Distance or reachMax) + 0.5)
		local lastTile = nil
		local d = 0
		while true do
			local tx, tz = tileIndex(eye + dir * d)
			local tile = tiles[tx] and tiles[tx][tz]
			if tile and tile ~= lastTile then
				lastTile = tile
				if not seen[tile] then              -- (rays near the eyes cross the same tiles: work each out once)
					local value = clearness(tile, eye, facing, sightRange)
					if value then see(seen, tile, value) end
				end
			end
			if d >= reach then break end
			d = math.min(reach, d + MARCH_STEP)
		end
	end
end

local function sightFan(eye, facing, range)
	local seen = {}
	if not facing then
		fan(seen, eye, nil, range, 0, 2 * math.pi, range)
		return seen
	end
	local heading = math.atan2(facing.Z, facing.X)
	local half = math.rad(CONE_ANGLE / 2)
	fan(seen, eye, facing, range, heading - half, heading + half, range)                          -- the cone
	fan(seen, eye, facing, NEAR_RADIUS, heading + half, heading + 2 * math.pi - half, range)      -- the circle round you
	return seen
end

local function sightFrom(eye, facing, range)
	local started = os.clock()
	range = range or VIEW_RANGE
	local seen = SIGHT_MODE == "tiles" and sightTiles(eye, facing, range) or sightFan(eye, facing, range)
	stats.sightTime += os.clock() - started
	return seen
end

function revealAround(p, visibleNow)
	local from = Vector3.new(p.X, floorY + EYE_HEIGHT, p.Z)
	for tile in sightFan(from, nil, SENSE_REVEAL) do
		setTarget(tile, T_VISIBLE)
		visibleNow[tile] = true   -- so it goes back to fog once the monster moves on
	end
end

-- Where a character's eyes are and which way they face (flattened onto the ground)
local function eyesOf(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and humanoid and humanoid.Health > 0) then return nil end
	local eye = Vector3.new(root.Position.X, floorY + EYE_HEIGHT, root.Position.Z)
	local facing = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	facing = facing.Magnitude > 0.01 and facing.Unit or Vector3.new(0, 0, -1)
	return eye, facing
end

-- SHARED VISION: your teammates' sight is worked out here too, from their positions and facing
-- (which every computer already receives). It's refreshed every TEAM_UPDATE_EVERY seconds rather
-- than every update, to save work, and the last result is reused in between.
local teamSight = {}   -- [teammate Player] = { seen = {...}, at = os.clock() }

-- Teammates whose eyes count: everyone on your side who has a character
local function teammates()
	local mySide = sideOf(player:GetAttribute("Role"))
	local list = {}
	if not mySide then return list end
	for _, other in Players:GetPlayers() do
		if other ~= player and sideOf(other:GetAttribute("Role")) == mySide then table.insert(list, other) end
	end
	return list
end

-- Bots whose eyes count for your side: the AI monsters (bodies with no player) for the monster
-- side, the survivor bots for survivors
local function botMonsters()
	local list = {}
	local side = sideOf(player:GetAttribute("Role"))
	if side == "monsters" then
		for _, model in CollectionService:GetTagged("Monster") do
			if not model:GetAttribute("OwnerUserId") then table.insert(list, model) end
		end
	elseif side == "survivors" then
		for _, model in CollectionService:GetTagged("SurvivorBot") do
			local root = model:FindFirstChild("HumanoidRootPart")
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if root and humanoid and humanoid.Health > 0 then table.insert(list, root) end
		end
	end
	return list
end

-- RELIC WATCH RINGS: once your team has spotted a relic (the server decides, see Objectives),
-- you keep seeing all around it until it's collected. The Maze Master watches every relic from
-- the start. Each ring's sight is worked out once and
-- reused until a door starts or stops moving.
local relicSight = {}  -- [relic info Configuration] = { seen = {...}, maze = maze }

local function relicRings()
	local list = {}
	local status = game:GetService("ReplicatedStorage"):FindFirstChild("Match")
	local folder = status and status:FindFirstChild("Relics")
	local role = player:GetAttribute("Role")
	local mazeMaster = role == Config.Roles.MazeMaster
	local monster = role == Config.Roles.Monster
	if not folder or (role ~= Config.Roles.Survivor and not mazeMaster and not monster) then return list end
	for _, info in folder:GetChildren() do
		-- survivors: once their team has spotted it; the Maze Master: every relic, from the start
		-- (false relics included); monsters: once their side has spotted it (false relics: always)
		local known = mazeMaster or info:GetAttribute(monster and "MonsterDiscovered" or "Discovered")
		if known and not info:GetAttribute("Collected") then
			local cached = relicSight[info]
			if not cached or cached.maze ~= maze or cached.doors ~= doorVersion then
				local c = info:GetAttribute("Center")
				cached = { seen = sightFrom(Vector3.new(c.X, floorY + EYE_HEIGHT, c.Z), nil, Config.RELIC_VISION_RADIUS),
					maze = maze, doors = doorVersion }
				relicSight[info] = cached
			end
			table.insert(list, cached.seen)
		end
	end
	for info in relicSight do
		if not info.Parent then relicSight[info] = nil end   -- an old match's relic
	end
	return list
end

-- THE MONSTER SIDE'S FIXED EYES: all round every ward, and every crushing wall's cell plus
-- Config.CRUSHER_VISION studs past it each way (a full circle from its middle: the corridor's
-- walls cut it down to the corridor). Worked out once each, and again when a door moves.
local fixedSight = {}  -- [ward model or crusher key] = { seen = {...}, maze, doors }

local function fixedEye(keyObj, center, radius, list)
	local cached = fixedSight[keyObj]
	if not cached or cached.maze ~= maze or cached.doors ~= doorVersion then
		cached = { seen = sightFrom(Vector3.new(center.X, floorY + EYE_HEIGHT, center.Z), nil, radius),
			maze = maze, doors = doorVersion }
		fixedSight[keyObj] = cached
	end
	cached.used = true
	table.insert(list, cached.seen)
end

local function monsterSideEyes()
	local list = {}
	if sideOf(player:GetAttribute("Role")) ~= "monsters" then return list end
	for _, c in fixedSight do c.used = false end
	for _, ward in CollectionService:GetTagged("WardEye") do
		local center = ward:GetAttribute("Center")
		if center and ward:IsDescendantOf(maze) then fixedEye(ward, center, Config.WARD_VISION_RADIUS, list) end
	end
	-- crushing walls: their slabs carry their resting spot ("Home"); the pair's middle is the cell
	local S = maze:GetAttribute("CellSize")
	local sums = {}
	for _, c in maze:GetChildren() do
		local id, home = c:GetAttribute("Id"), c:GetAttribute("Home")
		if c.Name == "Crusher" and id and home then
			sums[id] = sums[id] or { p = Vector3.zero, n = 0 }
			sums[id].p += home.Position
			sums[id].n += 1
		end
	end
	for id, sum in sums do
		fixedEye("crusher" .. id, sum.p / sum.n, S / 2 + Config.CRUSHER_VISION, list)
	end
	for k, c in fixedSight do
		if not c.used then fixedSight[k] = nil end   -- a ward that's gone, or an old maze's
	end
	return list
end

-- Haunted survivors (players and bots): for the monster side, their cones count as sight
local function hauntedSurvivors()
	local list = {}
	if sideOf(player:GetAttribute("Role")) ~= "monsters" then return list end
	local now = workspace:GetServerTimeNow()
	for _, other in Players:GetPlayers() do
		if other:GetAttribute("Role") == Config.Roles.Survivor and (other:GetAttribute("HauntedUntil") or 0) > now and other.Character then
			table.insert(list, other.Character)
		end
	end
	for _, bot in CollectionService:GetTagged("SurvivorBot") do
		if (bot:GetAttribute("HauntedUntil") or 0) > now then table.insert(list, bot) end
	end
	return list
end

-- Revealed survivors (a false relic, a haunt...): for the monster side, a small ring of sight
-- round each (Config.REVEAL_VISION_RADIUS), so they and the ground round them light up
local function revealedSurvivors()
	local list = {}
	if sideOf(player:GetAttribute("Role")) ~= "monsters" then return list end
	local now = workspace:GetServerTimeNow()
	for _, other in Players:GetPlayers() do
		if other:GetAttribute("Role") == Config.Roles.Survivor and (other:GetAttribute("RevealedUntil") or 0) > now and other.Character then
			table.insert(list, other.Character)
		end
	end
	for _, bot in CollectionService:GetTagged("SurvivorBot") do
		if (bot:GetAttribute("RevealedUntil") or 0) > now then table.insert(list, bot) end
	end
	for i = #list, 1, -1 do                   -- not in a sanctuary
		local ok, pivot = pcall(list[i].GetPivot, list[i])
		if not ok or inSanctuary(pivot.Position) then table.remove(list, i) end
	end
	return list
end

-- CAPTURED SANCTUARIES: your team knows its own sanctuaries. The start sanctuary (captured from the start)
-- and every sanctuary your team captures are added to your map whole - floor and walls - rather than
-- only the parts someone happened to look at. Remembered, not in view: they show dim until seen.
local sanctuariesShown = {}  -- [sanctuary info Configuration] = the maze it was shown for

local function showCapturedSanctuaries()
	local status = game:GetService("ReplicatedStorage"):FindFirstChild("Match")
	local folder = status and status:FindFirstChild("Sanctuaries")
	if not folder or player:GetAttribute("Role") ~= Config.Roles.Survivor then return end
	local reach = maze:GetAttribute("CellSize") + 1.5   -- a 2x2-cell sanctuary around its centre, plus its walls
	for _, info in folder:GetChildren() do
		if info:GetAttribute("Captured") and sanctuariesShown[info] ~= maze then
			sanctuariesShown[info] = maze
			local c = info:GetAttribute("Center")
			local x1, x2 = tileRange(c.X - reach, c.X + reach)
			local z1, z2 = tileRange(c.Z - reach, c.Z + reach)
			for x = x1, x2 do
				for z = z1, z2 do
					local tile = tiles[x][z]
					if not tile.explored then
						reveal(tile)
						setTarget(tile, T_EXPLORED)
					end
				end
			end
		end
	end
	for info in sanctuariesShown do
		if not info.Parent then sanctuariesShown[info] = nil end   -- an old match's sanctuary
	end
end

-- THE MAZE MASTER knows the whole layout: every tile is on their map
local mapShownFor = nil
local function showWholeMap()
	if player:GetAttribute("Role") ~= Config.Roles.MazeMaster or mapShownFor == maze then return end
	mapShownFor = maze
	for x = 1, count do
		for z = 1, count do
			local tile = tiles[x][z]
			if not tile.explored then
				reveal(tile)
				setTarget(tile, T_EXPLORED)
			end
		end
	end
	table.clear(newlyRevealed)   -- nothing left to fringe or fill
end

local function updateVisibility()
	if not ready or not (maze and maze.Parent) then return end
	showCapturedSanctuaries()
	showWholeMap()
	-- Your own sight, every update (if you have a character: while respawning or out of lives you
	-- see only through your teammates)
	local eye, facing = eyesOf(player.Character)
	local merged = eye and sightFrom(eye, facing) or {}
	local eyes = { eye }

	-- Your teammates' sight, refreshed every TEAM_UPDATE_EVERY seconds
	local now = os.clock()
	local current = {}
	for _, mate in teammates() do
		current[mate] = true
		local mateEye, mateFacing = eyesOf(mate.Character)
		if mateEye then
			local cached = teamSight[mate]
			if not cached or cached.maze ~= maze or now - cached.at >= TEAM_UPDATE_EVERY then
				cached = { seen = sightFrom(mateEye, mateFacing), at = now, maze = maze }
				teamSight[mate] = cached
			end
			for tile, t in cached.seen do
				if not merged[tile] or t > merged[tile] then merged[tile] = t end   -- the clearest view wins
			end
			table.insert(eyes, mateEye)
		else
			teamSight[mate] = nil
		end
	end
	-- The AI monsters' sight (for the monster side), refreshed the same way
	for _, model in botMonsters() do
		current[model] = true
		local pivot = model:GetPivot()
		local botEye = Vector3.new(pivot.Position.X, floorY + EYE_HEIGHT, pivot.Position.Z)
		local look = pivot.LookVector * Vector3.new(1, 0, 1)
		local cached = teamSight[model]
		if not cached or cached.maze ~= maze or now - cached.at >= TEAM_UPDATE_EVERY then
			cached = { seen = sightFrom(botEye, look.Magnitude > 0.01 and look.Unit or Vector3.zAxis), at = now, maze = maze }
			teamSight[model] = cached
		end
		for tile, t in cached.seen do
			if not merged[tile] or t > merged[tile] then merged[tile] = t end
		end
		table.insert(eyes, botEye)
	end
	-- Haunted survivors' sight (for the monster side), refreshed the same way
	for _, character in hauntedSurvivors() do
		local hauntedEye, hauntedFacing = eyesOf(character)
		if hauntedEye then
			current[character] = true
			local cached = teamSight[character]
			if not cached or cached.maze ~= maze or now - cached.at >= TEAM_UPDATE_EVERY then
				cached = { seen = sightFrom(hauntedEye, hauntedFacing), at = now, maze = maze }
				teamSight[character] = cached
			end
			for tile, t in cached.seen do
				if not merged[tile] or t > merged[tile] then merged[tile] = t end
			end
		end
	end
	-- Rings round revealed survivors (for the monster side), refreshed the same way
	for _, character in revealedSurvivors() do
		local revealedEye = eyesOf(character)
		if revealedEye then
			local ringKey = "ring:" .. character:GetFullName()
			current[ringKey] = true
			local cached = teamSight[ringKey]
			if not cached or cached.maze ~= maze or now - cached.at >= TEAM_UPDATE_EVERY then
				cached = { seen = sightFrom(revealedEye, nil, Config.REVEAL_VISION_RADIUS), at = now, maze = maze }
				teamSight[ringKey] = cached
			end
			for tile, t in cached.seen do
				if not merged[tile] or t > merged[tile] then merged[tile] = t end
			end
		end
	end
	for mate in teamSight do
		if not current[mate] then teamSight[mate] = nil end   -- left the team / the game
	end
	for _, seen in monsterSideEyes() do
		for tile, t in seen do
			if not merged[tile] or t > merged[tile] then merged[tile] = t end
		end
	end
	for _, seen in relicRings() do
		for tile, t in seen do
			if not merged[tile] or t > merged[tile] then merged[tile] = t end
		end
	end

	-- Doors your team can see right now: remember how they are (the Maze Master always knows)
	local knowsDoors = player:GetAttribute("Role") == Config.Roles.MazeMaster
	for part, entry in FogState.doors do
		local seen = knowsDoors
		for _, tile in entry.tiles do
			if merged[tile] then seen = true break end
		end
		entry.seen = seen
		if seen and part.Parent then
			local _, shut = FogState.doorPose(part)
			if shut ~= entry.closed then rememberDoor(entry, shut) end
		end
	end

	local visibleNow = {}
	for tile, t in merged do
		visibleNow[tile] = true
		setTarget(tile, t)
	end

	-- Forgiveness: reveal small unseen pockets surrounded by seen tiles (next to anything just revealed)
	local pocketStarted = os.clock()
	fillPockets(visibleNow)
	stats.pocketTime += os.clock() - pocketStarted

	-- Soft edge around everything seen
	updateFringe(visibleNow)

	-- Unseen fog between the camera and the player becomes see-through (explored sheets never block the view)
	for d = 0, eye and 14 or -1, 2 do
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
	updateHiddenObjects(visibleNow, eyes)

	-- Anything that was visible/peeked last time but isn't now goes back to its resting state
	for tile in lastVisible do
		if not visibleNow[tile] then setTarget(tile, restingState(tile)) end
	end

	lastVisible = visibleNow
	FogState.visible = visibleNow
end

-- Rebuild the fog whenever the server builds a new maze
workspace.ChildAdded:Connect(function(child)
	if child.Name == "Maze" and child:IsA("Model") then
		task.wait() -- let attributes arrive
		buildFog(child)
	end
end)
task.spawn(buildFog, workspace:WaitForChild("Maze", math.huge))

-- Line-of-sight checks many times a second
task.spawn(function()
	while true do
		local started = os.clock()
		updateVisibility()
		stats.updateTime += os.clock() - started
		stats.updates += 1
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

-- STUDIO ONLY: cost figures for tuning, refreshed every 2 seconds as attributes on the local player
-- (FogRaysPerSec; FogSightMs / FogPocketMs / FogUpdateMs = average milliseconds per update), and a
-- FogTest BindableFunction comparing the fan with the old one-ray-per-tile way from where you stand.
if RunService:IsStudio() then
	task.spawn(function()
		while true do
			task.wait(2)
			local n = math.max(1, stats.updates)
			player:SetAttribute("FogRaysPerSec", math.floor(stats.rays / 2))
			player:SetAttribute("FogSightMs", math.floor(stats.sightTime / n * 1e4) / 10)
			player:SetAttribute("FogPocketMs", math.floor(stats.pocketTime / n * 1e4) / 10)
			player:SetAttribute("FogUpdateMs", math.floor(stats.updateTime / n * 1e4) / 10)
			stats.rays, stats.sightTime, stats.pocketTime, stats.updateTime, stats.updates = 0, 0, 0, 0, 0
		end
	end)
	local test = Instance.new("BindableFunction")
	test.Name = "FogTest"
	-- FogTest:Invoke(spacing?, mode?) - mode "set" makes `spacing` the live FAN_SPACING, or pass
	-- "tiles"/"fan" as spacing to switch SIGHT_MODE, or "pocket", n to set POCKET_MAX.
	-- Otherwise: compares the fan (at that spacing) with one ray per tile, from where you stand.
	test.OnInvoke = function(spacing, mode)
		if spacing == "tiles" or spacing == "fan" then SIGHT_MODE = spacing return SIGHT_MODE end
		if spacing == "pocket" then POCKET_MAX = mode return POCKET_MAX end
		if mode == "set" then FAN_SPACING = spacing return FAN_SPACING end
		local eye, facing = eyesOf(player.Character)
		if not eye then return "no character" end
		local saved = FAN_SPACING
		FAN_SPACING = spacing or FAN_SPACING
		local r0 = stats.rays
		local t0 = os.clock()
		local byTiles = sightTiles(eye, facing, VIEW_RANGE)
		local t1 = os.clock()
		local r1 = stats.rays
		local byFan = sightFan(eye, facing, VIEW_RANGE)
		local t2 = os.clock()
		local r2 = stats.rays
		FAN_SPACING = saved
		local both, onlyTiles, onlyFan = 0, 0, 0
		for tile in byTiles do if byFan[tile] then both += 1 else onlyTiles += 1 end end
		for tile in byFan do if not byTiles[tile] then onlyFan += 1 end end
		return { tilesRays = r1 - r0, tilesMs = (t1 - t0) * 1000, fanRays = r2 - r1, fanMs = (t2 - t1) * 1000,
			both = both, onlyTiles = onlyTiles, onlyFan = onlyFan }
	end
	test.Parent = script
end
