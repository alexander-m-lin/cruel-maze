-- Finding the character behind a UserId, for players and survivor bots alike. The server publishes
-- who's collecting a relic or being killed as a UserId; a bot has a negative one, and its body is
-- tagged "SurvivorBot" with that id in its "BotUserId" attribute (see SurvivorBot).
--
--   local character = Characters.of(userId)   -- or nil

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local Characters = {}

function Characters.of(userId)
	if typeof(userId) ~= "number" then return nil end
	local player = Players:GetPlayerByUserId(userId)
	if player then return player.Character end
	for _, bot in CollectionService:GetTagged("SurvivorBot") do
		if bot:GetAttribute("BotUserId") == userId then return bot end
	end
	return nil
end

return Characters
