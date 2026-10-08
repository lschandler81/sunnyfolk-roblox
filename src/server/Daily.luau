-- The daily present and the request board (numbers and the list of requests are in Config).
--
--   * The present: the first time a player is here on a new day (by the server's clock, in
--     UTC), they get the next day's present of seven: coins, and on day 7 a hat too. Missing a
--     day doesn't start them again. A new player's very first present waits until they've
--     finished the First Story (shared/Goals), so it's a reward for that rather than one more
--     thing on their first screen.
--   * The request board: three requests a day, the same for everyone, picked by the day's
--     number (Config.requestsFor). The server watches for each one itself (through
--     Goals.onEvent, and a once-a-second check for "visit" requests) and pays its coins once.
--
-- A new day is noticed when a player joins, every Config.DAILY.CHECK_SECONDS while they play,
-- and whenever something happens on a day that's moved on. Days only ever go forwards: a
-- server whose clock is a little behind another's never gives a second present or older
-- requests.
--
-- In Studio, the Request Board has a "Next day" button for testing (StudioNextDay). It only
-- works while saving is off (Studio's API access turned off), so a test never writes made-up
-- dates into a real save. Live servers ignore it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Config = require(Shared.Config)
local GoalList = require(Shared.Goals)
local Looks = require(Shared.Looks)
local Analytics = require(script.Parent.Analytics)
local Goals = require(script.Parent.Goals)
local PlayerData = require(script.Parent.PlayerData)
local RemoteGuard = require(script.Parent.RemoteGuard)

local Remotes = Shared:WaitForChild("Remotes")

local S = Config.STUDS
local IN_STUDIO = RunService:IsStudio()
local SECONDS_A_DAY = 24 * 60 * 60
local VISIT_CHECK_SECONDS = 1

local Daily = {}

local studioDays = 0 -- days added by the Studio "Next day" button

-- Today's number: days since 1 January 1970, by the server's clock (UTC).
function Daily.today(): number
	return math.floor(os.time() / SECONDS_A_DAY) + studioDays
end

-- The cheapest hat from Clover's shop that the player hasn't got, or nil if they've got them all.
local function giftHat(owned: { string }): any
	for _, hat in Looks.shopHats() do
		if not table.find(owned, hat.id) then
			return hat
		end
	end
	return nil
end

local finish: (Player, number) -> ()

-- A "buy a hat" request can't be done by someone who's already got every hat in the shop,
-- so for them it counts as done.
local function settleHats(player: Player)
	local data = PlayerData.get(player)
	if not data or giftHat(data.hats) ~= nil then
		return
	end
	for slot, index in Config.requestsFor(data.requests.day) do
		if Config.REQUESTS[index].kind == "hat" and not data.requests.done[slot] then
			finish(player, slot)
		end
	end
end

-- Gives today's present, if they haven't had it, and starts today's requests, if they're
-- still on an earlier day's.
local function newDay(player: Player)
	local today = Daily.today()
	local present: { day: number, coins: number, hat: string? }? = nil
	local round, balance = 0, 0
	PlayerData.update(player, function(data)
		-- (only new players: old saves from before presents existed have no streak either)
		local waiting = data.newStory and data.daily.streak == 0 and not GoalList.storyDone(data.goalsDone)
		if today > data.daily.last and not waiting then
			local day = data.daily.streak % #Config.DAILY.COINS + 1
			if day == 1 then
				data.daily.start = today
			end
			local coins = Config.DAILY.COINS[day]
			local hatName: string? = nil
			if day == #Config.DAILY.COINS then
				local hat = giftHat(data.hats)
				if hat then
					table.insert(data.hats, hat.id)
					hatName = hat.name
				else
					coins += Config.DAILY.ALL_HATS_COINS
				end
			end
			data.coins += coins
			data.daily.last = today
			data.daily.streak = day
			present = { day = day, coins = coins, hat = hatName }
			round, balance = data.daily.start, data.coins
		end
		if today > data.requests.day then
			data.requests = { day = today, got = {}, done = {} }
			for i = 1, Config.REQUESTS_PER_DAY do
				data.requests.got[i] = 0
				data.requests.done[i] = false
			end
		end
	end)
	local gift = present
	if gift then
		Analytics.dailyPresent(player, gift.day, round)
		Analytics.coinsEarned(player, gift.coins, balance, `daily:{gift.day}`)
		Remotes.DailyPresent:FireClient(player, gift.day, gift.coins, gift.hat)
	end
	settleHats(player)
end

-- Pays for request number `slot` (1 to 3) of today's, if it isn't done yet.
finish = function(player: Player, slot: number)
	local request: any = nil
	local balance = 0
	PlayerData.update(player, function(data)
		if data.requests.done[slot] then
			return
		end
		request = Config.REQUESTS[Config.requestsFor(data.requests.day)[slot]]
		if not request then
			return
		end
		data.requests.done[slot] = true
		data.coins += request.coins
		balance = data.coins
	end)
	if request then
		Analytics.requestDone(player, request.id)
		Analytics.coinsEarned(player, request.coins, balance, `request:{request.id}`)
		Remotes.RequestDone:FireClient(player, request.text, request.coins)
	end
end

-- Something happened (from Goals.event) that might count towards today's requests.
local function heard(player: Player, kind: string, what: string?)
	local data = PlayerData.get(player)
	if data and Daily.today() > data.requests.day then
		newDay(player) -- a new day began since the last look: start its requests first
	end
	if not data or data.requests.day ~= Daily.today() then
		return
	end
	for slot, index in Config.requestsFor(data.requests.day) do
		local request = Config.REQUESTS[index]
		if data.requests.done[slot] or request.kind ~= kind or kind == "visit" then
			continue
		end
		if kind == "talk" and request.who ~= what then
			continue
		end
		local got = 0
		PlayerData.update(player, function(d)
			d.requests.got[slot] = (d.requests.got[slot] or 0) + 1
			got = d.requests.got[slot]
		end)
		if got >= (request.need or 1) then
			finish(player, slot)
		end
	end
end

function Daily.start()
	PlayerData.onLoaded(newDay)
	Goals.onEvent(heard)
	Goals.onStoryDone(newDay) -- a new player's first present

	-- A new day starting while people play.
	task.spawn(function()
		while true do
			task.wait(Config.DAILY.CHECK_SECONDS)
			for _, player in Players:GetPlayers() do
				local data = PlayerData.get(player)
				if data and (Daily.today() > data.daily.last or Daily.today() > data.requests.day) then
					-- (for someone whose first present is waiting, this only starts new requests)
					newDay(player)
				end
			end
		end
	end)

	-- "Visit" requests: once a second, see whether anyone has got there.
	task.spawn(function()
		while true do
			task.wait(VISIT_CHECK_SECONDS)
			for _, player in Players:GetPlayers() do
				local data = PlayerData.get(player)
				local root = player.Character and player.Character.PrimaryPart
				if data and Daily.today() > data.requests.day then
					newDay(player)
				end
				if not (data and root) or data.requests.day ~= Daily.today() then
					continue
				end
				for slot, index in Config.requestsFor(data.requests.day) do
					local request = Config.REQUESTS[index]
					local spot = request.kind == "visit" and Config.requestSpot(request)
					if spot and not data.requests.done[slot] then
						local radius = if request.pond then Config.HOME.ringR + Config.REQUEST_POND_EXTRA else Config.REQUEST_VISIT_RADIUS
						local gap = root.Position - spot
						if Vector3.new(gap.X, 0, gap.Z).Magnitude < radius * S then
							finish(player, slot)
						end
					end
				end
			end
		end
	end)

	-- Studio only: pretend it's tomorrow, for testing. Live servers ignore this, and so does
	-- Studio while anyone's game is being saved (so made-up dates never reach a real save).
	Remotes.StudioNextDay.OnServerEvent:Connect(function(player)
		if not IN_STUDIO or not RemoteGuard.allow(player, "StudioNextDay") then
			return
		end
		for _, other in Players:GetPlayers() do
			if other:GetAttribute("Saving") ~= false then
				warn("Daily: \"Next day\" only works while saving is off. Turn off Game Settings > Security >"
					.. " Enable Studio Access to API Services, then Play again.")
				return
			end
		end
		studioDays += 1
		print(`Daily: Studio test, it's now day {Daily.today()} ({studioDays} day(s) ahead)`)
		for _, other in Players:GetPlayers() do
			newDay(other)
		end
	end)
	-- These only go from the server to players; anything a player sends on them is ignored.
	Remotes.DailyPresent.OnServerEvent:Connect(function() end)
	Remotes.RequestDone.OnServerEvent:Connect(function() end)
end

return Daily
