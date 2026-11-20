-- Who gets the developer controls (the Role / New match / Doors panels): everyone in Studio, and in
-- the published game the experience's owner (the owning user, or a group's owner rank), plus any
-- UserIds in Config.DEV_USER_IDS. Checked here on the server; players' computers only read the
-- "Dev" attribute it sets on each player, to know whether to show the panels.
--
--   Dev.isDev(player)   -- (bots: false)

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Config = require(game:GetService("ReplicatedStorage").Config)

local Dev = {}
local cache = {}

function Dev.isDev(player)
	if typeof(player) ~= "Instance" then return false end
	if RunService:IsStudio() then return true end
	if cache[player] ~= nil then return cache[player] end
	local dev = table.find(Config.DEV_USER_IDS, player.UserId) ~= nil
	if game.CreatorType == Enum.CreatorType.User then
		dev = dev or player.UserId == game.CreatorId
	elseif game.CreatorType == Enum.CreatorType.Group then
		local ok, rank = pcall(player.GetRankInGroup, player, game.CreatorId)
		dev = dev or (ok and rank >= 255)
	end
	cache[player] = dev
	return dev
end

Players.PlayerRemoving:Connect(function(player) cache[player] = nil end)

return Dev
