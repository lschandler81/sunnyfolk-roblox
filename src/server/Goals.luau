-- The goals that lead a new player round town (the list is in shared/Goals). The server
-- watches for each one itself: other scripts tell it when a player talks to someone, picks up
-- a coin, opens the Hat Shop, buys a hat or makes a home, and it checks where players are for
-- "visit" goals. Nothing a player's computer says can finish a goal. Each goal pays its coins
-- and sunshine once, progress is saved in PlayerData, and the player's screen is told so it
-- can say "Well done!".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Config = require(Shared.Config)
local GoalList = require(Shared.Goals)
local Analytics = require(script.Parent.Analytics)
local PlayerData = require(script.Parent.PlayerData)

local Remotes = Shared:WaitForChild("Remotes")

local S = Config.STUDS
local LIST = GoalList.LIST
local CHECK_SECONDS = 1 -- how often "visit" goals look where players are
local NEXT_SECONDS = 3.5 -- a pause before a goal that's already done ticks itself, so messages don't overlap

local Goals = {}

local settle: (Player) -> ()

-- Pays for the goal they're on and moves them to the next one.
local function complete(player: Player)
	local goal: GoalList.Goal? = nil
	local finished, balance = false, 0
	PlayerData.update(player, function(data)
		goal = LIST[data.goal]
		if not goal then
			return
		end
		data.coins += goal.coins
		data.sun += goal.sun
		data.goal += 1
		data.goalCount = 0
		data.goalMet = {}
		if GoalList.done(data.goal) then
			finished = true
			data.coins += GoalList.FINISH.coins
			data.sun += GoalList.FINISH.sun
		end
		balance = data.coins
	end)
	if not goal then
		return
	end
	local done = goal :: GoalList.Goal
	if finished then
		Analytics.coinsEarned(player, done.coins, balance - GoalList.FINISH.coins, `goal:{done.id}`)
		Analytics.coinsEarned(player, GoalList.FINISH.coins, balance, "goal:finish")
	else
		Analytics.coinsEarned(player, done.coins, balance, `goal:{done.id}`)
	end
	Remotes.GoalDone:FireClient(player, done.id, done.coins, done.sun, finished)
	task.delay(NEXT_SECONDS, settle, player)
end

-- Ticks the goal they're on if they've already done it (they had a hat, or a home, before
-- they got to that goal).
settle = function(player: Player)
	local data = PlayerData.get(player)
	local goal = data and LIST[data.goal]
	if not (data and goal and player.Parent) then
		return
	end
	if (goal.kind == "hat" and #data.hats > 0) or (goal.kind == "home" and data.home ~= nil) then
		complete(player)
	end
end

-- Something happened that might finish a goal. `kind` is one of the kinds in shared/Goals;
-- `what` says which resident, for "talk".
function Goals.event(player: Player, kind: string, what: string?)
	local data = PlayerData.get(player)
	local goal = data and LIST[data.goal]
	if not (data and goal and goal.kind == kind) then
		return
	end
	if kind == "talk" then
		local who = goal.who or {}
		if not (what and table.find(who, what)) or table.find(data.goalMet, what) then
			return
		end
		local met = 0
		PlayerData.update(player, function(d)
			table.insert(d.goalMet, what :: string)
			met = GoalList.metCount(goal, d.goalMet)
		end)
		if met >= #who then
			complete(player)
		end
	elseif kind == "coin" then
		local got = 0
		PlayerData.update(player, function(d)
			d.goalCount += 1
			got = d.goalCount
		end)
		if got >= (goal.need or 1) then
			complete(player)
		end
	else
		complete(player)
	end
end

function Goals.start()
	-- GoalDone only goes from the server to players; anything a player sends on it is ignored.
	Remotes.GoalDone.OnServerEvent:Connect(function() end)

	-- A returning player may already have done the goal they're on.
	PlayerData.onLoaded(function(player)
		task.delay(NEXT_SECONDS, settle, player)
	end)

	-- "Visit" goals: once a second, see whether anyone on one has got there.
	task.spawn(function()
		while true do
			task.wait(CHECK_SECONDS)
			for _, player in Players:GetPlayers() do
				local data = PlayerData.get(player)
				local goal = data and LIST[data.goal]
				local root = player.Character and player.Character.PrimaryPart
				if goal and goal.kind == "visit" and goal.at and root then
					local gap = root.Position - goal.at
					if Vector3.new(gap.X, 0, gap.Z).Magnitude < GoalList.VISIT_RADIUS * S then
						Goals.event(player, "visit")
					end
				end
			end
		end
	end)
end

return Goals
