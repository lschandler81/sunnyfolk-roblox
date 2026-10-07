-- Stops your animal walking about while a screen (the welcome screen, the Hat Shop) is open,
-- or while a controller's ring is on the buttons at the top of the screen. Each thing that
-- stops it gives a reason, and walking only comes back once every reason has gone.

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

local stopped: { [string]: boolean } = {}

-- `reason` says what's stopping them ("screen" if not given).
function Controls.set(enabled: boolean, reason: string?)
	if enabled then
		stopped[reason or "screen"] = nil
	else
		stopped[reason or "screen"] = true
	end
	if controls then
		if next(stopped) == nil then
			controls:Enable()
		else
			controls:Disable()
		end
	end
end

return Controls
