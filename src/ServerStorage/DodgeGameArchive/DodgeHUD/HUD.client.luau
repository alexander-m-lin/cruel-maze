-- Shows the player's survival time at the top of the screen.
local player = game:GetService("Players").LocalPlayer
local label = script.Parent:WaitForChild("TimerLabel")

local stats = player:WaitForChild("leaderstats")
local current = stats:WaitForChild("Time")
local best = stats:WaitForChild("Best")

local function refresh()
	label.Text = ("Survived: %ds   |   Best: %ds"):format(current.Value, best.Value)
end
current.Changed:Connect(refresh)
best.Changed:Connect(refresh)
refresh()
