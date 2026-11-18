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

local MazeBuilder = {}

MazeBuilder.CELLS  = 15   -- maze is CELLS x CELLS
MazeBuilder.CELL   = 20   -- studs per cell (hallways are CELL - WALL_T wide)
MazeBuilder.WALL_H = 7    -- wall height (low enough for the isometric camera to see into corridors)
MazeBuilder.WALL_T = 2    -- wall thickness

-- Wall look. WALL_VARIANT names an AI-generated MaterialVariant stored in MaterialService (it lives
-- in the place file); WALL_MATERIAL must be the base material it was made for. Options generated:
--   "JungleTempleStone" .. "JungleTempleStone3"  (base Cobblestone) - mossy grey-green temple blocks
--   "AncientTombStone"  .. "AncientTombStone3"   (base Sandstone)   - weathered tomb sandstone
-- WALL_COLOR tints the texture; white shows it as generated.
-- NOTE (2026-11-18): the generated textures' images were still awaiting Roblox moderation (they
-- load as blank), so for now the walls use Roblox's built-in Cobblestone with a mossy tint
-- (WALL_VARIANT = "" means no variant). Once the images load, set WALL_VARIANT to one of the
-- names above and WALL_COLOR back to white.
MazeBuilder.WALL_MATERIAL = Enum.Material.Cobblestone
MazeBuilder.WALL_VARIANT  = ""
MazeBuilder.WALL_COLOR    = Color3.fromRGB(104, 114, 88)

-- Floor look: Roblox's built-in Pavement (stone pavers) in a weathered warm grey
MazeBuilder.FLOOR_MATERIAL = Enum.Material.Pavement
MazeBuilder.FLOOR_COLOR    = Color3.fromRGB(118, 110, 94)

-- Outside the walls: jungle ground
MazeBuilder.GROUND_MATERIAL = Enum.Material.LeafyGrass
MazeBuilder.GROUND_COLOR    = Color3.fromRGB(78, 96, 52)

-- How far the ground extends past the outer walls on every side. Along the near (bottom-of-screen)
-- walls the fog script shows some of it (RING_CLEAR + RING_FADE + RING_NOISE should fit within this).
MazeBuilder.BORDER = 20

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

-- Builds the maze in the workspace.
-- Returns: mazeModel, startPosition, finishPart
function MazeBuilder.build()
	local n, S, H, T = MazeBuilder.CELLS, MazeBuilder.CELL, MazeBuilder.WALL_H, MazeBuilder.WALL_T
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

	local function wall(pos, size)
		local p = block("Wall", size, pos + Vector3.new(0, H / 2, 0), MazeBuilder.WALL_COLOR, MazeBuilder.WALL_MATERIAL)
		p.MaterialVariant = MazeBuilder.WALL_VARIANT
	end

	-- Paved floor inside the walls; jungle ground outside them. The ground is one big slab reaching
	-- BORDER studs past the walls, sitting a hair lower than the pavers so they cover it inside
	-- (exactly level surfaces would flicker where they overlap).
	local floorSize = n * S + T
	block("Floor", Vector3.new(floorSize, 1, floorSize), Vector3.new(0, y0 + 0.5, 0),
		MazeBuilder.FLOOR_COLOR, MazeBuilder.FLOOR_MATERIAL)
	local groundSize = floorSize + 2 * MazeBuilder.BORDER
	block("Ground", Vector3.new(groundSize, 1, groundSize), Vector3.new(0, y0 + 0.5 - 0.05, 0),
		MazeBuilder.GROUND_COLOR, MazeBuilder.GROUND_MATERIAL)
	y0 += 1 -- everything else sits on the maze floor

	local walls = MazeBuilder.generate(n)
	for x = 1, n do
		for z = 1, n do
			local c = cellCenter(x, z)
			local w = walls[x][z]
			-- Each cell builds its North and West walls; the last row/column also build South/East.
			-- That way no wall is built twice.
			if w.N then wall(c + Vector3.new(0, 0, -S/2), Vector3.new(S + T, H, T)) end
			if w.W then wall(c + Vector3.new(-S/2, 0, 0), Vector3.new(T, H, S + T)) end
			if z == n and w.S then wall(c + Vector3.new(0, 0, S/2), Vector3.new(S + T, H, T)) end
			if x == n and w.E then wall(c + Vector3.new(S/2, 0, 0), Vector3.new(T, H, S + T)) end
		end
	end

	-- Finish pad in the far corner, with a tall glowing beam so you can aim for it
	local fc = cellCenter(n, n)
	local finish = block("Finish", Vector3.new(S - T - 1, 0.4, S - T - 1), fc + Vector3.new(0, 0.2, 0),
		Color3.fromRGB(60, 255, 120), Enum.Material.Neon)
	local beam = block("Beacon", Vector3.new(2, 120, 2), fc + Vector3.new(0, 60, 0),
		Color3.fromRGB(60, 255, 120), Enum.Material.Neon)
	beam.Transparency = 0.5
	beam.CanCollide, beam.CanTouch, beam.CanQuery = false, false, false

	-- Move the spawn into the start corner
	local start = cellCenter(1, 1)
	local spawn = workspace:FindFirstChild("SpawnLocation")
	if spawn then
		spawn.Size = Vector3.new(6, 1, 6)
		spawn.Position = start + Vector3.new(0, 0.5, 0)
		spawn.Duration = 0
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

	-- Remember the layout so other scripts (e.g. the monster) can navigate the maze
	MazeBuilder.current = { walls = walls, n = n, S = S, half = half, floorY = y0, model = model }

	model.Parent = workspace
	return model, start + Vector3.new(0, 4, 0), finish
end

return MazeBuilder
