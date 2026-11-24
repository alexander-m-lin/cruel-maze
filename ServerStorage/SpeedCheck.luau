-- SERVER-SIDE SPEED CHECK. Players' characters are moved by their own computers (Controls applies
-- the speed rules there), so a tampered client could run faster than allowed. The server watches
-- how far each player's character moves on the ground and pulls back anyone going too fast.
--
--   SpeedCheck.step(dt)              -- every frame (Match)
--   SpeedCheck.moved(player)         -- the server just moved them itself (spawn, door nudge...)
--   SpeedCheck.grant(player, studs)  -- allow this much extra once (a monster's lunge)
--   SpeedCheck.exempt(player, seconds) -- don't check them for a while: the server moves them along
--                                       -- a path it planned itself (the Minotaur's Charge and Crush)
--
-- How: each player has an ALLOWANCE of studs, refilling at their base speed (the "BaseSpeed"
-- attribute, the most the facing rule ever allows) times SLACK, and banking up to BANK seconds'
-- worth plus EXTRA studs. Every SAMPLE seconds the distance they moved is taken out of it. Banking
-- means lag doesn't trip it: a client that stalls and then catches up has saved up while it
-- stalled. Overspend, and they're put back where they last were within the rules (and the
-- "SpeedFlags" attribute on the player counts it, for looking into).
-- Only real players with a character are checked (bots are moved by the server). Height is
-- ignored (falling, stairs). Characters anchored by the server (held in a kill) are skipped.

local Players = game:GetService("Players")
local Config = require(game:GetService("ReplicatedStorage").Config)

local SpeedCheck = {}

local SAMPLE = 0.2       -- seconds between checks
local SLACK = 1.15       -- allowance refills this much faster than the base speed
local BANK = 1.5         -- seconds of movement that can be saved up (lag catch-ups)
local EXTRA = 4          -- studs on top (being bumped, small physics shoves)
local MIN_SPEED = 2      -- studs/s allowed even while frozen (BaseSpeed 0: settling after a spawn)

local STUDIO = game:GetService("RunService"):IsStudio()

local watched = {}       -- [player] = { character, last (Vector3, last good position), allowance, timer }

local function rootOf(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and root and humanoid.Health > 0 then return root end
	return nil
end

local function maxSpeed(player)
	local speed = math.max(MIN_SPEED, player:GetAttribute("BaseSpeed") or Config.PLAYER_SPEED) * SLACK
	speed *= 1 + (player:GetAttribute("ChaseBoost") or 0)      -- a monster player's chase speed
	-- Fear Eater's Living Nightmare: up to this much faster (toward feared survivors)
	if (player:GetAttribute("NightmareUntil") or 0) > workspace:GetServerTimeNow() then
		speed *= 1 + (player:GetAttribute("NightmareBoost") or 0)
	end
	return speed
end

local function cap(player)
	return maxSpeed(player) * BANK + EXTRA
end

local function reset(player, character, root)
	if STUDIO then player:SetAttribute("SpeedResets", (player:GetAttribute("SpeedResets") or 0) + 1) end   -- (for testing)
	watched[player] = { character = character, last = root.Position, allowance = cap(player), timer = 0 }
end

function SpeedCheck.moved(player)
	local character = typeof(player) == "Instance" and player.Character
	local root = rootOf(character)
	if root then reset(player, character, root) end
end

function SpeedCheck.grant(player, studs)
	local w = watched[player]
	if w then w.allowance += studs end
end

function SpeedCheck.exempt(player, seconds)
	local w = watched[player]
	if w then w.exemptUntil = math.max(w.exemptUntil or 0, os.clock() + seconds) end
end

function SpeedCheck.step(dt)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = rootOf(character)
		local w = watched[player]
		if not root or root.Anchored then
			watched[player] = nil
			continue
		end
		if not w or w.character ~= character then      -- a new character: start watching afresh
			reset(player, character, root)
			continue
		end
		if w.exemptUntil then
			if os.clock() < w.exemptUntil then
				w.last, w.timer = root.Position, 0
				continue
			end
			w.exemptUntil = nil
			w.allowance = cap(player)
		end
		w.timer += dt
		if w.timer < SAMPLE then continue end
		local elapsed = w.timer
		w.timer = 0
		w.allowance = math.min(cap(player), w.allowance + maxSpeed(player) * elapsed)
		local moved = ((root.Position - w.last) * Vector3.new(1, 0, 1)).Magnitude
		w.allowance -= moved
		if STUDIO then player:SetAttribute("SpeedAllowance", math.floor(w.allowance * 10) / 10) end   -- (for testing)
		if w.allowance < 0 then
			-- too fast: back to the last good spot (keeping their height and the way they face)
			local back = Vector3.new(w.last.X, root.Position.Y, w.last.Z)
			character:PivotTo(character:GetPivot() + (back - root.Position))
			root.AssemblyLinearVelocity = Vector3.zero
			w.allowance = 0
			player:SetAttribute("SpeedFlags", (player:GetAttribute("SpeedFlags") or 0) + 1)
			warn(("SpeedCheck: %s moved %.1f studs in %.2f s; pulled back"):format(player.Name, moved, elapsed))
		else
			w.last = root.Position
		end
	end
end

Players.PlayerRemoving:Connect(function(player) watched[player] = nil end)

return SpeedCheck
