-- KAI'S ENCRYPT on the server: his CIRCUIT INDICATORS, the real one and its copies (decoys).
-- (The ability itself: HeroAbilities.Kai; its numbers: HeroData.Kai's Ultimate.)
--
--   Encrypt.start(user, def, maze, objectives)  -- he dissolves ("EncryptedUntil" on him, server time)
--   Encrypt.stop(user)        -- it ends (run out, or ended early: an ability, a relic, a ward, caught)
--   Encrypt.isOn(user)
--   Encrypt.step()            -- every frame (Match)
--   Encrypt.positions()       -- where every indicator is now (floor points): monster players' chase
--                                speed counts them as survivors (PlayerMonster)
--   Encrypt.clear()           -- the match is over
--
-- While it lasts he's hidden from the monster side and can't be caught (Protection.encrypted;
-- Match leaves him out of who monsters may hunt). What they see instead is a blue circuit on the
-- floor of the CELL he's in (never his spot in it), which slides to the next cell when he crosses
-- into it. It only ever moves straight from one cell's middle to a neighbour's (4 ways, never
-- diagonally): cells he crosses into wait their turn, and a corner he cuts is two quick moves, across
-- then up or down (the other way round only if a wall's in the way). When it leaves a junction (3+ ways on), copies run off down the other ways out (at most
-- def.decoys at once, at most one junction every def.decoyEvery seconds), and wander from cell to
-- cell along open corridors at the same pace, now and then stopping for a moment as a person would.
--
-- Every indicator is the same: a model "Circuit<random number>" in the maze, tagged "HiddenByFog"
-- (so each player's fog shows it only where their side can see) and "CircuitIndicator", with an
-- invisible part the fog checks, and attributes for players' computers to draw it smoothly
-- (KaiEffects): From, To (floor points), MoveAt (server time), MoveTime, Ease ("both", "in", "out":
-- which ends of the move slow down; two moves round a corner run on without stopping), EndsAt,
-- WarnTime. Nothing
-- says which one is him, so nothing on anyone's computer can tell.

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local Config = require(game:GetService("ReplicatedStorage").Config)
local MazeLayout = require(ServerStorage.MazeLayout)

local DIRS = MazeLayout.DIRS

local Encrypt = {}

local active = {}   -- [user] = { def, maze, objectives, endsAt, real, decoys = {}, nextDecoyAt }

local function rootOf(who)
	local character = who.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and humanoid and humanoid.Health > 0 then return root end
	return nil
end

local function center(maze, x, z)
	return Vector3.new((x - 0.5) * maze.S - maze.half, maze.floorY, (z - 0.5) * maze.S - maze.half)
end

-- The open ways out of cell (x, z): { {x, z}, ... } (not through walls or shut doors, not into a sanctuary)
local function exits(state, x, z)
	local maze, list = state.maze, {}
	local cell = maze.walls[x] and maze.walls[x][z]
	if not cell then return list end
	for _, d in DIRS do
		local nx, nz = x + d[1], z + d[2]
		if not cell[d[3]] and nx >= 1 and nz >= 1 and nx <= maze.n and nz <= maze.n
			and not state.objectives:IsBlocked(nx, nz) then
			table.insert(list, { nx, nz })
		end
	end
	return list
end

local function moveTime(maze)
	return maze.S / Config.PLAYER_SPEED
end

local function positionOf(ind, now)
	local k = ind.moveTime > 0 and math.clamp((now - ind.moveStart) / ind.moveTime, 0, 1) or 1
	return ind.from:Lerp(ind.to, k), k >= 1
end

local function publish(ind)
	local m = ind.model
	m:SetAttribute("Ease", ind.ease or "both")
	m:SetAttribute("From", ind.from)
	m:SetAttribute("To", ind.to)
	m:SetAttribute("MoveAt", workspace:GetServerTimeNow() - (os.clock() - ind.moveStart))
	m:SetAttribute("MoveTime", ind.moveTime)
end

local function newIndicator(state, x, z, from)
	local maze = state.maze
	local model = Instance.new("Model")
	model.Name = "Circuit" .. math.random(100000, 999999)
	local part = Instance.new("Part")
	part.Name = "Spot"
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
	part.Transparency = 1
	part.CastShadow = false
	part.Size = Vector3.new(2, 0.2, 2)
	part.Position = from + Vector3.new(0, 0.5, 0)
	part.Parent = model
	model.PrimaryPart = part
	model:SetAttribute("EndsAt", state.endsAtServer)
	model:SetAttribute("WarnTime", state.def.warnTime)
	local ind = { model = model, part = part, x = x, z = z, from = from, to = from, moveStart = os.clock(), moveTime = 0 }
	publish(ind)
	model.Parent = maze.model
	CollectionService:AddTag(model, "HiddenByFog")
	CollectionService:AddTag(model, "CircuitIndicator")
	return ind
end

-- Start sliding to cell (x, z) from wherever it is now (a neighbour's middle, or back the way it
-- came: always straight along one axis). opts: { fast = true } for half the time, ease = see publish
local function moveTo(state, ind, x, z, now, opts)
	local at = positionOf(ind, now)
	ind.cameFrom = { ind.x, ind.z }
	ind.x, ind.z = x, z
	ind.from, ind.to = at, center(state.maze, x, z)
	ind.moveStart = now
	ind.moveTime = moveTime(state.maze) * (opts and opts.fast and 0.5 or 1) * ((at - ind.to).Magnitude / state.maze.S)
	ind.ease = opts and opts.ease or "both"
	ind.pauseUntil = nil
	publish(ind)
end

local function isExit(state, x, z, tx, tz)
	for _, w in exits(state, x, z) do
		if w[1] == tx and w[2] == tz then return true end
	end
	return false
end

function Encrypt.isOn(user)
	return active[user] ~= nil
end

function Encrypt.start(user, def, maze, objectives)
	local root = rootOf(user)
	if not root then return false end
	local x, z = objectives:CellOf(root.Position)
	if not x then return false end
	Encrypt.stop(user)
	local endsAtServer = workspace:GetServerTimeNow() + def.duration
	local state = { def = def, maze = maze, objectives = objectives, endsAt = os.clock() + def.duration,
		endsAtServer = endsAtServer, decoys = {}, nextDecoyAt = 0, queue = {} }
	state.real = newIndicator(state, x, z, center(maze, x, z))
	active[user] = state
	user:SetAttribute("EncryptedUntil", endsAtServer)
	return true
end

function Encrypt.stop(user)
	local state = active[user]
	if not state then return end
	active[user] = nil
	state.real.model:Destroy()
	for _, d in state.decoys do d.model:Destroy() end
	if user:GetAttribute("EncryptedUntil") then user:SetAttribute("EncryptedUntil", nil) end
end

function Encrypt.clear()
	for user in active do Encrypt.stop(user) end
end

-- The real one leaves cell A for B: at a junction, copies run off down A's other ways out
local function branch(state, ind, toX, toZ, now)
	if now < state.nextDecoyAt or #state.decoys >= state.def.decoys then return end
	local ways = exits(state, ind.x, ind.z)
	if #ways < 3 then return end
	local from = positionOf(ind, now)
	local made = false
	for _, w in ways do
		if #state.decoys >= state.def.decoys then break end
		local back = ind.cameFrom and w[1] == ind.cameFrom[1] and w[2] == ind.cameFrom[2]
		if not back and not (w[1] == toX and w[2] == toZ) then
			local decoy = newIndicator(state, ind.x, ind.z, from)
			moveTo(state, decoy, w[1], w[2], now)
			table.insert(state.decoys, decoy)
			made = true
		end
	end
	if made then state.nextDecoyAt = now + state.def.decoyEvery end
end

local function stepDecoy(state, decoy, now)
	local _, arrived = positionOf(decoy, now)
	if not arrived then return end
	if decoy.pauseUntil == nil and math.random() < state.def.pauseChance then
		decoy.pauseUntil = now + 0.3 + math.random() * 0.7
	end
	if decoy.pauseUntil and now < decoy.pauseUntil then return end
	local ways = exits(state, decoy.x, decoy.z)
	local onward = {}
	for _, w in ways do
		if not (decoy.cameFrom and w[1] == decoy.cameFrom[1] and w[2] == decoy.cameFrom[2]) then table.insert(onward, w) end
	end
	if #onward == 0 then onward = ways end          -- a dead end: back the way it came
	local pick = onward[math.random(math.max(1, #onward))]
	if pick then moveTo(state, decoy, pick[1], pick[2], now) end
end

function Encrypt.step()
	local now = os.clock()
	for user, state in active do
		local root = rootOf(user)
		if now >= state.endsAt or not root or user:GetAttribute("Seized") or not state.maze.model.Parent then
			Encrypt.stop(user)
			continue
		end
		-- the real one follows his cell: the cells he crosses into are queued, and it goes through them
		-- one neighbour at a time
		local ind = state.real
		local queue = state.queue
		local x, z = state.objectives:CellOf(root.Position)
		local last = queue[#queue] or { ind.x, ind.z }
		local _, arrived = positionOf(ind, now)
		if x and (x ~= last[1] or z ~= last[2]) then
			local dx, dz = x - last[1], z - last[2]
			if math.abs(dx) + math.abs(dz) == 1 then
				local back = #queue == 0 and not arrived and ind.cameFrom and ind.cameFrom[1] == x and ind.cameFrom[2] == z
				if back then
					moveTo(state, ind, x, z, now)             -- (turned back mid-move: straight back)
				else
					table.insert(queue, { x, z })
				end
			elseif math.abs(dx) == 1 and math.abs(dz) == 1 then
				-- a corner cut: across, then up or down (the other way round if across is walled)
				local corner = isExit(state, last[1], last[2], x, last[2]) and { x, last[2] } or { last[1], z }
				table.insert(queue, { corner[1], corner[2], fast = true, ease = "in" })
				table.insert(queue, { x, z, fast = true, ease = "out" })
			else                                            -- (moved some other way: it jumps there)
				table.clear(queue)
				ind.x, ind.z = x, z
				ind.from = center(state.maze, x, z)
				ind.to, ind.moveTime = ind.from, 0
				publish(ind)
			end
		end
		if arrived and #queue > 0 then
			local nextCell = table.remove(queue, 1)
			if #queue >= 2 then nextCell.fast = true end    -- (fallen behind him: catching up)
			branch(state, ind, nextCell[1], nextCell[2], now)
			moveTo(state, ind, nextCell[1], nextCell[2], now, nextCell)
		end
		for _, decoy in state.decoys do stepDecoy(state, decoy, now) end
		for _, i in { ind, table.unpack(state.decoys) } do
			i.part.Position = positionOf(i, now) + Vector3.new(0, 0.5, 0)
		end
	end
end

function Encrypt.positions()
	local list = {}
	local now = os.clock()
	for _, state in active do
		table.insert(list, (positionOf(state.real, now)))
		for _, d in state.decoys do table.insert(list, (positionOf(d, now))) end
	end
	return list
end

return Encrypt
