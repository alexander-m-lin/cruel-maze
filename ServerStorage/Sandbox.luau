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
-- The maze, 6 x 6 cells (x right, z down; N is up the screen's grid, toward z = 1):
--
--        1   2   3   4   5   6
--      +---+---+---+---+---+---+
--    1 |           |F          |      F  = false relic (4,1), placed at the start
--      +           +           +      |  = the wall jutting in from the top (east sides of
--    2 |           D           |          (3,1)..(3,3)); D = a door in it, open at the start
--      +           +           +
--    3 |           |       |C  |      C  = a crushing wall in a short corridor (6,3), running N-S
--      +                       +          (west sides of (6,2) and (6,3) closed)
--    4 |                       |
--      +   +---+               +
--    5 | S   S |       R       |      R  = the relic (4,5)
--      +       +               +      S  = the sanctuary, 2 x 2 at (1,5), exits north of (1,5)
--    6 | S   S                 |           and east of (2,6)
--      +---+---+---+---+---+---+

local ServerStorage = game:GetService("ServerStorage")
local MazeLayout = require(ServerStorage.MazeLayout)

local DIRS, key = MazeLayout.DIRS, MazeLayout.key
local N, E, S, W = DIRS[1], DIRS[2], DIRS[3], DIRS[4]

local Sandbox = {}

Sandbox.LIVES = 99                 -- each survivor (players and spawned bots)
Sandbox.FALSE_RELIC = { 4, 1 }     -- cell of the false relic placed at the start

-- The layout, in the same form MazeLayout's planners produce (see MazeBuilder.build's options.layout)
function Sandbox.layout()
	local n = 6
	local walls = {}
	for x = 1, n do
		walls[x] = {}
		for z = 1, n do
			-- an open square: only the outer walls
			walls[x][z] = { N = z == 1, E = x == n, S = z == n, W = x == 1 }
		end
	end
	local function close(x, z, d) MazeLayout.setWall(walls, x, z, d, true) end

	-- the wall jutting in from the top, with a door slot in the middle (door slots are closed in
	-- the layout; the door itself decides whether it's open)
	close(3, 1, E)
	close(3, 2, E)
	close(3, 3, E)
	-- the crushing wall's corridor along the right-hand side
	close(6, 2, W)
	close(6, 3, W)
	-- the sanctuary's walls: north of (2,5) and east of (2,5); its exits (north of (1,5), east of
	-- (2,6)) stay open
	close(2, 5, N)
	close(2, 5, E)

	local cells = {}
	for _, c in { { 1, 5 }, { 2, 5 }, { 1, 6 }, { 2, 6 } } do cells[key(c[1], c[2])] = true end
	local sanctuaries = {
		{ id = 1, x = 1, z = 5, size = 2, cells = cells, exits = { { 1, 5, N }, { 2, 6, E } } },
	}
	local relics = { { 4, 5 } }
	local doors = { { x = 3, z = 2, d = E, open = true, kind = "corridor" } }
	local crushers = { { x = 6, z = 3, along = "Z" } }
	return { n = n, walls = walls, sanctuaries = sanctuaries, relics = relics, doors = doors, crushers = crushers }
end

return Sandbox
