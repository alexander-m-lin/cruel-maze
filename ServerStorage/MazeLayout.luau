-- Plans the special places in a maze: SANCTUARIES and RELIC ROOMS. Works only on the layout table
-- (walls[x][z] = {N, E, S, W}), so it can be tested on its own without building anything.
--
-- Sanctuary: a square block of cells (2x2; the start one 3x3) with the walls inside it knocked down,
--   and 2-3 exits, spread apart, to the rest of the maze. Monsters can never enter one, and the
--   monster side can't see survivors inside. The first sanctuary is the start, in the corner.
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

-- Knock down walls between unblocked cells until all unblocked cells are one connected region.
-- Never touches walls next to a blocked cell (so sanctuaries keep exactly the exits they were given).
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

---------------------------------------------------------------- sanctuaries
-- Is cell (x, z) in sanctuary `s`, or within `margin` cells of it?
function MazeLayout.nearSanctuary(s, x, z, margin)
	margin = margin or 0
	return x >= s.x - margin and x <= s.x + s.size - 1 + margin and z >= s.z - margin and z <= s.z + s.size - 1 + margin
end

-- Carves `count` sanctuaries. The first is always the start sanctuary, startSize x startSize cells
-- in the corner from (1,1); the others are size x size, placed at random, each wholly inside a
-- quarter of the maze that no other sanctuary is in (while there are free quarters left), and at
-- least `spacing` cells (Chebyshev distance, between their corners) from every other.
-- Each gets 2-3 exits, spread out: from the cell just outside one exit to the cell just outside
-- another is at least exitSpacing steps walking the maze (not through any sanctuary), so nobody can
-- hold two exits at once. (It also connects the maze round the sanctuaries first - see connect -
-- so those walks are the real ones.)
-- Returns a list of sanctuaries: { id, x, z (top-left cell), size, cells = {[key]=true}, exits = {...} }
function MazeLayout.carveSanctuaries(walls, n, count, spacing, options)
	options = options or {}
	local startSize, size = options.startSize or 2, options.size or 2
	local exitSpacing = options.exitSpacing or 0
	local sanctuaries = {}
	local usedQuadrants = {}
	local function fits(x, z)
		if x < 1 or z < 1 or x + size - 1 > n or z + size - 1 > n then return false end
		local q = quadrant(x, z, n)
		if quadrant(x + size - 1, z + size - 1, n) ~= q then return false end      -- straddles the middle
		if usedQuadrants[q] and #sanctuaries < 4 then return false end
		for _, r in sanctuaries do
			if math.max(math.abs(r.x - x), math.abs(r.z - z)) < spacing + (r.size - 2) then return false end
		end
		return true
	end
	local function addSanctuary(x, z, s)
		local sanctuary = { id = #sanctuaries + 1, x = x, z = z, size = s, cells = {}, exits = {} }
		for dx = 0, s - 1 do
			for dz = 0, s - 1 do
				sanctuary.cells[key(x + dx, z + dz)] = true
				-- knock down the walls inside it
				if dx < s - 1 then setWall(walls, x + dx, z + dz, DIRS[2], false) end   -- east side
				if dz < s - 1 then setWall(walls, x + dx, z + dz, DIRS[3], false) end   -- south side
			end
		end
		table.insert(sanctuaries, sanctuary)
		usedQuadrants[quadrant(x, z, n)] = true
	end

	addSanctuary(1, 1, startSize)   -- the start sanctuary
	local candidates = {}
	for x = 1, n - 1 do
		for z = 1, n - 1 do table.insert(candidates, { x, z }) end
	end
	shuffle(candidates)
	for _, c in candidates do
		if #sanctuaries >= count then break end
		if fits(c[1], c[2]) then addSanctuary(c[1], c[2], size) end
	end

	-- The rest of the maze as one piece round the sanctuaries, so walking distances are final
	local blocked = {}
	for _, sanctuary in sanctuaries do
		for k in sanctuary.cells do blocked[k] = true end
	end
	MazeLayout.connect(walls, n, blocked)

	-- Give each 2-3 exits: keep some of its existing openings (else open new ones), spread apart
	for _, sanctuary in sanctuaries do
		local edges, open = {}, {}
		for k in sanctuary.cells do
			local x, z = k // 1000, k % 1000
			for _, d in DIRS do
				local nx, nz = x + d[1], z + d[2]
				if nx >= 1 and nx <= n and nz >= 1 and nz <= n and not sanctuary.cells[key(nx, nz)] then
					local edge = { x, z, d, out = { nx, nz } }
					table.insert(edges, edge)
					if not walls[x][z][d[3]] then table.insert(open, edge) end
				end
			end
		end
		-- the start sanctuary always aims for 3 (everyone begins there); the others 2 or 3
		local want = sanctuary.id == 1 and 3 or math.random(2, 3)
		shuffle(edges)
		-- walking steps between the cells just outside each pair of edges (nil: no way round)
		local steps = {}
		for i, e in edges do
			steps[i] = {}
			for j, f in edges do
				if j > i then steps[i][j] = distance(walls, n, e.out[1], e.out[2], f.out[1], f.out[2], blocked) end
			end
		end
		local function far(i, j)
			if i > j then i, j = j, i end
			local d = steps[i][j]
			return d == nil or d >= exitSpacing
		end
		local isOpen = {}
		for _, e in open do isOpen[e] = true end
		-- every set of `want` edges (then fewer) that are all spread apart; among them, the ones
		-- keeping the most existing openings (changing the maze least), one at random
		local exits = {}
		for size = want, 1, -1 do
			local best, bestScore, ties = nil, -1, 0
			local chosen = {}
			local function search(from)
				if #chosen == size then
					local score = 0
					for _, i in chosen do if isOpen[edges[i]] then score += 1 end end
					if score > bestScore then best, bestScore, ties = table.clone(chosen), score, 1
					elseif score == bestScore then
						ties += 1
						if math.random(ties) == 1 then best = table.clone(chosen) end
					end
					return
				end
				for i = from, #edges do
					local ok = true
					for _, c in chosen do if not far(c, i) then ok = false break end end
					if ok then
						table.insert(chosen, i)
						search(i + 1)
						table.remove(chosen)
					end
				end
			end
			search(1)
			if best then
				for _, i in best do table.insert(exits, edges[i]) end
				break
			end
		end
		for _, e in edges do setWall(walls, e[1], e[2], e[3], true) end   -- close every edge...
		for _, e in exits do setWall(walls, e[1], e[2], e[3], false) end  -- ...then open the exits
		sanctuary.exits = exits
	end
	return sanctuaries
end

---------------------------------------------------------------- relic rooms
-- Picks up to `count` relic cells: cells with 2-3 openings (so there's more than one way out),
-- not in or right next to a sanctuary, at least `spacing` cells apart (straight-line distance),
-- and at most `nearStart` of them in the start sanctuary's quarter of the maze.
-- Monsters can walk through relic cells, so picks never affect how the maze connects.
-- If it can't fit `count` relics that far apart, it tries again with the spacing reduced in
-- half-cell steps (down to 2), so the match always gets its full set.
-- Returns a list of { x, z }, and the spacing actually used.
local tryPick
function MazeLayout.pickRelics(walls, n, sanctuaries, count, spacing, nearStart)
	local picks
	local s = spacing
	while true do
		picks = tryPick(walls, n, sanctuaries, count, s, nearStart or count)
		if #picks >= count or s <= 2 then break end
		s -= 0.5
	end
	return picks, s
end

function tryPick(walls, n, sanctuaries, count, spacing, nearStart)
	local startQuadrant = quadrant(sanctuaries[1].x, sanctuaries[1].z, n)
	local inStart = 0
	local nearSanctuary = {}
	for _, sanctuary in sanctuaries do
		for dx = -1, sanctuary.size do
			for dz = -1, sanctuary.size do nearSanctuary[key(sanctuary.x + dx, sanctuary.z + dz)] = true end
		end
	end
	local candidates = {}
	for x = 1, n do
		for z = 1, n do
			local sides = openSides(walls, x, z)
			if (sides == 2 or sides == 3) and not nearSanctuary[key(x, z)] then
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
-- Picks DOOR SLOTS: cell sides that can open and close during a match. Two kinds:
--   corridor doors - in an existing opening; they start open, and closing one forces a detour
--   shortcut doors - in place of a wall; they start closed, and opening one cuts a long way round
-- The rule that keeps every door safe to work at any time: with EVERY door closed, the maze is
-- still one connected piece, for survivors and for monsters (who can't use sanctuaries). So no
-- combination of doors can cut anyone off from a relic or a sanctuary - doors only redirect.
-- Doors never touch a sanctuary or a relic cell (sanctuaries keep their exits, relics their 2-3 ways in).
-- options: corridors, shortcuts (how many of each), spacing (cells between doors), minDetour
-- (closing a corridor door / opening a shortcut must save or cost at least this many steps),
-- exitSpacing (with every door open, a sanctuary's exits must still be at least this many steps
-- apart: no shortcut door between them - see carveSanctuaries).
-- Leaves walls with corridor doors open and shortcut doors closed.
-- Returns a list of { x, z, d (a DIRS entry: the side of cell x,z), open (starting state), kind }.
function MazeLayout.placeDoors(walls, n, sanctuaries, relics, options)
	local sanctuaryCells, avoid = {}, {}
	for _, sanctuary in sanctuaries do
		for k in sanctuary.cells do sanctuaryCells[k] = true avoid[k] = true end
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

	-- Every interior side once (east and south of each cell), not touching a sanctuary or relic
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
		local around = distance(walls, n, x, z, x + d[1], z + d[2], sanctuaryCells)
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
		local around = distance(walls, n, x, z, x + d[1], z + d[2], sanctuaryCells)
		if around and around >= options.minDetour then
			table.insert(shortcuts, { x, z, d, around })
		end
	end
	table.sort(shortcuts, function(a, b) return a[4] > b[4] end)   -- the biggest shortcuts first
	-- With every door so far and this one open, are all sanctuaries' exits still spread apart?
	local exitSpacing = options.exitSpacing or 0
	local function keepsExitsApart(x, z, d)
		if exitSpacing <= 0 then return true end
		for _, door in doors do setWall(walls, door.x, door.z, door.d, false) end
		setWall(walls, x, z, d, false)
		local ok = true
		for _, sanctuary in sanctuaries do
			for i = 1, #sanctuary.exits do
				for j = i + 1, #sanctuary.exits do
					local a, b = sanctuary.exits[i].out, sanctuary.exits[j].out
					local steps = a and b and distance(walls, n, a[1], a[2], b[1], b[2], sanctuaryCells)
					if steps and steps < exitSpacing then ok = false end
				end
			end
		end
		setWall(walls, x, z, d, true)
		for _, door in doors do setWall(walls, door.x, door.z, door.d, true) end
		return ok
	end
	local added = 0
	for _, s in shortcuts do
		if added >= options.shortcuts then break end
		if spacedOut(s[1], s[2], s[3]) and keepsExitsApart(s[1], s[2], s[3]) then
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

---------------------------------------------------------------- crushing walls
-- Picks CRUSHER cells: straight corridor cells (open at two opposite ends, ordinary walls on the
-- other two sides) whose side walls can slam together. Not in or next to a sanctuary, not a relic
-- cell, and at least `spacing` cells from every door and other crusher. They never change how the
-- maze connects (they only shut for a moment).
-- Returns a list of { x, z, along = "X" or "Z" (the way the corridor runs) }.
function MazeLayout.placeCrushers(walls, n, sanctuaries, relics, doors, count, spacing)
	local avoid = {}
	for _, sanctuary in sanctuaries do
		for dx = -1, sanctuary.size do
			for dz = -1, sanctuary.size do avoid[key(sanctuary.x + dx, sanctuary.z + dz)] = true end
		end
	end
	for _, r in relics do avoid[key(r[1], r[2])] = true end
	-- door slots, by the cell side they're on (both cells' views of it)
	local doorSide = {}
	for _, door in doors do
		doorSide[key(door.x, door.z) .. door.d[3]] = true
		doorSide[key(door.x + door.d[1], door.z + door.d[2]) .. door.d[4]] = true
	end
	local candidates = {}
	for x = 1, n do
		for z = 1, n do
			if avoid[key(x, z)] then continue end
			local w = walls[x][z]
			local along
			if not w.E and not w.W and w.N and w.S then along = "X"
			elseif not w.N and not w.S and w.E and w.W then along = "Z" end
			if not along then continue end
			local sides = along == "X" and { "N", "S" } or { "E", "W" }
			if doorSide[key(x, z) .. sides[1]] or doorSide[key(x, z) .. sides[2]] then continue end
			table.insert(candidates, { x = x, z = z, along = along })
		end
	end
	shuffle(candidates)
	local picks = {}
	for _, c in candidates do
		if #picks >= count then break end
		local ok = true
		for _, p in picks do
			if math.max(math.abs(p.x - c.x), math.abs(p.z - c.z)) < spacing then ok = false break end
		end
		for _, door in doors do
			local mx, mz = door.x + door.d[1] / 2, door.z + door.d[2] / 2
			if math.max(math.abs(mx - c.x), math.abs(mz - c.z)) < spacing - 0.5 then ok = false break end
		end
		if ok then table.insert(picks, c) end
	end
	return picks
end

MazeLayout.setWall = setWall
MazeLayout.components = components

return MazeLayout
