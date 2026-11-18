-- Tracks how long each player has survived (Time) and their record (Best).
-- These show up in the player list because they're inside "leaderstats".

local Players = game:GetService("Players")

Players.PlayerAdded:Connect(function(player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	stats.Parent = player

	local current = Instance.new("IntValue")
	current.Name = "Time"
	current.Parent = stats

	local best = Instance.new("IntValue")
	best.Name = "Best"
	best.Parent = stats

	player.CharacterAdded:Connect(function(character)
		current.Value = 0
		local humanoid = character:WaitForChild("Humanoid")
		local alive = true
		humanoid.Died:Connect(function() alive = false end)

		while alive and character.Parent do
			task.wait(1)
			if not alive then break end
			current.Value += 1
			if current.Value > best.Value then
				best.Value = current.Value
			end
		end
	end)
end)
