-- Generates and builds a random maze.
-- Algorithm: "recursive backtracker" (a depth-first search).
--   Start in a cell, knock down the wall to a random unvisited neighbour, move there,
--   repeat. When stuck, back up until a cell has unvisited neighbours.
--   This guarantees every cell is reachable and there's exactly one path between any two cells.

local MazeBuilder = {}

MazeBuilder.CELLS  = 15   -- maze is CELLS x CELLS
MazeBuilder.CELL   = 20   -- studs per cell (hallways are CELL - WALL_T wide)
MazeBuilder.WALL_H = 7    -- wall height (low enough for the isometric camera to see into corridors)
MazeBuilder.WALL_T = 2    -- wall thickness

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

	local stack = { {1, 1} }
	visited[1][1] = true
	while #stack > 0 do
		local x, z = stack[#stack][1], stack[#stack][2]
		local options = {}
		for _, d in DIRS do
			local nx, nz = x + d[1], z + d[2]
			if nx >= 1 and nx <= n and nz >= 1 and nz <= n and not visited[nx][nz] then
				table.insert(options, d)
			end
		end
		if #options == 0 then
			table.remove(stack) -- dead end: back up
		else
			local d = options[math.random(#options)]
			local nx, nz = x + d[1], z + d[2]
			walls[x][z][d[3]] = false
			walls[nx][nz][d[4]] = false
			visited[nx][nz] = true
			table.insert(stack, { nx, nz })
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

	local WALL_COLOR = Color3.fromRGB(95, 105, 125)
	local function wall(pos, size)
		block("Wall", size, pos + Vector3.new(0, H / 2, 0), WALL_COLOR, Enum.Material.Brick)
	end

	block("Floor", Vector3.new(n * S + T, 1, n * S + T), Vector3.new(0, y0 + 0.5, 0),
		Color3.fromRGB(200, 190, 160), Enum.Material.Sand)
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
	-- Always keep the whole maze loaded on every client, so line-of-sight
	-- raycasts never pass through walls that haven't streamed in yet
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	-- Remember the layout so other scripts (e.g. the monster) can navigate the maze
	MazeBuilder.current = { walls = walls, n = n, S = S, half = half, floorY = y0, model = model }

	model.Parent = workspace
	return model, start + Vector3.new(0, 4, 0), finish
end

return MazeBuilder
