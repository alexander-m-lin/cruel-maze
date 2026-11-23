-- Generates and builds a random maze, tuned to have lots of JUNCTIONS (places where you must choose).
--
-- Step 1, "growing tree": keep a list of cells to grow from. Each step, pick one, knock down the wall
--   to a random unvisited neighbour and add that neighbour to the list (or drop the cell if it has
--   none). Always picking the NEWEST cell gives long winding corridors with few branches; picking a
--   RANDOM one gives lots of short branches. Mixing the two gives plenty of junctions whose branches
--   still go somewhere.
-- Step 2, "braiding": most dead ends get one extra wall knocked down, joining them to a neighbour.
--   That turns a dead end into a junction and adds loops, so there's more than one way around - and
--   you can lose the monster by circling.
-- Every cell is still reachable from every other.
-- Step 3 (MazeLayout): carve sanctuaries, pick relic rooms and door slots. build() then makes the
--   parts: walls, floors, sanctuary floors, the barriers monsters can't cross (sanctuaries only), the
--   relics, and the doors (moved by the Doors module).

local MazeLayout = require(game:GetService("ServerStorage").MazeLayout)

local MazeBuilder = {}

MazeBuilder.CELLS  = 15   -- maze is CELLS x CELLS
MazeBuilder.CELL   = 20   -- studs per cell (hallways are CELL - WALL_T wide)
MazeBuilder.WALL_H = 7    -- wall height (low enough for the isometric camera to see into corridors)
MazeBuilder.WALL_T = 2    -- wall thickness

-- Wall look. Walls are built from panels exactly one cell (CELL studs) long, with posts where
-- walls turn, branch or end. Each panel picks one of WALL_VARIANTS at random; posts use the first.
-- The variants are AI-generated MaterialVariants stored in MaterialService (they live in the place
-- file), all made for WALL_MATERIAL. The JungleTempleStone3_V1..V4 variations share their
-- edges with JungleTempleStone3, so any two panels meet seamlessly in a straight run. That only
-- works because each panel is a whole number of texture tiles long (CELL = 20 studs, the
-- variants tile every 10 studs): Roblox starts a texture afresh on each part.
-- Other options: "JungleTempleStone" .. "JungleTempleStone2" (Cobblestone),
-- "AncientTombStone" .. "AncientTombStone3" (Sandstone). See Workspace.WallPalette in the place.
-- WALL_COLOR tints the texture; white shows it as generated.
MazeBuilder.WALL_MATERIAL = Enum.Material.Cobblestone
MazeBuilder.WALL_VARIANTS = { "JungleTempleStone3", "JungleTempleStone3_V1", "JungleTempleStone3_V2",
	"JungleTempleStone3_V3", "JungleTempleStone3_V4" }   -- images and script in assets/textures/JungleTempleStone3
MazeBuilder.POST_SIZE = 3      -- corner posts are this many studs square (walls are WALL_T thick)
MazeBuilder.WALL_COLOR    = Color3.fromRGB(104, 114, 88)

-- Floor look: muted temple flagstones (MaterialVariant in MaterialService.FloorVariations, made for
-- Slate, 15 studs per tile), tinted a weathered warm grey to sit with the walls. It's an
-- AI-generated floor toned down by tools/textures/soften.py so its tiling isn't obvious; images in
-- assets/textures/TempleFloor. The earlier, mossier "JungleTempleFloor".."3" are still in the
-- place (see Workspace.FloorPalette). FLOOR_VARIANT = "" = plain material.
MazeBuilder.FLOOR_MATERIAL = Enum.Material.Slate
MazeBuilder.FLOOR_VARIANT  = "TempleFloorSoft"
MazeBuilder.FLOOR_COLOR    = Color3.fromRGB(118, 110, 94)

-- Outside the walls: jungle ground
MazeBuilder.GROUND_MATERIAL = Enum.Material.LeafyGrass
MazeBuilder.GROUND_COLOR    = Color3.fromRGB(78, 96, 52)

-- How far the ground extends past the outer walls on every side. Along the near (bottom-of-screen)
-- walls the fog script shows some of it (RING_CLEAR + RING_FADE + RING_NOISE should fit within this).
MazeBuilder.BORDER = 20

-- Doors: slabs that rise out of the floor to close a passage and sink back into it to open it.
-- DOOR_LOOK picks how they look:
--   "subtle" - the slab is a wall like any other (same texture and colour); the only tell is its
--              two posts, a little darker than the walls
--   "dev"    - plainly different (rusty metal slab, dark posts), to see every door at a glance
-- variant = nil: a random one of WALL_VARIANTS, like a wall panel.
MazeBuilder.DOOR_LOOK = "subtle"
MazeBuilder.DOOR_LOOKS = {
	subtle = { material = MazeBuilder.WALL_MATERIAL, variant = nil, color = MazeBuilder.WALL_COLOR,
	           post = Color3.fromRGB(78, 74, 62) },
	dev    = { material = Enum.Material.CorrodedMetal, variant = "", color = Color3.fromRGB(150, 82, 52),
	           post = Color3.fromRGB(70, 60, 54) },
}

MazeBuilder.NEWEST = 0.5  -- step 1: chance to grow from the newest cell (1 = long corridors, 0 = bushy)
MazeBuilder.BRAID  = 0.75 -- step 2: fraction of dead ends opened up into loops (0 = none, 1 = no dead ends)

-- Returns walls[x][z] = {N=bool, E=bool, S=bool, W=bool}
function MazeBuilder.generate(n)
	local walls, visited = {}, {}
	for x = 1, n do
		walls[x], visited[x] = {}, {}
		for z = 1, n do
			walls[x][z] = { N = true, E = true, S = true, W = true }
		end
	end

	-- {dx, dz, wallOnThisCell, wallOnNeighbour}
	local DIRS = { {0,-1,"N","S"}, {1,0,"E","W"}, {0,1,"S","N"}, {-1,0,"W","E"} }

	local function inside(x, z) return x >= 1 and x <= n and z >= 1 and z <= n end
	local function knock(x, z, d)
		walls[x][z][d[3]] = false
		walls[x + d[1]][z + d[2]][d[4]] = false
	end
	local function openSides(x, z)
		local w = walls[x][z]
		return (w.N and 0 or 1) + (w.E and 0 or 1) + (w.S and 0 or 1) + (w.W and 0 or 1)
	end

	-- Step 1: growing tree
	local active = { {1, 1} }
	visited[1][1] = true
	while #active > 0 do
		local i = math.random() < MazeBuilder.NEWEST and #active or math.random(#active)
		local x, z = active[i][1], active[i][2]
		local options = {}
		for _, d in DIRS do
			local nx, nz = x + d[1], z + d[2]
			if inside(nx, nz) and not visited[nx][nz] then
				table.insert(options, d)
			end
		end
		if #options == 0 then
			table.remove(active, i) -- nothing left to grow into from here
		else
			local d = options[math.random(#options)]
			knock(x, z, d)
			visited[x + d[1]][z + d[2]] = true
			table.insert(active, { x + d[1], z + d[2] })
		end
	end

	-- Step 2: braiding. Visit cells in a random order; open up dead ends. Joining two dead ends
	-- together fixes both at once, so prefer that.
	local cells = {}
	for x = 1, n do
		for z = 1, n do table.insert(cells, { x, z }) end
	end
	for i = #cells, 2, -1 do
		local j = math.random(i)
		cells[i], cells[j] = cells[j], cells[i]
	end
	for _, c in cells do
		local x, z = c[1], c[2]
		if openSides(x, z) == 1 and math.random() < MazeBuilder.BRAID then
			local best, any = {}, {}
			for _, d in DIRS do
				local nx, nz = x + d[1], z + d[2]
				if inside(nx, nz) and walls[x][z][d[3]] then
					table.insert(any, d)
					if openSides(nx, nz) == 1 then table.insert(best, d) end
				end
			end
			local pick = #best > 0 and best or any
			if #pick > 0 then knock(x, z, pick[math.random(#pick)]) end
		end
	end
	return walls
end

-- Looks of the special places
local SANCTUARY_FLOOR_COLOR     = Color3.fromRGB(96, 104, 110)    -- a sanctuary nobody has found yet
MazeBuilder.SANCTUARY_CAPTURED_COLOR = Color3.fromRGB(70, 150, 160)  -- a sanctuary your team has captured
local SANCTUARY_WARD_COLOR      = Color3.fromRGB(90, 220, 235)    -- barrier across sanctuary exits
local RELIC_COLOR          = Color3.fromRGB(255, 200, 80)

-- The relic itself: a skull (the model ServerStorage.SkullRelic, Creator Store asset 98498294) sitting
-- on its pedestal, facing the camera, with red light glowing deep in its eye sockets. It's named
-- "Gem" because the rest of the game looks for that (the beam, the prompt, the sounds...).
-- Returns nil if the skull model is missing (then the relic is a glowing cube instead).
local SKULL_SCALE = 2         -- how big the skull is (1 = the model as made)
local EYE_COLOR = Color3.fromRGB(255, 30, 20)
local function makeRelicSkull(pedestalTop, parent)
	local template = game:GetService("ServerStorage"):FindFirstChild("SkullRelic")
	local head = template and template:FindFirstChildWhichIsA("BasePart")
	if not head then return nil end
	local skull = head:Clone()
	skull.Name = "Gem"
	local mesh = skull:FindFirstChildWhichIsA("SpecialMesh")
	if mesh then mesh.Scale *= SKULL_SCALE end
	skull.Size *= SKULL_SCALE
	skull.Anchored = true
	skull.CanCollide, skull.CanQuery, skull.CanTouch = false, false, false
	skull.CastShadow = false
	-- resting on the pedestal, turned toward the camera (the skull's face is its front, -Z)
	local at = pedestalTop + Vector3.new(0, 0.55 * SKULL_SCALE, 0)
	skull.CFrame = CFrame.lookAt(at, at - Vector3.new(1, 0, 1))
	-- the glow: a glowing ball filling each eye socket (centred in it, set back a little so the
	-- socket's rim frames it), and a faint red light in front
	for _, x in { -0.243, 0.243 } do
		local eye = Instance.new("Part")
		eye.Name = "Eye"
		eye.Shape = Enum.PartType.Ball
		eye.Size = Vector3.one * 0.3 * SKULL_SCALE
		eye.Material = Enum.Material.Neon
		eye.Color = EYE_COLOR
		eye.Anchored = true
		eye.CanCollide, eye.CanQuery, eye.CanTouch = false, false, false
		eye.CastShadow = false
		eye.CFrame = skull.CFrame * CFrame.new(x * SKULL_SCALE, 0.11 * SKULL_SCALE, -0.34 * SKULL_SCALE)
		eye.Parent = skull
	end
	local glowAt = Instance.new("Attachment")
	glowAt.Position = Vector3.new(0, 0.12 * SKULL_SCALE, -0.7 * SKULL_SCALE)
	glowAt.Parent = skull
	local red = Instance.new("PointLight")
	red.Color, red.Range, red.Brightness = EYE_COLOR, 4, 3
	red.Parent = glowAt
	skull.Parent = parent
	return skull
end

-- A relic on its pedestal at `center` (a cell centre on the floor), with a progress bar above it
-- that fills while it's being collected. Also used for false relics (Objectives), which must look
-- exactly the same. Returns the relic's model ("Relic<id>") and its gem (the skull).
function MazeBuilder.buildRelic(parent, center, id)
	local function decor(name, size, cf, color, material, into)
		local p = Instance.new("Part")
		p.Name, p.Size, p.CFrame = name, size, cf
		p.Anchored = true
		p.CanCollide, p.CanTouch, p.CanQuery = false, false, false
		p.CastShadow = false
		p.Color, p.Material = color, material
		p.Parent = into
		return p
	end
	local relicModel = Instance.new("Model")
	relicModel.Name = "Relic" .. id
	relicModel.Parent = parent
	decor("Pedestal", Vector3.new(3, 2, 3), CFrame.new(center + Vector3.new(0, 1, 0)),
		Color3.fromRGB(120, 112, 96), Enum.Material.Slate, relicModel)
	local gem = makeRelicSkull(center + Vector3.new(0, 2, 0), relicModel)
		or decor("Gem", Vector3.new(1.6, 1.6, 1.6),
			CFrame.new(center + Vector3.new(0, 3.4, 0)) * CFrame.Angles(math.rad(45), 0, math.rad(45)),
			RELIC_COLOR, Enum.Material.Neon, relicModel)
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness = RELIC_COLOR, 16, 2.5   -- the golden glow around it
	light.Parent = gem
	MazeBuilder.buildProgressBar(relicModel, gem, RELIC_COLOR, 6)
	return relicModel, gem
end

-- A progress bar floating `height` studs above `adornee`, named "Progress" in `parent`: hidden
-- until someone collects a relic (or destroys a ward), then shown and filled by players'
-- computers (HUD)
function MazeBuilder.buildProgressBar(parent, adornee, color, height)
	local bar = Instance.new("BillboardGui")
	bar.Name = "Progress"
	bar.Size = UDim2.fromOffset(70, 10)
	bar.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	bar.Enabled = false
	bar.Adornee = adornee
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	back.BorderSizePixel = 0
	back.Parent = bar
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = back
	bar.Parent = parent
	return bar
end

-- Builds the maze in the workspace (replacing any previous one).
-- Returns a maze table (see the end): the layout, plus its sanctuaries and relics.
-- options.layout: a fixed layout instead of a generated one (the dev Sandbox):
--   { n, walls, sanctuaries, relics, doors, crushers } in the forms MazeLayout's planners return
function MazeBuilder.build(options)
	options = options or {}
	local layout = options.layout
	local n, S, H, T = layout and layout.n or MazeBuilder.CELLS, MazeBuilder.CELL, MazeBuilder.WALL_H, MazeBuilder.WALL_T
	local base = workspace.Baseplate
	local y0 = base.Position.Y + base.Size.Y / 2   -- top of the baseplate
	local half = n * S / 2

	local function cellCenter(x, z)
		return Vector3.new((x - 0.5) * S - half, y0, (z - 0.5) * S - half)
	end

	local old = workspace:FindFirstChild("Maze")
	if old then old:Destroy() end

	local model = Instance.new("Model")
	model.Name = "Maze"

	local function block(name, size, pos, color, material)
		local p = Instance.new("Part")
		p.Name, p.Size, p.Position = name, size, pos
		p.Anchored = true
		p.Color = color
		p.Material = material
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end

	local variants = MazeBuilder.WALL_VARIANTS
	local function wall(pos, size, variant)
		local p = block("Wall", size, pos + Vector3.new(0, H / 2, 0), MazeBuilder.WALL_COLOR, MazeBuilder.WALL_MATERIAL)
		p.MaterialVariant = variant or variants[math.random(#variants)]
		return p
	end

	-- Paved floor inside the walls; jungle ground outside them. The ground is one big slab reaching
	-- BORDER studs past the walls, sitting a hair lower than the pavers so they cover it inside
	-- (exactly level surfaces would flicker where they overlap).
	local floorSize = n * S + T
	local floor = block("Floor", Vector3.new(floorSize, 1, floorSize), Vector3.new(0, y0 + 0.5, 0),
		MazeBuilder.FLOOR_COLOR, MazeBuilder.FLOOR_MATERIAL)
	floor.MaterialVariant = MazeBuilder.FLOOR_VARIANT
	local groundSize = floorSize + 2 * MazeBuilder.BORDER
	block("Ground", Vector3.new(groundSize, 1, groundSize), Vector3.new(0, y0 + 0.5 - 0.05, 0),
		MazeBuilder.GROUND_COLOR, MazeBuilder.GROUND_MATERIAL)
	y0 += 1 -- everything else sits on the maze floor

	-- The layout: a fixed one (the Sandbox), or maze, then sanctuaries, then relic rooms (see MazeLayout)
	local walls, sanctuaryPlans, relicPlans, doorPlans, crusherPlans
	if layout then
		walls, sanctuaryPlans, relicPlans = layout.walls, layout.sanctuaries, layout.relics
		doorPlans, crusherPlans = layout.doors or {}, layout.crushers or {}
	else
		-- (a few tries for a maze whose start sanctuary gets 3 well-spread exits: not every maze has room)
		for _ = 1, 10 do
			walls = MazeBuilder.generate(n)
			sanctuaryPlans = MazeLayout.carveSanctuaries(walls, n, options.sanctuaries or 4, options.sanctuarySpacing or 5, {
				startSize = options.startSanctuarySize, size = options.sanctuarySize, exitSpacing = options.sanctuaryExitSpacing })
			if #sanctuaryPlans[1].exits >= 3 then break end
		end
		local blocked = {}      -- cells monsters can't enter
		for _, sanctuary in sanctuaryPlans do
			for k in sanctuary.cells do blocked[k] = true end
		end
		MazeLayout.connect(walls, n, blocked)
		relicPlans = MazeLayout.pickRelics(walls, n, sanctuaryPlans,
			options.relics or 9, options.relicSpacing or 4, options.relicsNearStart)
		doorPlans = MazeLayout.placeDoors(walls, n, sanctuaryPlans, relicPlans, {
			corridors = options.doorCorridors or 0, shortcuts = options.doorShortcuts or 0,
			spacing = options.doorSpacing or 3, minDetour = options.doorMinDetour or 6,
			exitSpacing = options.sanctuaryExitSpacing,
		})
		crusherPlans = MazeLayout.placeCrushers(walls, n, sanctuaryPlans, relicPlans, doorPlans,
			options.crushers or 0, options.crusherSpacing or 3)
	end
	-- isDoor[x][z].E / .S: that side of the cell is a door slot (doors are always on an E or S side)
	local isDoor = {}
	for x = 1, n do isDoor[x] = {} for z = 1, n do isDoor[x][z] = {} end end
	for _, door in doorPlans do isDoor[door.x][door.z][door.d[3]] = true end

	-- WALLS. Grid points (i, j) are the cell corners, 0..n each way. A wall panel runs along one
	-- cell side, corner to corner. Each cell builds its North and West sides; the last row/column
	-- also build South/East, so no side is built twice. sides[i][j] records which directions
	-- leave each corner, to decide where posts go.
	local sides = {}
	for i = 0, n do
		sides[i] = {}
		for j = 0, n do sides[i][j] = {} end
	end
	local function corner(i, j)
		return Vector3.new(i * S - half, y0, j * S - half)
	end
	local panelsX, panelsZ = {}, {}   -- [i * 1000 + j] = the wall panel starting at corner (i, j)
	local function panelX(i, j)   -- from corner (i, j) to (i + 1, j)
		panelsX[i * 1000 + j] = wall((corner(i, j) + corner(i + 1, j)) / 2, Vector3.new(S, H, T))
		sides[i][j].E, sides[i + 1][j].W = true, true
	end
	local function panelZ(i, j)   -- from corner (i, j) to (i, j + 1)
		panelsZ[i * 1000 + j] = wall((corner(i, j) + corner(i, j + 1)) / 2, Vector3.new(T, H, S))
		sides[i][j].S, sides[i][j + 1].N = true, true
	end
	for x = 1, n do
		for z = 1, n do
			local w = walls[x][z]
			-- (no panel where there's a door: N of this cell is S of the one above, W is E of the one left)
			if w.N and not (z > 1 and isDoor[x][z - 1].S) then panelX(x - 1, z - 1) end
			if w.W and not (x > 1 and isDoor[x - 1][z].E) then panelZ(x - 1, z - 1) end
			if z == n and w.S then panelX(x - 1, z) end
			if x == n and w.E then panelZ(x, z - 1) end
		end
	end
	-- Both ends of every door get a post (its door frame), even in a straight run of wall
	local doorEnds = {}
	for _, door in doorPlans do
		local i, j = door.x, door.z                    -- the cell's far corner
		local a = door.d[3] == "E" and { i, j - 1 } or { i - 1, j }
		doorEnds[a[1] * 1000 + a[2]] = true
		doorEnds[i * 1000 + j] = true
	end
	-- A post at every corner where walls meet, except where two panels just continue in a
	-- straight line (there the panels join seamlessly on their own)
	local P = MazeBuilder.POST_SIZE
	for i = 0, n do
		for j = 0, n do
			local d = sides[i][j]
			local count = (d.N and 1 or 0) + (d.S and 1 or 0) + (d.E and 1 or 0) + (d.W and 1 or 0)
			local straight = count == 2 and ((d.N and d.S) or (d.E and d.W))
			if doorEnds[i * 1000 + j] then
				local look = MazeBuilder.DOOR_LOOKS[MazeBuilder.DOOR_LOOK]
				local post = wall(corner(i, j), Vector3.new(P, H + 0.4, P), variants[1])
				post:SetAttribute("DoorPost", true)   -- otherwise a wall like any other
				post.Color = look.post
				post.Position += Vector3.new(0, 0.2, 0)
			elseif count > 0 and not straight then
				wall(corner(i, j), Vector3.new(P, H, P), variants[1])
			end
		end
	end

	-- Decorations that are only for show: nothing collides with them, and raycasts (line of sight,
	-- the monster's checks) pass straight through
	local function decor(name, size, cf, color, material, parent)
		local p = Instance.new("Part")
		p.Name, p.Size, p.CFrame = name, size, cf
		p.Anchored = true
		p.CanCollide, p.CanTouch, p.CanQuery = false, false, false
		p.CastShadow = false
		p.Color, p.Material = color, material
		p.Parent = parent or model
		return p
	end

	-- A shimmering barrier panel across the opening on side `d` of cell (x, z): monsters can't pass
	local function ward(x, z, d, color, parent)
		local c = cellCenter(x, z) + Vector3.new(d[1], 0, d[2]) * (S / 2) + Vector3.new(0, H / 2, 0)
		local size = d[1] == 0 and Vector3.new(S - T, H, 0.3) or Vector3.new(0.3, H, S - T)
		local p = decor("Ward", size, CFrame.new(c), color, Enum.Material.ForceField, parent)
		p.Transparency = 0.15
		return p
	end

	-- SANCTUARIES: a tinted floor, and a barrier across each exit
	local sanctuaries = {}
	for _, plan in sanctuaryPlans do
		-- the middle of the block of cells
		local center = Vector3.new((plan.x - 1 + plan.size / 2) * S - half, y0, (plan.z - 1 + plan.size / 2) * S - half)
		local folder = Instance.new("Model")
		folder.Name = "Sanctuary" .. plan.id
		folder.Parent = model
		local floor = decor("SanctuaryFloor", Vector3.new(plan.size * S - T, 0.1, plan.size * S - T), CFrame.new(center + Vector3.new(0, 0.05, 0)),
			SANCTUARY_FLOOR_COLOR, Enum.Material.Slate, folder)
		floor.MaterialVariant = MazeBuilder.FLOOR_VARIANT   -- same flagstones, tinted (needs a Slate-based variant)
		local wards = {}
		for _, e in plan.exits do
			table.insert(wards, ward(e[1], e[2], e[3], SANCTUARY_WARD_COLOR, folder))
		end
		table.insert(sanctuaries, { id = plan.id, x = plan.x, z = plan.z, size = plan.size, cells = plan.cells, center = center,
			floor = floor, wards = wards, exits = plan.exits })
	end

	-- RELICS: a relic on a pedestal (see MazeBuilder.buildRelic)
	local relics = {}
	for i, plan in relicPlans do
		local x, z = plan[1], plan[2]
		local center = cellCenter(x, z)
		local relicModel, gem = MazeBuilder.buildRelic(model, center, i)
		table.insert(relics, { id = i, x = x, z = z, center = center, model = relicModel, gem = gem })
	end

	-- DOORS: a slab between the two door posts. Closed, it stands like a wall; open, it has sunk
	-- just under the floor (out of sight and out of the way of rays and bodies).
	local look = MazeBuilder.DOOR_LOOKS[MazeBuilder.DOOR_LOOK]
	local doors = {}
	for id, plan in doorPlans do
		local i, j = plan.x, plan.z
		local horizontal = plan.d[3] == "S"           -- runs along X (between cells above and below)
		local a = horizontal and corner(i - 1, j) or corner(i, j - 1)
		local mid = (a + corner(i, j)) / 2
		local length = S - P + 0.6                     -- reaches a little into each post
		local size = horizontal and Vector3.new(length, H, T) or Vector3.new(T, H, length)
		local closedCF = CFrame.new(mid + Vector3.new(0, H / 2, 0))
		local openCF = CFrame.new(mid - Vector3.new(0, H / 2 + 0.1, 0))
		local p = block("Door", size, (plan.open and openCF or closedCF).Position, look.color, look.material)
		p.MaterialVariant = look.variant or variants[math.random(#variants)]
		p.CanCollide = not plan.open
		p:SetAttribute("Id", id)
		p:SetAttribute("Kind", plan.kind)
		p:SetAttribute("Open", plan.open)
		p:SetAttribute("ClosedCFrame", closedCF)
		p:SetAttribute("OpenCFrame", openCF)
		table.insert(doors, { id = id, x = i, z = j, d = plan.d, kind = plan.kind, open = plan.open,
			part = p, closedCF = closedCF, openCF = openCF,
			other = { i + plan.d[1], j + plan.d[2] } })  -- the cell on the far side
	end

	-- CRUSHING WALLS: inside each side wall of a crusher cell hides a slab of the same stone, a bit
	-- thinner, shorter and lower than the wall so no face of it shows. Set off (see Crushers), the
	-- two slabs slide out of the walls and meet in the middle of the cell; the walls themselves never
	-- move, so the maze never opens up. The wall panels are tagged with the crusher's id, so players'
	-- computers can shake them while it rumbles.
	local crushers = {}
	for id, plan in crusherPlans do
		local x, z = plan.x, plan.z
		local c = cellCenter(x, z) + Vector3.new(0, 0, 0)
		local alongX = plan.along == "X"
		-- the two side walls: N and S for a corridor running along X, W and E for one along Z
		local panelA = alongX and panelsX[(x - 1) * 1000 + (z - 1)] or panelsZ[(x - 1) * 1000 + (z - 1)]
		local panelB = alongX and panelsX[(x - 1) * 1000 + z] or panelsZ[x * 1000 + (z - 1)]
		local inward = alongX and Vector3.new(0, 0, 1) or Vector3.new(1, 0, 0)   -- from side A into the cell
		local slabT = T - 0.4
		local slabSize = alongX and Vector3.new(S - 0.4, H - 0.3, slabT) or Vector3.new(slabT, H - 0.3, S - 0.4)
		local mid = c + Vector3.new(0, (H - 0.3) / 2, 0)
		local homeA = CFrame.new(mid - inward * (S / 2))
		local homeB = CFrame.new(mid + inward * (S / 2))
		local shutA = CFrame.new(mid - inward * (slabT / 2))
		local shutB = CFrame.new(mid + inward * (slabT / 2))
		local slabs = {}
		for k, home in { homeA, homeB } do
			local slab = block("Crusher", slabSize, home.Position, MazeBuilder.WALL_COLOR, MazeBuilder.WALL_MATERIAL)
			slab.MaterialVariant = variants[math.random(#variants)]
			slab:SetAttribute("Id", id)
			slab:SetAttribute("Home", home)
			slab:SetAttribute("Shut", k == 1 and shutA or shutB)
			slabs[k] = slab
		end
		for _, panel in { panelA, panelB } do
			if panel then panel:SetAttribute("CrusherId", id) end
		end
		table.insert(crushers, { id = id, x = x, z = z, along = plan.along, center = c, slabs = slabs,
			homes = { homeA, homeB }, shuts = { shutA, shutB }, inward = inward })
	end

	-- Move the spawn pad into the start sanctuary (players are moved to their own spots from there)
	local start = sanctuaries[1].center
	local spawn = workspace:FindFirstChild("SpawnLocation")
	if spawn then
		spawn.Size = Vector3.new(6, 1, 6)
		spawn.Position = start + Vector3.new(0, 0.5, 0)
		spawn.Duration = 0
		spawn.Transparency = 1                -- invisible: the sanctuary floor marks the start
		spawn.CanCollide = false
		for _, d in spawn:GetChildren() do    -- including its star emblem
			if d:IsA("Decal") then d.Transparency = 1 end
		end
	end

	-- Info the client needs for fog of war (it can't see this ModuleScript)
	model:SetAttribute("Cells", n)
	model:SetAttribute("CellSize", S)
	model:SetAttribute("WallHeight", H)
	model:SetAttribute("FloorY", y0)
	model:SetAttribute("Border", MazeBuilder.BORDER)
	-- Always keep the whole maze loaded on every client, so line-of-sight
	-- raycasts never pass through walls that haven't streamed in yet
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	model.Parent = workspace
	return {
		model = model,
		walls = walls,                          -- the layout, for anything that navigates the maze
		n = n, S = S, half = half, floorY = y0,
		start = start + Vector3.new(0, 4, 0),   -- the start sanctuary's centre (raised to standing height)
		sanctuaries = sanctuaries,                          -- sanctuaries: { id, x, z, cells, center, floor, wards }
		relics = relics,                        -- relics: { id, x, z, center, model, gem (the skull) }
		doors = doors,                          -- doors: { id, x, z, d, other, kind, open, part, closedCF, openCF }
		crushers = crushers,                    -- crushing walls: { id, x, z, along, center, slabs, homes, shuts, inward }
	}
end

return MazeBuilder
