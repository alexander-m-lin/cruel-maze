-- A monster that roams the maze and hunts players.
--
-- It moves along the maze's grid of cells (using the layout MazeBuilder generated), so it never
-- gets stuck on walls. To find a route it uses "breadth-first search" (BFS): explore outward from
-- the monster's cell one step at a time until reaching the target cell, then walk back along the
-- steps taken. In a maze, that's always the shortest route.
--
-- Behaviour:
--   ROAM   - wander to random cells
--   CHASE  - it saw you (line of sight) or heard you (very close, even through walls)
--   SEARCH - lost you: go to where it last saw you, then go back to roaming
-- If it touches you, you're caught: knocked out and sent back to the start.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local MazeBuilder = require(game:GetService("ServerStorage").MazeBuilder)

local ROAM_SPEED   = 8      -- studs per second (players walk at 16)
local SEARCH_SPEED = 11
local CHASE_SPEED  = 13
local SIGHT_RANGE  = 60     -- sees you this far if no wall is in the way
local HEAR_RANGE   = 14     -- notices you this close even through walls
local LOSE_AFTER   = 4      -- seconds without seeing you before it stops chasing
local CATCH_DIST   = 4      -- how close counts as caught
local CATCH_GRACE  = 4      -- seconds it ignores a player it just caught
local HOVER        = 3.2    -- how high it floats above the floor

local DIRS = { {0, -1, "N"}, {1, 0, "E"}, {0, 1, "S"}, {-1, 0, "W"} }

local maze          -- MazeBuilder.current: { walls, n, S, half, floorY, model }
local monster       -- the Model
local pos           -- current position (on the floor plane)
local facing = Vector3.new(0, 0, -1)
local path = {}     -- list of {x, z} cells still to walk through
local mode = "roam"
local chaseTarget, targetCell, lastSeenAt = nil, nil, 0
local detectTimer = 0
local graceUntil = {}

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

---------------------------------------------------------------- grid helpers
local function cellOf(p)
	local x = math.clamp(math.floor((p.X + maze.half) / maze.S) + 1, 1, maze.n)
	local z = math.clamp(math.floor((p.Z + maze.half) / maze.S) + 1, 1, maze.n)
	return x, z
end

local function centerOf(x, z)
	return Vector3.new((x - 0.5) * maze.S - maze.half, maze.floorY, (z - 0.5) * maze.S - maze.half)
end

-- Shortest route from one cell to another (list of cells, not including the start)
local function findPath(sx, sz, tx, tz)
	if sx == tx and sz == tz then return {} end
	local function key(x, z) return x * 1000 + z end
	local cameFrom = { [key(sx, sz)] = false }
	local queue, head = { {sx, sz} }, 1
	while head <= #queue do
		local c = queue[head]
		head += 1
		if c[1] == tx and c[2] == tz then break end
		for _, d in DIRS do
			if not maze.walls[c[1]][c[2]][d[3]] then          -- no wall on that side = can walk through
				local nx, nz = c[1] + d[1], c[2] + d[2]
				if cameFrom[key(nx, nz)] == nil then
					cameFrom[key(nx, nz)] = c
					table.insert(queue, {nx, nz})
				end
			end
		end
	end
	if cameFrom[key(tx, tz)] == nil then return {} end
	local route, c = {}, {tx, tz}
	while c and not (c[1] == sx and c[2] == sz) do
		table.insert(route, 1, c)
		c = cameFrom[key(c[1], c[2])]
	end
	return route
end

---------------------------------------------------------------- the monster's body
local function buildMonster()
	local model = Instance.new("Model")
	model.Name = "Monster"

	local function piece(name, shape, size, offset, color, material)
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = shape
		p.Size = size
		p.CFrame = CFrame.new(offset)
		p.Color = color
		p.Material = material
		p.Anchored = true
		p.CanCollide, p.CanTouch, p.CanQuery = false, false, false
		p.CastShadow = false   -- a shadow would give its position away through the fog
		p.Parent = model
		return p
	end

	local body = piece("Body", Enum.PartType.Ball, Vector3.new(5, 5, 5), Vector3.zero,
		Color3.fromRGB(40, 15, 50), Enum.Material.SmoothPlastic)
	piece("EyeL", Enum.PartType.Ball, Vector3.new(0.9, 0.9, 0.9), Vector3.new(-0.9, 0.6, -2.1),
		Color3.fromRGB(255, 40, 40), Enum.Material.Neon)
	piece("EyeR", Enum.PartType.Ball, Vector3.new(0.9, 0.9, 0.9), Vector3.new(0.9, 0.6, -2.1),
		Color3.fromRGB(255, 40, 40), Enum.Material.Neon)

	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 40, 40)
	glow.Range = 12
	glow.Brightness = 1.5
	glow.Parent = body

	model.PrimaryPart = body
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent  -- clients always know where it is (for pings)
	CollectionService:AddTag(model, "Monster")       -- the ping script looks for this
	CollectionService:AddTag(model, "HiddenByFog")   -- the fog script hides it unless you can see it
	model.Parent = workspace
	return model
end

---------------------------------------------------------------- senses
local function rootOf(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return character:FindFirstChild("HumanoidRootPart"), humanoid
	end
end

local function canDetect(root)
	local eye = pos + Vector3.new(0, HOVER, 0)
	local offset = root.Position - eye
	local flat = Vector3.new(offset.X, 0, offset.Z).Magnitude
	if flat <= HEAR_RANGE then return true end
	if flat > SIGHT_RANGE then return false end
	return workspace:Raycast(eye, offset, rayParams) == nil   -- nothing in the way = it can see you
end

---------------------------------------------------------------- new maze
local function onNewMaze()
	maze = MazeBuilder.current
	if not maze then return end
	rayParams.FilterDescendantsInstances = { maze.model }
	monster = monster or buildMonster()
	local mid = math.ceil(maze.n / 2)
	pos = centerOf(mid, mid)               -- start in the middle, far from the start corner
	path, mode, chaseTarget, targetCell = {}, "roam", nil, nil
end

workspace.ChildAdded:Connect(function(child)
	if child.Name == "Maze" then
		task.defer(onNewMaze)
	end
end)
if MazeBuilder.current then onNewMaze() end

---------------------------------------------------------------- main loop
RunService.Heartbeat:Connect(function(dt)
	if not (maze and monster and maze.model.Parent) then return end
	local now = os.clock()

	-- 1. SENSES (5 times a second): pick the closest player it can detect
	detectTimer -= dt
	if detectTimer <= 0 then
		detectTimer = 0.2
		local best, bestDist
		for _, player in Players:GetPlayers() do
			local root = rootOf(player)
			if root and (graceUntil[player] or 0) < now and canDetect(root) then
				local d = (root.Position - pos).Magnitude
				if not bestDist or d < bestDist then best, bestDist = player, d end
			end
		end
		if best then
			if mode ~= "chase" then path = {} end
			mode, chaseTarget, lastSeenAt = "chase", best, now
			targetCell = { cellOf(rootOf(best).Position) }
		elseif mode == "chase" and now - lastSeenAt > LOSE_AFTER then
			mode = "search"                       -- head for where it last saw you
			path = {}
		end
	end

	-- 2. DECIDE where to move next
	local cx, cz = cellOf(pos)
	local goal, speed
	local targetRoot = chaseTarget and rootOf(chaseTarget)
	if mode == "chase" and targetRoot and now - lastSeenAt < 0.5 and select(1, cellOf(targetRoot.Position)) == cx
		and select(2, cellOf(targetRoot.Position)) == cz then
		-- Same cell as you: no walls inside a cell, so go straight for you
		goal = Vector3.new(targetRoot.Position.X, maze.floorY, targetRoot.Position.Z)
		path = {}
	else
		if #path == 0 then
			if (mode == "chase" or mode == "search") and targetCell then
				path = findPath(cx, cz, targetCell[1], targetCell[2])
				if #path == 0 and mode == "search" then mode = "roam" end   -- reached it, nobody here
			end
			if mode == "roam" and #path == 0 then
				path = findPath(cx, cz, math.random(maze.n), math.random(maze.n))
			end
			-- if we're off-centre (e.g. after lunging at a player), go back to the cell centre first
			if #path > 0 and (pos - centerOf(cx, cz)).Magnitude > 0.5 then
				table.insert(path, 1, { cx, cz })
			end
		end
		goal = path[1] and centerOf(path[1][1], path[1][2])
	end
	speed = (mode == "chase" and CHASE_SPEED) or (mode == "search" and SEARCH_SPEED) or ROAM_SPEED

	-- 3. MOVE toward the goal
	if goal then
		local toGoal = goal - pos
		local step = speed * dt
		if toGoal.Magnitude <= step then
			pos = goal
			if path[1] then
				table.remove(path, 1)
				if mode == "chase" then path = {} end   -- re-plan at every cell while chasing
			end
		else
			pos += toGoal.Unit * step
		end
		if toGoal.Magnitude > 0.05 then facing = toGoal.Unit end
	end

	-- Float and bob, facing the way it's moving
	local bob = math.sin(now * 3) * 0.3
	local at = pos + Vector3.new(0, HOVER + bob, 0)
	monster:PivotTo(CFrame.lookAt(at, at + facing))

	-- 4. CATCH anyone close enough
	for _, player in Players:GetPlayers() do
		local root, humanoid = rootOf(player)
		if root and (graceUntil[player] or 0) < now then
			local flat = Vector3.new(root.Position.X - pos.X, 0, root.Position.Z - pos.Z).Magnitude
			if flat < CATCH_DIST then
				humanoid.Health = 0                      -- caught! you respawn at the start
				graceUntil[player] = now + CATCH_GRACE
				mode, chaseTarget, path = "roam", nil, {}
			end
		end
	end
end)
