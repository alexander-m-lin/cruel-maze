-- Plans the special places in a maze: SPAWN ROOMS and RELIC ROOMS. Works only on the layout table
-- (walls[x][z] = {N, E, S, W}), so it can be tested on its own without building anything.
--
-- Spawn room: a 2x2 block of cells with the walls inside it knocked down, and 2-3 exits to the rest
--   of the maze. Monsters can never enter one. The first room is the start, in the corner.
-- Relic room: a single junction cell with 2-3 openings holding a relic. Monsters can't enter it
--   until shortly after its relic is collected.
--
-- Because monsters can't pass through these places, they must never be the only connection
-- between two parts of the maze - or a monster could be cut off from part of it. The functions
-- below check that, and knock down extra walls where needed.

local MazeLayout = {}

-- {dx, dz, wallOnThisCell, wallOnNeighbour}
local DIRS = { {0,-1,"N","S"}, {1,0,"E","W"}, {0,1,"S","N"}, {-1,0,"W","E"} }
MazeLayout.DIRS = DIRS

local function key(x, z) return x * 1000 + z end
MazeLayout.key = key

local function shuffle(list)
	for i = #list, 2, -1 do
		local j = math.random(i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

local function openSides(walls, x, z)
	local w = walls[x][z]
	return (w.N and 0 or 1) + (w.E and 0 or 1) + (w.S and 0 or 1) + (w.W and 0 or 1)
end
MazeLayout.openSides = openSides

local function setWall(walls, x, z, d, closed)
	walls[x][z][d[3]] = closed
	walls[x + d[1]][z + d[2]][d[4]] = closed
end

-- Group the cells that aren't blocked into connected regions ("components").
-- Returns comp[key] = region number, and how many regions there are.
local function components(walls, n, blocked)
	local comp, count = {}, 0
	for sx = 1, n do
		for sz = 1, n do
			local k = key(sx, sz)
			if comp[k] or blocked[k] then continue end
			count += 1
			comp[k] = count
			local queue, head = { {sx, sz} }, 1
			while head <= #queue do
				local c = queue[head]
				head += 1
				for _, d in DIRS do
					if not walls[c[1]][c[2]][d[3]] then
						local nx, nz = c[1] + d[1], c[2] + d[2]
						local nk = key(nx, nz)
						if not comp[nk] and not blocked[nk] then
							comp[nk] = count
							table.insert(queue, {nx, nz})
						end
					end
				end
			end
		end
	end
	return comp, count
end

-- Knock down walls between unblocked cells until all unblocked cells are one connected region.
-- Never touches walls next to a blocked cell (so rooms keep exactly the exits they were given).
function MazeLayout.connect(walls, n, blocked)
	while true do
		local comp, count = components(walls, n, blocked)
		if count <= 1 then return end
		-- find walls between two different regions; open one at random
		local options = {}
		for x = 1, n do
			for z = 1, n do
				local a = comp[key(x, z)]
				if not a then continue end
				for _, d in { DIRS[2], DIRS[3] } do        -- east and south: each wall checked once
					local nx, nz = x + d[1], z + d[2]
					local b = nx <= n and nz <= n and comp[key(nx, nz)]
					if b and b ~= a and walls[x][z][d[3]] then
						table.insert(options, { x, z, d })
					end
				end
			end
		end
		if #options == 0 then return end   -- can't happen in a grid, but never loop forever
		local o = options[math.random(#options)]
		setWall(walls, o[1], o[2], o[3], false)
	end
end

-- Which quarter of the maze a cell is in: 1-4 (the middle row/column counts as east/south)
function MazeLayout.quadrant(x, z, n)
	local east = x * 2 > n and 1 or 0
	local south = z * 2 > n and 1 or 0
	return 1 + east + 2 * south
end
local quadrant = MazeLayout.quadrant

---------------------------------------------------------------- spawn rooms
-- Carves `count` 2x2 rooms. The first is always the start room at cells (1,1)-(2,2). The others
-- are placed at random, each wholly inside a quarter of the maze that no other room is in (while
-- there are free quarters left), and at least `spacing` cells (Chebyshev distance) from every
-- other room.
-- Returns a list of rooms: { id, x, z (top-left cell), cells = {[key]=true}, exits = {...} }
function MazeLayout.carveRooms(walls, n, count, spacing)
	local rooms = {}
	local usedQuadrants = {}
	local function fits(x, z)
		if x < 1 or z < 1 or x + 1 > n or z + 1 > n then return false end
		local q = quadrant(x, z, n)
		if quadrant(x + 1, z + 1, n) ~= q then return false end      -- straddles the middle
		if usedQuadrants[q] and #rooms < 4 then return false end
		for _, r in rooms do
			if math.max(math.abs(r.x - x), math.abs(r.z - z)) < spacing then return false end
		end
		return true
	end
	local function addRoom(x, z)
		local room = { id = #rooms + 1, x = x, z = z, cells = {}, exits = {} }
		for dx = 0, 1 do
			for dz = 0, 1 do room.cells[key(x + dx, z + dz)] = true end
		end
		-- knock down the walls inside the room
		setWall(walls, x, z, DIRS[2], false)       -- (x,z)   | (x+1,z)
		setWall(walls, x, z + 1, DIRS[2], false)   -- (x,z+1) | (x+1,z+1)
		setWall(walls, x, z, DIRS[3], false)       -- (x,z)   / (x,z+1)
		setWall(walls, x + 1, z, DIRS[3], false)   -- (x+1,z) / (x+1,z+1)
		table.insert(rooms, room)
		usedQuadrants[quadrant(x, z, n)] = true
	end

	addRoom(1, 1)   -- the start room
	local candidates = {}
	for x = 1, n - 1 do
		for z = 1, n - 1 do table.insert(candidates, { x, z }) end
	end
	shuffle(candidates)
	for _, c in candidates do
		if #rooms >= count then break end
		if fits(c[1], c[2]) then addRoom(c[1], c[2]) end
	end

	-- Give each room 2-3 exits: keep some of its existing openings, open or close the rest
	for _, room in rooms do
		local edges, open = {}, {}
		for k in room.cells do
			local x, z = k // 1000, k % 1000
			for _, d in DIRS do
				local nx, nz = x + d[1], z + d[2]
				if nx >= 1 and nx <= n and nz >= 1 and nz <= n and not room.cells[key(nx, nz)] then
					local edge = { x, z, d }
					table.insert(edges, edge)
					if not walls[x][z][d[3]] then table.insert(open, edge) end
				end
			end
		end
		local want = math.random(2, 3)
		shuffle(open)
		shuffle(edges)
		local exits = {}
		for i = 1, math.min(want, #open) do table.insert(exits, open[i]) end
		for _, e in edges do                        -- not enough openings: make more
			if #exits >= want then break end
			if not table.find(exits, e) then table.insert(exits, e) end
		end
		for _, e in edges do setWall(walls, e[1], e[2], e[3], true) end   -- close every edge...
		for _, e in exits do setWall(walls, e[1], e[2], e[3], false) end  -- ...then open the exits
		room.exits = exits
	end
	return rooms
end

---------------------------------------------------------------- relic rooms
-- Picks up to `count` relic cells: cells with 2-3 openings (so there's more than one way out),
-- not in or right next to a spawn room, at least `spacing` cells apart (straight-line distance),
-- and at most `nearStart` of them in the start room's quarter of the maze.
-- Monsters can walk through relic cells, so picks never affect how the maze connects.
-- If it can't fit `count` relics that far apart, it tries again with the spacing reduced in
-- half-cell steps (down to 2), so the match always gets its full set.
-- Returns a list of { x, z }, and the spacing actually used.
local tryPick
function MazeLayout.pickRelics(walls, n, rooms, count, spacing, nearStart)
	local picks
	local s = spacing
	while true do
		picks = tryPick(walls, n, rooms, count, s, nearStart or count)
		if #picks >= count or s <= 2 then break end
		s -= 0.5
	end
	return picks, s
end

function tryPick(walls, n, rooms, count, spacing, nearStart)
	local startQuadrant = quadrant(rooms[1].x, rooms[1].z, n)
	local inStart = 0
	local nearRoom = {}
	for _, room in rooms do
		for dx = -1, 2 do
			for dz = -1, 2 do nearRoom[key(room.x + dx, room.z + dz)] = true end
		end
	end
	local candidates = {}
	for x = 1, n do
		for z = 1, n do
			local sides = openSides(walls, x, z)
			if (sides == 2 or sides == 3) and not nearRoom[key(x, z)] then
				table.insert(candidates, { x, z })
			end
		end
	end
	shuffle(candidates)

	local picks = {}
	for _, c in candidates do
		if #picks >= count then break end
		local ok = true
		for _, p in picks do
			if (Vector2.new(p[1], p[2]) - Vector2.new(c[1], c[2])).Magnitude < spacing then ok = false break end
		end
		local q = quadrant(c[1], c[2], n)
		if ok and q == startQuadrant and inStart >= nearStart then ok = false end
		if ok then
			table.insert(picks, c)
			if q == startQuadrant then inStart += 1 end
		end
	end
	return picks
end

---------------------------------------------------------------- doors
-- Shortest walking distance (in steps) from cell a to cell b, avoiding blocked cells, or nil if
-- there's no way through.
local function distance(walls, n, ax, az, bx, bz, blocked)
	local dist = { [key(ax, az)] = 0 }
	local queue, head = { {ax, az} }, 1
	while head <= #queue do
		local c = queue[head]
		head += 1
		local here = dist[key(c[1], c[2])]
		if c[1] == bx and c[2] == bz then return here end
		for _, d in DIRS do
			if not walls[c[1]][c[2]][d[3]] then
				local nx, nz = c[1] + d[1], c[2] + d[2]
				local nk = key(nx, nz)
				if dist[nk] == nil and not blocked[nk] then
					dist[nk] = here + 1
					table.insert(queue, {nx, nz})
				end
			end
		end
	end
	return nil
end

-- Picks DOOR SLOTS: cell sides that can open and close during a match. Two kinds:
--   corridor doors - in an existing opening; they start open, and closing one forces a detour
--   shortcut doors - in place of a wall; they start closed, and opening one cuts a long way round
-- The rule that keeps every door safe to work at any time: with EVERY door closed, the maze is
-- still one connected piece, for survivors and for monsters (who can't use spawn rooms). So no
-- combination of doors can cut anyone off from a relic or a room - doors only redirect.
-- Doors never touch a spawn room or a relic cell (rooms keep their exits, relics their 2-3 ways in).
-- options: corridors, shortcuts (how many of each), spacing (cells between doors), minDetour
-- (closing a corridor door / opening a shortcut must save or cost at least this many steps).
-- Leaves walls with corridor doors open and shortcut doors closed.
-- Returns a list of { x, z, d (a DIRS entry: the side of cell x,z), open (starting state), kind }.
function MazeLayout.placeDoors(walls, n, rooms, relics, options)
	local roomCells, avoid = {}, {}
	for _, room in rooms do
		for k in room.cells do roomCells[k] = true avoid[k] = true end
	end
	for _, r in relics do avoid[key(r[1], r[2])] = true end

	local doors = {}
	local function spacedOut(x, z, d)
		-- edge midpoint, in cell units
		local mx, mz = x + d[1] / 2, z + d[2] / 2
		for _, door in doors do
			local ox, oz = door.x + door.d[1] / 2, door.z + door.d[2] / 2
			if math.max(math.abs(mx - ox), math.abs(mz - oz)) < options.spacing then return false end
		end
		return true
	end

	-- Every interior side once (east and south of each cell), not touching a room or relic
	local open, closed = {}, {}
	for x = 1, n do
		for z = 1, n do
			for _, d in { DIRS[2], DIRS[3] } do
				local nx, nz = x + d[1], z + d[2]
				if nx > n or nz > n or avoid[key(x, z)] or avoid[key(nx, nz)] then continue end
				table.insert(walls[x][z][d[3]] and closed or open, { x, z, d })
			end
		end
	end
	shuffle(open)
	shuffle(closed)

	-- Corridor doors: close one for good (as if every door were shut), and keep it only if the
	-- two sides are still joined the long way round - by a route monsters can use too, which
	-- means survivors can as well.
	for _, e in open do
		if #doors >= options.corridors then break end
		local x, z, d = e[1], e[2], e[3]
		if not spacedOut(x, z, d) then continue end
		setWall(walls, x, z, d, true)
		local around = distance(walls, n, x, z, x + d[1], z + d[2], roomCells)
		if around and around >= options.minDetour then
			table.insert(doors, { x = x, z = z, d = d, open = true, kind = "corridor" })
		else
			setWall(walls, x, z, d, false)
		end
	end

	-- Shortcut doors: walls between cells that are a long way apart with every door shut. Opening
	-- one can't disconnect anything, so the only test is that it's worth having.
	local shortcuts = {}
	for _, e in closed do
		local x, z, d = e[1], e[2], e[3]
		local around = distance(walls, n, x, z, x + d[1], z + d[2], roomCells)
		if around and around >= options.minDetour then
			table.insert(shortcuts, { x, z, d, around })
		end
	end
	table.sort(shortcuts, function(a, b) return a[4] > b[4] end)   -- the biggest shortcuts first
	local added = 0
	for _, s in shortcuts do
		if added >= options.shortcuts then break end
		if spacedOut(s[1], s[2], s[3]) then
			table.insert(doors, { x = s[1], z = s[2], d = s[3], open = false, kind = "shortcut" })
			added += 1
		end
	end

	-- Every door shut is now the state of the walls table; open the corridor doors
	for _, door in doors do
		if door.open then setWall(walls, door.x, door.z, door.d, false) end
	end
	return doors
end

MazeLayout.setWall = setWall
MazeLayout.components = components

return MazeLayout
