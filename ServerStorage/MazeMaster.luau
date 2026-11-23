-- THE MAZE MASTER's tools, checked and carried out on the server.
--
--   local mm = MazeMaster.new(player, { maze, doors, crushers, objectives, wards })
--     (player = nil for the AI Maze Master, MazeMasterAI, which uses these same tools)
--   mm:Step(dt)                 -- every frame: dark mana refills
--   mm:Use(tool, target)        -- -> ok, message
--   mm:Destroy()
--
-- Each tool has its own cooldown (Config.MAZE_MASTER_TOOLS) and, while Config.DARK_MANA_ENABLED is
-- on, costs DARK MANA (Config.DARK_MANA_MAX, refilling Config.DARK_MANA_REGEN a second):
--   Door       target = door id      open or shut it (that door then rests MAZE_MASTER_DOOR_COOLDOWN s)
--   Ward       target = a position   place a ward (a floating eye, see WardEyes) in that cell
--   FalseRelic target = a position   place a false relic in that cell (FALSE_RELICS_PER_MATCH a match)
--   Crusher    target = crusher id   set off that crushing wall
--
-- The Maze Master's computer follows along through attributes on the player: DarkMana,
-- ToolReady<Tool> (server time each tool is ready again), FalseRelicsLeft.
-- Doors get a "RestUntil" attribute (server time) when the Maze Master changes them, and so do a
-- crushing wall's slabs when it's set off (MAZE_MASTER_CRUSHER_COOLDOWN).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)

local MazeMaster = {}
MazeMaster.__index = MazeMaster

local ATTRIBUTES = { "DarkMana", "ToolReadyDoor", "ToolReadyWard", "ToolReadyFalseRelic",
	"ToolReadyCrusher", "FalseRelicsLeft" }

function MazeMaster.new(player, parts)
	local self = setmetatable({}, MazeMaster)
	self.player = player
	self.maze, self.doors, self.crushers, self.objectives = parts.maze, parts.doors, parts.crushers, parts.objectives
	self.wards = parts.wards
	self.mana = Config.DARK_MANA_MAX
	self.crusherRest = {}        -- [crusher id] = os.clock() when it can be set off again
	self.readyAt = {}            -- [tool] = os.clock() when it can be used again
	self.falseRelicsLeft = Config.FALSE_RELICS_PER_MATCH
	self.active = false          -- the countdown: no tools yet
	self:set("FalseRelicsLeft", self.falseRelicsLeft)
	self:publish()
	return self
end

-- An attribute on the player, for their computer (no player: the AI)
function MazeMaster:set(name, value)
	if self.player and self.player:GetAttribute(name) ~= value then self.player:SetAttribute(name, value) end
end

function MazeMaster:Destroy()
	if self.player and self.player.Parent then
		for _, name in ATTRIBUTES do self.player:SetAttribute(name, nil) end
	end
end

function MazeMaster:publish()
	self:set("DarkMana", Config.DARK_MANA_ENABLED and math.floor(self.mana) or nil)
end

function MazeMaster:Step(dt)
	if not self.active then return end
	self.mana = math.min(Config.DARK_MANA_MAX, self.mana + Config.DARK_MANA_REGEN * dt)
	self:publish()
end

function MazeMaster:Use(tool, target)
	local def = Config.MAZE_MASTER_TOOLS[tool]
	if not def then return false, "" end
	if not self.active then return false, "Not yet" end
	local now = os.clock()
	if now < (self.readyAt[tool] or 0) then return false, "Not ready yet" end
	if Config.DARK_MANA_ENABLED and self.mana < def.cost then return false, "Not enough dark mana" end

	local ok, message = false, ""
	if tool == "Door" then
		local door = typeof(target) == "number" and self.doors.list[target]
		if not door then return false, "" end
		if os.clock() < (door.restUntil or 0) then return false, "That door is resting" end
		if os.clock() < (door.jamUntil or 0) then return false, "That door is jammed (EMP)" end
		ok = self.doors:Request(target, not door.open)
		if ok then
			door.restUntil = os.clock() + Config.MAZE_MASTER_DOOR_COOLDOWN
			door.part:SetAttribute("RestUntil", workspace:GetServerTimeNow() + Config.MAZE_MASTER_DOOR_COOLDOWN)
		else
			message = "That door is already moving"
		end
	elseif tool == "Ward" then
		if typeof(target) ~= "Vector3" then return false, "" end
		local x, z = self.objectives:CellOf(target)
		ok = x ~= nil and self.wards:Add(x, z) ~= nil
		if not ok then message = "Can't place a ward there" end
	elseif tool == "FalseRelic" then
		if self.falseRelicsLeft <= 0 then return false, "No false relics left this match" end
		if typeof(target) ~= "Vector3" then return false, "" end
		local x, z = self.objectives:CellOf(target)
		ok = x ~= nil and self.objectives:AddFalseRelic(x, z) ~= nil
		if ok then
			self.falseRelicsLeft -= 1
			self:set("FalseRelicsLeft", self.falseRelicsLeft)
		else
			message = "Can't place one there"
		end
	elseif tool == "Crusher" then
		if typeof(target) ~= "number" then return false, "" end
		if os.clock() < (self.crusherRest[target] or 0) then return false, "That crushing wall is resting" end
		local jammed = self.crushers.list[target]
		if jammed and os.clock() < (jammed.jamUntil or 0) then return false, "That crushing wall is jammed (EMP)" end
		ok = self.crushers:Trigger(target)
		if ok then
			-- that wall rests (each on its own; the others can still be used)
			self.crusherRest[target] = os.clock() + Config.MAZE_MASTER_CRUSHER_COOLDOWN
			local crusher = self.crushers.list[target]
			for _, slab in crusher and crusher.slabs or {} do
				slab:SetAttribute("RestUntil", workspace:GetServerTimeNow() + Config.MAZE_MASTER_CRUSHER_COOLDOWN)
			end
		else
			message = "That crushing wall is busy"
		end
	end

	if ok then
		if Config.DARK_MANA_ENABLED then self.mana -= def.cost end
		self.readyAt[tool] = now + def.cooldown
		self:set("ToolReady" .. tool, workspace:GetServerTimeNow() + def.cooldown)
		self:publish()
	end
	return ok, message
end

return MazeMaster
