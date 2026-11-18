-- Shows a live run timer and round announcements.
local RunService = game:GetService("RunService")
local player = game:GetService("Players").LocalPlayer
local gui = script.Parent
local timerLabel = gui:WaitForChild("TimerLabel")
local announceLabel = gui:WaitForChild("AnnounceLabel")

-- Live timer: runs every frame
RunService.RenderStepped:Connect(function()
	local start = player:GetAttribute("RunStart")
	if start then
		timerLabel.Text = ("Time: %.1fs"):format(workspace:GetServerTimeNow() - start)
	end
end)

-- Announcements from the server
local announcement = game:GetService("ReplicatedStorage"):WaitForChild("Announcement")
local function show()
	announceLabel.Text = announcement.Value
	announceLabel.Visible = announcement.Value ~= ""
end
announcement.Changed:Connect(show)
show()
