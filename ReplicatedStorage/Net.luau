-- Messages between the server and players' computers ("remote events").
--
-- Usage, the same on both sides:
--   local Net = require(game.ReplicatedStorage.Net)
--   local caught = Net.event("Caught")
--   caught:FireClient(player, ...)         -- server -> one player
--   caught.OnClientEvent:Connect(fn)       -- on the player's computer
--
-- The server creates each RemoteEvent the first time it's asked for; players' computers wait
-- for it to appear. Every event a client can send to the server must be checked on the server
-- (who sent it, is it allowed now, are the values sensible) - never trust the client.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}

local folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = ReplicatedStorage
else
	folder = ReplicatedStorage:WaitForChild("Remotes")
end

function Net.event(name: string): RemoteEvent
	if RunService:IsServer() then
		local event = folder:FindFirstChild(name)
		if not event then
			event = Instance.new("RemoteEvent")
			event.Name = name
			event.Parent = folder
		end
		return event
	end
	return folder:WaitForChild(name)
end

return Net
