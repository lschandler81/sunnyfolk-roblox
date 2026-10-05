-- Players' homes at Home Pond. Each free plot has a "Free plot" sign: press it to design your
-- house (client/HomeDesigner), and the server builds it there. Your design and favourite plot
-- are saved, so next time you move straight back in (to the same plot if it's free, or the
-- next free one). When you leave, your plot is free for someone else.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Build = require(Shared.Build)
local Config = require(Shared.Config)
local Houses = require(Shared.Houses)
local PlayerData = require(script.Parent.PlayerData)

local Remotes = Shared:WaitForChild("Remotes")

local S = Config.STUDS
local C = Build.C

local Homes = {}

type Plot = { index: number, cframe: CFrame, model: Model, sign: Model, owner: Player? }
local plots: { Plot } = {}
local plotOf: { [Player]: number } = {}

-- The "Free plot" sign, with the button to move in.
local function freeSign(plot: Plot): Model
	local sign = Instance.new("Model")
	sign.Name = "FreeSign"
	Build.into(sign)
	local at = plot.cframe * CFrame.new(0, 0, 1.5 * S) -- in the middle of the empty plot
	Build.cylinder(0.1 * S, 1.8 * S, at * CFrame.new(0, 0.9 * S, 0), C.woodDark)
	local board = Build.block(Vector3.new(2.6, 0.8, 0.12) * S, at * CFrame.new(0, 1.75 * S, 0.1 * S) * CFrame.Angles(0, math.pi, 0), C.yellow)
	Build.label(board, "Free plot!", C.ink, C.yellow)
	Build.label(board, "Free plot!", C.ink, C.yellow, Enum.NormalId.Back)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ClaimPlot"
	prompt.ActionText = "Make this my home"
	prompt.ObjectText = "Free plot"
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Custom -- shown at the bottom of the screen
	prompt:SetAttribute("PlotIndex", plot.index)
	prompt.Parent = board
	return sign
end

local function release(index: number)
	local plot = plots[index]
	if not plot then
		return
	end
	local house = plot.model:FindFirstChild("House")
	if house then
		house:Destroy()
	end
	if plot.owner then
		plotOf[plot.owner] = nil
		plot.owner:SetAttribute("HomePlot", nil)
	end
	plot.owner = nil
	plot.model:SetAttribute("OwnerId", nil)
	plot.sign.Parent = plot.model
end

-- Builds `player`'s house on a plot (replacing what was there).
local function moveIn(player: Player, index: number, design: Houses.Design)
	local plot = plots[index]
	local old = plotOf[player]
	if old and old ~= index then
		release(old)
	end
	local previous = plot.model:FindFirstChild("House")
	if previous then
		previous:Destroy()
	end
	local house = Instance.new("Model")
	house.Name = "House"
	Build.into(house)
	Houses.build(design, plot.cframe, player.DisplayName)
	house.Parent = plot.model

	plot.owner = player
	plotOf[player] = index
	plot.sign.Parent = nil
	plot.model:SetAttribute("OwnerId", player.UserId)
	player:SetAttribute("HomePlot", index)
end

-- The plot to move a returning player into: their old one if it's free, or the nearest free.
local function plotFor(wanted: number?): number?
	local best, bestGap = nil, math.huge
	for _, plot in plots do
		if not plot.owner then
			local gap = if wanted then math.abs(plot.index - wanted) else plot.index
			if gap < bestGap then
				best, bestGap = plot.index, gap
			end
		end
	end
	return best
end

function Homes.start(plotFrames: { CFrame })
	local folder = Instance.new("Folder")
	folder.Name = "HomePlots"
	folder.Parent = Workspace
	for index, cframe in plotFrames do
		local model = Instance.new("Model")
		model.Name = `Plot{index}`
		model:SetAttribute("PlotIndex", index)
		model:SetAttribute("Plot", cframe)
		model.Parent = folder
		local plot: Plot = { index = index, cframe = cframe, model = model, sign = nil :: any, owner = nil }
		plot.sign = freeSign(plot)
		plot.sign.Parent = model
		plots[index] = plot
	end

	-- Move returning players back in.
	PlayerData.onLoaded(function(player)
		local data = PlayerData.get(player)
		local home = data and data.home
		if not home then
			return
		end
		local index = plotFor(home.plot)
		if index and player.Parent then
			moveIn(player, index, home.design)
		end
	end)

	-- Moving in, and changing your house.
	local lastBuilt: { [Player]: number } = {}
	Remotes.SetHome.OnServerInvoke = function(player, plotIndex, design)
		if os.clock() - (lastBuilt[player] or 0) < 2 then
			return false, "Just a moment!"
		end
		local checked = Houses.check(design)
		if not (checked and PlayerData.get(player)) then
			return false, "Something went wrong. Please try again."
		end
		local index = plotOf[player]
		if typeof(plotIndex) == "number" and plotIndex ~= index then
			local plot = plots[plotIndex]
			if not plot then
				return false, "That plot isn't there."
			end
			if plot.owner then
				return false, "Someone's just moved in there! Try another free plot."
			end
			index = plotIndex
		end
		if not index then
			return false, "Find a free plot at Home Pond first."
		end
		lastBuilt[player] = os.clock()
		moveIn(player, index, checked)
		PlayerData.update(player, function(data)
			data.home = { design = checked, plot = index }
		end)
		return true
	end

	Players.PlayerRemoving:Connect(function(player)
		lastBuilt[player] = nil
		local index = plotOf[player]
		if index then
			release(index)
		end
	end)
end

return Homes
