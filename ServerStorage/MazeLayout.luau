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

---------------------------------------------------------------- spawn rooms
-- Carves `count` 2x2 rooms. The first is always the start room at cells (1,1)-(2,2). The others
-- are placed at random, at least `spacing` cells (Chebyshev distance) from every other room.
-- Returns a list of rooms: { id, x, z (top-left cell), cells = {[key]=true}, exits = {...} }
function MazeLayout.carveRooms(walls, n, count, spacing)
	local rooms = {}
	local function fits(x, z)
		if x < 1 or z < 1 or x + 1 > n or z + 1 > n then return false end
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
-- Picks up to `count` relic cells: junctions with 2-3 openings, not in or right next to a spawn
-- room, at least `spacing` cells apart (straight-line distance in cells). Each pick is only kept
-- if monsters can still reach every other open cell without passing through it.
-- blocked: cells monsters already can't enter (the spawn rooms). Adds the picks to it.
-- If it can't fit `count` relics that far apart, it tries again with the spacing reduced in
-- half-cell steps (down to 2), so the match always gets its full set.
-- Returns a list of { x, z }, and the spacing actually used.
local tryPick
function MazeLayout.pickRelics(walls, n, rooms, blocked, count, spacing)
	local picks
	local s = spacing
	while true do
		picks = tryPick(walls, n, rooms, blocked, count, s)
		if #picks >= count or s <= 2 then break end
		for _, p in picks do blocked[key(p[1], p[2])] = nil end   -- undo and retry closer together
		s -= 0.5
	end
	return picks, s
end

function tryPick(walls, n, rooms, blocked, count, spacing)
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
		if ok then
			blocked[key(c[1], c[2])] = true
			local _, regions = components(walls, n, blocked)
			if regions == 1 then
				table.insert(picks, c)
			else
				blocked[key(c[1], c[2])] = nil    -- it would cut monsters off: skip it
			end
		end
	end
	return picks
end

return MazeLayout
