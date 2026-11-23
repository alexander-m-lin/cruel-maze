-- THE SANDBOX: a developer-only test match on a small hand-made maze, for quick QA. Everything in it
-- runs on the real game's code (Match, MazeBuilder, Objectives, monsters, bots, abilities...); the
-- sandbox only changes what goes in:
--   - the maze: Sandbox.layout() below, handed to MazeBuilder.build instead of a generated one
--   - who's there: only the players (no AI monsters, survivor bots or AI Maze Master to start with);
--     the sandbox panel (SandboxPanel, on a developer's computer) spawns more through Match
--   - no end: no timer, no win or loss, and Sandbox.LIVES each
--
-- Started from the dev panel's "Sandbox" button (Match: the "DevMatch" remote's "sandbox" action);
-- "New match" goes back to a normal match.
--
-- The maze, 9 x 9 cells (x right, z down; N is up this grid, toward z = 1). With the isometric camera,
-- (1,1) is the bottom of the screen and (9,9) the top. Sandbox.MAP below is the layout itself: its walls
-- are read from it, so change the maze by editing the picture. The square at (1..6, 1..6) is open:
--   F  = false relic (4,1), placed at the start
--   D  = a door in the wall jutting in from the top (east sides of (3,1)..(3,3)), open at the start
--   C  = a crushing wall in a short corridor (6,3), running N-S (west sides of (6,2) and (6,3) closed)
--   R  = the relic (4,5)
--   S  = the sanctuary, 2 x 2 at (1,5), exits north of (1,5) and east of (2,6)
-- Around it, wrapping the top corner (x 7..9, and z 7..9), WINDING HALLWAYS like the real maze's:
-- 1-cell corridors with turns, junctions, a loop and two dead ends ((2,8), and (9,9) at the very top),
-- entered from the square east of (6,1), east of (6,5) and south of (4,6).

local ServerStorage = game:GetService("ServerStorage")
local MazeLayout = require(ServerStorage.MazeLayout)

local DIRS, key = MazeLayout.DIRS, MazeLayout.key
local N, E = DIRS[1], DIRS[2]

local Sandbox = {}

Sandbox.LIVES = 99                 -- each survivor (players and spawned bots)
Sandbox.FALSE_RELIC = { 4, 1 }     -- cell of the false relic placed at the start

-- The maze as a picture: "---" and "|" are walls, any other character in a wall's spot is a wall too
-- (D, the door's slot), and letters inside cells are only labels (see the key at the top)
Sandbox.MAP = [[
+---+---+---+---+---+---+---+---+---+
|           | F                     |
+   +   +   +   +   +   +---+---+   +
|           D       |   |           |
+   +   +   +   +   +   +   +---+---+
|           |       | C |           |
+   +   +   +   +   +   +   +---+   +
|                       |   |       |
+   +---+   +   +   +   +   +   +---+
| S   S |     R             |       |
+   +   +   +   +   +   +   +   +   +
| S   S                 |       |   |
+---+---+---+   +---+---+---+---+   +
|                   |           |   |
+   +---+---+---+   +   +   +   +   +
|   |           |   |   |   |       |
+   +---+---+   +   +   +   +---+---+
|               |       |           |
+---+---+---+---+---+---+---+---+---+
]]

-- Sandbox.MAP read into walls[x][z] = { N, E, S, W } (true = closed)
local function readMap(map)
	local lines = string.split(map, "\n")
	local n = (#lines[1] - 1) // 4
	local function wallAt(line, i, j) return string.sub(lines[line], i, j) ~= string.rep(" ", j - i + 1) end
	local function north(x, z) return wallAt(2 * z - 1, 4 * x - 2, 4 * x) end   -- line 2z-1 is above row z
	local function west(x, z) return wallAt(2 * z, 4 * x - 3, 4 * x - 3) end
	local walls = {}
	for x = 1, n do
		walls[x] = {}
		for z = 1, n do
			walls[x][z] = { N = north(x, z), W = west(x, z), E = west(x + 1, z), S = north(x, z + 1) }
		end
	end
	return n, walls
end

-- The layout, in the same form MazeLayout's planners produce (see MazeBuilder.build's options.layout)
function Sandbox.layout()
	local n, walls = readMap(Sandbox.MAP)
	local cells = {}
	for _, c in { { 1, 5 }, { 2, 5 }, { 1, 6 }, { 2, 6 } } do cells[key(c[1], c[2])] = true end
	local sanctuaries = {
		{ id = 1, x = 1, z = 5, size = 2, cells = cells, exits = { { 1, 5, N }, { 2, 6, E } } },
	}
	local relics = { { 4, 5 } }
	-- (door slots are closed in the layout; the door itself decides whether it's open)
	local doors = { { x = 3, z = 2, d = E, open = true, kind = "corridor" } }
	local crushers = { { x = 6, z = 3, along = "Z" } }
	return { n = n, walls = walls, sanctuaries = sanctuaries, relics = relics, doors = doors, crushers = crushers }
end

return Sandbox
