-- Homes on the player's side: the "Make this my home" button on free plots, and a
-- "Change my home" button at the door of your own house (only you see that one), and a kind
-- message when someone else is on your saved plot, so your house is on another one this visit.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Workspace = game:GetService("Workspace")

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Sunnyfolk").Config)
local HomeDesigner = require(script.Parent.HomeDesigner)
local Hud = require(script.Parent.Hud)

local player = Players.LocalPlayer
local S = Config.STUDS

local Homes = {}

-- `say(message)` shows a friendly message, like "Welcome home!".
function Homes.start(say: (string) -> ())
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name == "ClaimPlot" then
			local index = prompt:GetAttribute("PlotIndex")
			if typeof(index) == "number" then
				HomeDesigner.open(index, say)
			end
		elseif prompt.Name == "ChangeHome" then
			HomeDesigner.open(nil, say)
		end
	end)

	-- the button at your own front door
	local doorButton: Part? = nil
	local function updateDoor()
		if doorButton then
			doorButton:Destroy()
			doorButton = nil
		end
		local index = player:GetAttribute("HomePlot")
		local plots = Workspace:FindFirstChild("HomePlots")
		local plot = plots and plots:FindFirstChild(`Plot{index}`)
		local at = plot and plot:GetAttribute("Plot")
		if typeof(at) ~= "CFrame" then
			return
		end
		local spot = Instance.new("Part")
		spot.Name = "MyFrontDoor"
		spot.Anchored = true
		spot.CanCollide = false
		spot.CanQuery = false
		spot.CanTouch = false
		spot.Transparency = 1
		spot.Size = Vector3.new(3, 3, 1)
		spot.CFrame = at * CFrame.new(0, 3, 3.6 * S)
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "ChangeHome"
		prompt.ActionText = "Change my home"
		prompt.ObjectText = "Your home"
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Style = Enum.ProximityPromptStyle.Custom
		prompt.Parent = spot
		spot.Parent = Workspace
		doorButton = spot
	end
	player:GetAttributeChangedSignal("HomePlot"):Connect(updateDoor)
	task.spawn(function()
		Workspace:WaitForChild("HomePlots", 30)
		updateDoor()
	end)

	-- Someone's on your saved plot today (server/Homes sets "HomeAway"): say where your house
	-- is instead, once you're playing. Plots have no numbers on them, so it names the pond.
	local told = false
	local function tellIfAway()
		local index = player:GetAttribute("HomePlot")
		local saved = player:GetAttribute("HomeAway")
		if told or typeof(saved) ~= "number" or typeof(index) ~= "number" then
			return
		end
		told = true
		local pondNumber = math.ceil(index / Config.HOME.plotsPerPond)
		local pond = Config.HOME.ponds[pondNumber]
		local name = if pond then pond.name else "the pond"
		local where = if math.ceil(saved / Config.HOME.plotsPerPond) == pondNumber
			then `on another plot at {name}`
			else `at {name}`
		Hud.announce("Someone's living on your plot today!", `So your house is {where} for this visit.`)
	end
	player:GetAttributeChangedSignal("HomeAway"):Connect(tellIfAway)
	tellIfAway()
end

return Homes
