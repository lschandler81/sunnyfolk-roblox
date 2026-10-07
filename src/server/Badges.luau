-- Badges, given with Roblox's BadgeService (the ids are in Config.BADGES):
--   chooseAnimal  chose an animal for the first time
--   firstHat      got a first hat
--   firstHome     made a first home
--   coins         earned Config.BADGE_COINS coins in all
--   week          got the day 7 present
--   allGoals      finished all the goals
--
-- Everything is decided from the player's own save, on the server: whenever one of their
-- numbers changes (the attributes PlayerData sets, which only the server can change), and
-- when they join, so anyone who'd already done something before badges existed gets it too.
-- Each badge is only asked for once per visit, and never if they've already got it (if Roblox
-- couldn't give it, it's asked for again, but not more than once a minute). A badge whose id
-- is still 0 is skipped (in Studio, the Output says when it would have been given).
--
-- The "week" badge is given while the day 7 present is the latest one (until the next
-- present starts the seven days again), so anyone who reached day 7 before badges existed
-- gets it the next time they reach day 7.

local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Config = require(Shared.Config)
local GoalList = require(Shared.Goals)
local PlayerData = require(script.Parent.PlayerData)

local IN_STUDIO = RunService:IsStudio()

-- When each badge is earned, from the player's save.
local EARNED: { [string]: (PlayerData.Data) -> boolean } = {
	chooseAnimal = function(data)
		return data.look ~= nil
	end,
	firstHat = function(data)
		return #data.hats > 0
	end,
	firstHome = function(data)
		return data.home ~= nil
	end,
	coins = function(data)
		return data.earned >= Config.BADGE_COINS
	end,
	week = function(data)
		return data.daily.streak >= #Config.DAILY.COINS
	end,
	allGoals = function(data)
		return GoalList.done(data.goal)
	end,
}

-- The attributes whose changes might mean a new badge.
local WATCH = { "Look", "OwnedHats", "HomeDesign", "Coins", "DailyStreak", "Goal" }

local Badges = {}

-- Badges already asked for (or already owned) this visit: asked[player][key]
local asked: { [Player]: { [string]: boolean } } = {}
-- When Roblox last couldn't give one: failedAt[player][key] = os.clock()
local failedAt: { [Player]: { [string]: number } } = {}
local watching: { [Player]: { RBXScriptConnection } } = {}

local function give(player: Player, key: string)
	local id = Config.BADGES[key]
	if id == 0 then
		if IN_STUDIO then
			print(`Badges: {player.Name} would get the "{key}" badge (its id in Config.BADGES is still 0)`)
		end
		return
	end
	local checked, has = pcall(function()
		return BadgeService:UserHasBadgeAsync(player.UserId, id)
	end)
	if checked and has then
		return
	end
	local ok, result = pcall(function()
		return BadgeService:AwardBadge(player.UserId, id)
	end)
	if ok and result == true then
		if IN_STUDIO then
			print(`Badges: gave {player.Name} the "{key}" badge`)
		end
	else
		warn(`Badges: couldn't give {player.Name} the "{key}" badge: {if ok then "Roblox said no" else result}`)
		local mine, failed = asked[player], failedAt[player]
		if mine and failed then
			mine[key] = nil -- try again later (see Badges.check)
			failed[key] = os.clock()
		end
	end
end

-- Gives any badges they've earned but haven't been given yet.
function Badges.check(player: Player)
	local data = PlayerData.get(player)
	if not (data and player.Parent) then
		return
	end
	local mine = asked[player]
	if not mine then
		mine = {}
		asked[player] = mine
		failedAt[player] = {}
	end
	local failed = failedAt[player]
	for key, earned in EARNED do
		local waiting = failed[key] and os.clock() - failed[key] < Config.BADGE_RETRY_SECONDS
		if not mine[key] and not waiting and earned(data) then
			mine[key] = true
			task.spawn(give, player, key)
		end
	end
end

function Badges.start()
	PlayerData.onLoaded(function(player)
		if not player.Parent then
			return
		end
		local connections = {}
		for _, attribute in WATCH do
			table.insert(connections, player:GetAttributeChangedSignal(attribute):Connect(function()
				Badges.check(player)
			end))
		end
		watching[player] = connections
		Badges.check(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local connections = watching[player]
		if connections then
			for _, connection in connections do
				connection:Disconnect()
			end
		end
		watching[player] = nil
		asked[player] = nil
		failedAt[player] = nil
	end)
end

return Badges
