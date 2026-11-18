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
-- Step 3 (MazeLayout): carve spawn rooms and pick relic rooms. build() then makes the parts:
--   walls, floors, room floors, the barriers monsters can't cross, and the relics.

local MazeLayout = require(game:GetService("ServerStorage").MazeLayout)

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

-- Looks of the special places
local ROOM_FLOOR_COLOR     = Color3.fromRGB(96, 104, 110)    -- a spawn room nobody has found yet
MazeBuilder.ROOM_CAPTURED_COLOR = Color3.fromRGB(70, 150, 160)  -- a spawn room your team has captured
local ROOM_WARD_COLOR      = Color3.fromRGB(90, 220, 235)    -- barrier across spawn room exits
local RELIC_WARD_COLOR     = Color3.fromRGB(255, 196, 70)    -- barrier across relic room openings
local RELIC_COLOR          = Color3.fromRGB(255, 200, 80)

-- Builds the maze in the workspace (replacing any previous one).
-- Returns a maze table (see the end): the layout, plus its spawn rooms and relics.
function MazeBuilder.build(options)
	options = options or {}
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

	-- The layout: maze, then spawn rooms, then relic rooms (see MazeLayout)
	local walls = MazeBuilder.generate(n)
	local roomPlans = MazeLayout.carveRooms(walls, n, options.spawnRooms or 4, options.roomSpacing or 5)
	local blocked = {}      -- cells monsters can't enter
	for _, room in roomPlans do
		for k in room.cells do blocked[k] = true end
	end
	MazeLayout.connect(walls, n, blocked)
	local relicPlans = MazeLayout.pickRelics(walls, n, roomPlans, blocked,
		options.relics or 9, options.relicSpacing or 4)

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

	-- SPAWN ROOMS: a tinted floor, and a barrier across each exit
	local rooms = {}
	for _, plan in roomPlans do
		-- centre of the 2x2 block = the corner shared by its four cells
		local center = Vector3.new(plan.x * S - half, y0, plan.z * S - half)
		local folder = Instance.new("Model")
		folder.Name = "SpawnRoom" .. plan.id
		folder.Parent = model
		local floor = decor("RoomFloor", Vector3.new(2 * S - T, 0.1, 2 * S - T), CFrame.new(center + Vector3.new(0, 0.05, 0)),
			ROOM_FLOOR_COLOR, Enum.Material.Slate, folder)
		local wards = {}
		for _, e in plan.exits do
			table.insert(wards, ward(e[1], e[2], e[3], ROOM_WARD_COLOR, folder))
		end
		table.insert(rooms, { id = plan.id, x = plan.x, z = plan.z, cells = plan.cells, center = center,
			floor = floor, wards = wards })
	end

	-- RELIC ROOMS: a relic on a pedestal, and a barrier across each opening
	local relics = {}
	for i, plan in relicPlans do
		local x, z = plan[1], plan[2]
		local center = cellCenter(x, z)
		local relicModel = Instance.new("Model")
		relicModel.Name = "Relic" .. i
		relicModel.Parent = model
		decor("Pedestal", Vector3.new(3, 2, 3), CFrame.new(center + Vector3.new(0, 1, 0)),
			Color3.fromRGB(120, 112, 96), Enum.Material.Slate, relicModel)
		local gem = decor("Gem", Vector3.new(1.6, 1.6, 1.6),
			CFrame.new(center + Vector3.new(0, 3.4, 0)) * CFrame.Angles(math.rad(45), 0, math.rad(45)),
			RELIC_COLOR, Enum.Material.Neon, relicModel)
		local light = Instance.new("PointLight")
		light.Color, light.Range, light.Brightness = RELIC_COLOR, 14, 1.5
		light.Parent = gem
		local wards = {}
		for _, d in MazeLayout.DIRS do
			if not walls[x][z][d[3]] then table.insert(wards, ward(x, z, d, RELIC_WARD_COLOR, relicModel)) end
		end
		table.insert(relics, { id = i, x = x, z = z, center = center, model = relicModel, gem = gem, wards = wards })
	end

	-- Move the spawn pad into the start room (players are moved to their own spots from there)
	local start = rooms[1].center
	local spawn = workspace:FindFirstChild("SpawnLocation")
	if spawn then
		spawn.Size = Vector3.new(6, 1, 6)
		spawn.Position = start + Vector3.new(0, 0.5, 0)
		spawn.Duration = 0
		spawn.Transparency = 1                -- invisible: the room floor marks the start
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
		start = start + Vector3.new(0, 4, 0),   -- the start room's centre (raised to standing height)
		rooms = rooms,                          -- spawn rooms: { id, x, z, cells, center, floor, wards }
		relics = relics,                        -- relics: { id, x, z, center, model, gem, wards }
	}
end

return MazeBuilder
