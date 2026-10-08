-- Players' homes at Home Pond and Lily Pond (Config.HOME). Each free plot has a "Free plot"
-- sign: press it to design your house (client/HomeDesigner), and the server builds it there.
-- Your design and favourite plot are saved, so next time you move straight back in (to the
-- same plot if it's free, or the nearest free one). When you leave, your plot is free for
-- someone else.
--
-- If your saved plot is taken when you come back, your house goes on the nearest free plot
-- just for this visit: your "HomeAway" attribute is set to your saved plot, so your screen can
-- tell you (client/Homes), and your saved plot stays the same unless you choose a new one.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Build = require(Shared.Build)
local Config = require(Shared.Config)
local Houses = require(Shared.Houses)
local Analytics = require(script.Parent.Analytics)
local Goals = require(script.Parent.Goals)
local PlayerData = require(script.Parent.PlayerData)
local RemoteGuard = require(script.Parent.RemoteGuard)

local Remotes = Shared:WaitForChild("Remotes")

local S = Config.STUDS
local C = Build.C

local Homes = {}

type Plot = { index: number, cframe: CFrame, model: Model, sign: Model, owner: Player? }
local plots: { Plot } = {}
local plotOf: { [Player]: number } = {}
-- Players living away from their saved plot this visit, and that saved plot.
local awayFrom: { [Player]: number } = {}

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

-- Which pond a plot is round (1 for Home Pond, 2 for Lily Pond).
local function pondOf(index: number): number
	return math.ceil(index / Config.HOME.plotsPerPond)
end

-- The plot to move a returning player into: their old one if it's free, or the free one
-- nearest to it, at the same pond if there's room there.
local function plotFor(wanted: number?): number?
	local from = if wanted and plots[wanted] then plots[wanted].cframe.Position else nil
	local best, bestGap = nil, math.huge
	for _, plot in plots do
		if not plot.owner then
			local gap = plot.index
			if wanted and from then
				-- another pond counts as further than anywhere at their own pond
				local otherPond = if pondOf(plot.index) == pondOf(wanted) then 0 else 100000
				gap = (plot.cframe.Position - from).Magnitude + otherPond
			end
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
			if index ~= home.plot and plots[home.plot] then
				awayFrom[player] = home.plot
				player:SetAttribute("HomeAway", home.plot)
			end
		end
	end)

	-- Moving in, and changing your house.
	local lastBuilt: { [Player]: number } = {}
	Remotes.SetHome.OnServerInvoke = function(player, plotIndex, design)
		if not RemoteGuard.allow(player, "SetHome") then
			return false, "Just a moment!"
		end
		if os.clock() - (lastBuilt[player] or 0) < 2 then
			return false, "Just a moment!"
		end
		local checked = Houses.check(design)
		if not (checked and PlayerData.get(player)) then
			return false, "Something went wrong. Please try again."
		end
		local index = plotOf[player]
		local moving = false
		if typeof(plotIndex) == "number" and plotIndex ~= index then
			local plot = plots[plotIndex]
			if not plot then
				return false, "That plot isn't there."
			end
			if plot.owner then
				return false, "Someone's just moved in there! Try another free plot."
			end
			index = plotIndex
			moving = true
		end
		if not index then
			return false, "Find a free plot at Home Pond or Lily Pond first."
		end
		lastBuilt[player] = os.clock()
		moveIn(player, index, checked)
		-- choosing a new plot makes it your saved one; changing your house on a plot you're
		-- only borrowing this visit keeps your saved plot
		if moving then
			awayFrom[player] = nil
			player:SetAttribute("HomeAway", nil)
		end
		local savedPlot = awayFrom[player] or index
		local changed, firstTime = false, false
		PlayerData.update(player, function(data)
			changed, firstTime = true, data.home == nil
			data.home = { design = checked, plot = savedPlot }
		end)
		if changed then
			Analytics.step(player, Analytics.FIRST_HOME, firstTime)
			Goals.event(player, "home")
		end
		return true
	end

	Players.PlayerRemoving:Connect(function(player)
		lastBuilt[player] = nil
		awayFrom[player] = nil
		local index = plotOf[player]
		if index then
			release(index)
		end
	end)
end

return Homes
