-- Stops your animal walking about while a screen (the welcome screen, the Hat Shop) is open.

local Players = game:GetService("Players")

local Controls = {}

local controls = nil
task.spawn(function()
	local ok, result = pcall(function()
		local module = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 10)
		return (require :: any)(module):GetControls()
	end)
	if ok then
		controls = result
	end
end)

function Controls.set(enabled: boolean)
	if controls then
		if enabled then
			controls:Enable()
		else
			controls:Disable()
		end
	end
end

return Controls
