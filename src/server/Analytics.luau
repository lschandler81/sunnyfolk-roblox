-- Sends numbers about how the game is played to Roblox's analytics (Creator Dashboard >
-- Analytics), so we can see where new players get to and how coins flow:
--
--   * The onboarding funnel follows new players through their first steps:
--     1 joined, 2 chose an animal, 3 first coin, 4 first hat bought, 5 first home.
--     Each step is only logged the first time a player ever does it (judged from their save),
--     so the funnel shows new players rather than every visit. One exception: "joined" means
--     "has never chosen an animal", so someone who leaves before choosing is counted again
--     next time they join.
--   * Economy events log coins earned (from pickups, and as rewards for goals, daily presents
--     and requests) and spent (on hats).
--   * A "DailyPresent" funnel counts each day of the seven a player comes back for, and a
--     custom event is logged for each request finished.
--
-- Every call to Roblox is wrapped in pcall, so analytics can never break the game. In Studio
-- each event is also printed to the Output, so you can watch them while testing.

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Analytics = {}

Analytics.JOINED = 1
Analytics.CHOSE_ANIMAL = 2
Analytics.FIRST_COIN = 3
Analytics.FIRST_HAT = 4
Analytics.FIRST_HOME = 5

local STEP_NAMES = { "Joined", "Chose an animal", "First coin", "First hat bought", "First home" }
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

-- Coins earned. `source` says where from (like "pickup"); `balance` is their coins after.
function Analytics.coinsEarned(player: Player, amount: number, balance: number, source: string)
	pcall(function()
		AnalyticsService:LogEconomyEvent(player, Enum.AnalyticsEconomyFlowType.Source, CURRENCY, amount,
			balance, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, source)
	end)
	note(`{player.Name} earned {amount} coin(s) from {source}, now has {balance}`)
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
	pcall(function()
		AnalyticsService:LogEconomyEvent(player, Enum.AnalyticsEconomyFlowType.Sink, CURRENCY, amount,
			balance, Enum.AnalyticsEconomyTransactionType.Shop.Name, sink)
	end)
	note(`{player.Name} spent {amount} coins on {sink}, now has {balance}`)
end

Players.PlayerRemoving:Connect(function(player)
	seen[player] = nil
end)

return Analytics
