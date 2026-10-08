-- Sends numbers about how the game is played to Roblox's analytics (Creator Dashboard >
-- Analytics), so we can see where new players get to and how coins flow:
--
--   * The onboarding funnel follows new players through their first steps:
--     1 joined, 2 chose an animal, 3 first coin, 4 first hat bought, 5 first home.
--     Each step is only logged the first time a player ever does it (judged from their save),
--     so the funnel shows new players rather than every visit. One exception: "joined" means
--     "has never chosen an animal", so someone who leaves before choosing is counted again
--     next time they join.
--   * Economy events log coins earned (from pickups, and as rewards for goals, daily presents,
--     requests and harvests) and spent (in the shops). Coin pickups are added up for each
--     player and logged together about once a minute (Config.ANALYTICS), and when they leave,
--     so a busy server doesn't send one event per coin. Each reward is still one event.
--   * A "FirstStory" funnel follows new players through the First Story (shared/Goals):
--     1 met Clover, 2 planted, 3 picked, 4 bought a hat, 5 chose an Adventure. Each step is
--     logged once, and only for players who started the story after it came in (Step 16).
--   * A "DailyPresent" funnel counts each day of the seven a player comes back for, and a
--     custom event is logged for each request finished.
--
-- Every call to Roblox is wrapped in pcall, so analytics can never break the game. In Studio
-- each event is also printed to the Output, so you can watch them while testing.

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Sunnyfolk").Config)

local Analytics = {}

Analytics.JOINED = 1
Analytics.CHOSE_ANIMAL = 2
Analytics.FIRST_COIN = 3
Analytics.FIRST_HAT = 4
Analytics.FIRST_HOME = 5

local STEP_NAMES = { "Joined", "Chose an animal", "First coin", "First hat bought", "First home" }
local STORY_NAMES = { "Met Clover", "Planted", "Picked", "Bought a hat", "Chose an adventure" }
local CURRENCY = "Coins"

local IN_STUDIO = RunService:IsStudio()

-- Steps already printed this visit, so each one shows once in the Output.
local seen: { [Player]: { [number]: boolean } } = {}

local function note(text: string)
	if IN_STUDIO then
		print(`Analytics: {text}`)
	end
end

-- A step of the onboarding funnel. `firstTime` is whether the player has never done this
-- before; only then is it logged.
function Analytics.step(player: Player, step: number, firstTime: boolean)
	local mine = seen[player]
	if not mine then
		mine = {}
		seen[player] = mine
	end
	if mine[step] then
		return
	end
	mine[step] = true
	local name = STEP_NAMES[step] or `Step {step}`
	if firstTime then
		pcall(function()
			AnalyticsService:LogOnboardingFunnelStepEvent(player, step, name)
		end)
		note(`{player.Name} funnel step {step}: {name} (logged)`)
	else
		note(`{player.Name} funnel step {step}: {name} (done before, so not logged)`)
	end
end

-- Coins picked up but not logged yet, for each player: how many, and their coins after the
-- last one.
local pickups: { [Player]: { coins: number, balance: number } } = {}

local function logEarned(player: Player, amount: number, balance: number, source: string)
	pcall(function()
		AnalyticsService:LogEconomyEvent(player, Enum.AnalyticsEconomyFlowType.Source, CURRENCY, amount,
			balance, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, source)
	end)
	note(`{player.Name} earned {amount} coin(s) from {source}, now has {balance}`)
end

-- Logs a player's waiting pickups now. Called before any other coin event for them, so the
-- balances in the dashboard stay in order.
local function logPickups(player: Player)
	local waiting = pickups[player]
	if waiting then
		pickups[player] = nil
		logEarned(player, waiting.coins, waiting.balance, "pickup")
	end
end

-- Coins earned. `source` says where from (like "goal:hello"); `balance` is their coins after.
function Analytics.coinsEarned(player: Player, amount: number, balance: number, source: string)
	logPickups(player)
	logEarned(player, amount, balance, source)
end

-- A coin picked up. These are logged together (see the top of this file). `balance` is their
-- coins after this one.
function Analytics.coinPickedUp(player: Player, balance: number)
	local waiting = pickups[player]
	if waiting then
		waiting.coins += 1
		waiting.balance = balance
		return
	end
	local batch = { coins = 1, balance = balance }
	pickups[player] = batch
	task.delay(Config.ANALYTICS.PICKUP_SECONDS, function()
		-- only if these are still waiting (something else may have logged them already)
		if pickups[player] == batch then
			logPickups(player)
		end
	end)
end

-- Step `step` of the First Story funnel (see the top of this file). Each player goes through
-- it once, so their UserId names their trip through it.
function Analytics.storyStep(player: Player, step: number)
	local name = STORY_NAMES[step] or `Step {step}`
	pcall(function()
		AnalyticsService:LogFunnelStepEvent(player, "FirstStory", `story-{player.UserId}`, step, name)
	end)
	note(`{player.Name} First Story step {step}: {name}`)
end

-- A daily present: day `day` (1 to 7) of a round of seven that began on day number `round`.
-- Logged as a funnel, so the dashboard shows how many come back for day 2, day 3 and so on.
function Analytics.dailyPresent(player: Player, day: number, round: number)
	pcall(function()
		AnalyticsService:LogFunnelStepEvent(player, "DailyPresent", `{player.UserId}-{round}`, day, `Day {day}`)
	end)
	note(`{player.Name} daily present: day {day} (round {round})`)
end

-- A request from the board done (`id` from Config.REQUESTS).
function Analytics.requestDone(player: Player, id: string)
	pcall(function()
		AnalyticsService:LogCustomEvent(player, `Request:{id}`)
	end)
	note(`{player.Name} finished the request "{id}"`)
end

-- Coins spent. `sink` says on what (like "hat:beret"); `balance` is their coins after.
function Analytics.coinsSpent(player: Player, amount: number, balance: number, sink: string)
	logPickups(player)
	pcall(function()
		AnalyticsService:LogEconomyEvent(player, Enum.AnalyticsEconomyFlowType.Sink, CURRENCY, amount,
			balance, Enum.AnalyticsEconomyTransactionType.Shop.Name, sink)
	end)
	note(`{player.Name} spent {amount} coins on {sink}, now has {balance}`)
end

Players.PlayerRemoving:Connect(function(player)
	logPickups(player)
	seen[player] = nil
end)

-- When the server shuts down (or Stop is pressed in Studio), log what's still waiting.
game:BindToClose(function()
	for player in pickups do
		logPickups(player)
	end
end)

return Analytics
