-- The daily present and the board, "Today in Sunnyfolk" (the numbers and lists are in Config).
--
--   * The present: the first time a player is here on a new day (by the server's clock, in
--     UTC), they get the next day's present of seven: coins, and on day 7 a hat too. Missing a
--     day doesn't start them again. A new player's very first present waits until they've
--     finished the First Story (shared/Goals), so it's a reward for that rather than one more
--     thing on their first screen.
--   * Today's story, on top of the board (Config.TODAY): a resident asks for help with one
--     activity. Each player's story is picked by the day's number from the ones they can do,
--     and not from the resident who asked last time (if someone else can ask). It waits until
--     they've done it: a new day doesn't take it away, and only once it's done does a new one
--     come, on a later day. Like the present, stories start once the First Story is done. The
--     server counts what they do (through Goals.onEvent), even if they haven't read the board
--     yet, and pays its coins and a story stamp once. Reading it on the board is noted for the
--     analytics.
--   * The little helps, underneath: three a day, the same for everyone, picked by the day's
--     number (Config.requestsFor). The server watches for each one itself (through
--     Goals.onEvent, and a once-a-second check for "visit" ones) and pays its coins once.
--     Nothing else needs them.
--
-- A new day is noticed when a player joins, every Config.DAILY.CHECK_SECONDS while they play,
-- and whenever something happens on a day that's moved on. Days only ever go forwards: a
-- server whose clock is a little behind another's never gives a second present or older
-- requests.
--
-- In Studio, the board has a "Next day" button for testing (StudioNextDay). It only
-- works while saving is off (Studio's API access turned off), so a test never writes made-up
-- dates into a real save. Live servers ignore it.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
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
local TODAY = Config.TODAY

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

---------------------------------------------------------------- today's story

-- Can the player do this story's activity now (its `needs`, Config.TODAY)?
local function storyOpen(story: any, data: PlayerData.Data): boolean
	if story.needs == "garden" then
		return GoalList.gardenOpen(data.goalsDone)
	elseif story.needs == "cafe" then
		return data.sun >= Config.CAFE.SUN
	elseif story.needs == "home" then
		return data.home ~= nil
	end
	return true
end

-- Is it time for a new story? Once the First Story is done: when they've none yet, or the one
-- they have was done on an earlier day (so never two in one day).
local function wantsStory(data: PlayerData.Data, today: number): boolean
	if not GoalList.storyDone(data.goalsDone) then
		return false
	end
	local T = data.today
	return T.id == nil or (T.done and today > T.doneDay)
end

-- A new story for the player, picked by the day's number from those they can do, from someone
-- other than who asked last time when there's a choice. Nil if none fits.
local function chooseStory(data: PlayerData.Data, today: number): any
	local last = Config.todayStory(data.today.id)
	local open, others = {}, {}
	for _, story in TODAY.STORIES do
		if storyOpen(story, data) then
			table.insert(open, story)
			if not (last and last.who == story.who) then
				table.insert(others, story)
			end
		end
	end
	local choices = if #others > 0 then others else open
	if #choices == 0 then
		return nil
	end
	return choices[Config.todayPick(today, #choices)]
end

-- Gives the player a new story, if it's time for one.
local function pickStory(player: Player)
	local today = Daily.today()
	local data = PlayerData.get(player)
	if not (data and wantsStory(data, today)) then
		return
	end
	PlayerData.update(player, function(d)
		local story = wantsStory(d, today) and chooseStory(d, today)
		if story then
			d.today.id = story.id
			d.today.day = today
			d.today.got = 0
			d.today.done = false
			d.today.doneDay = 0
			d.today.shown = false
		end
	end)
end

-- Pays for their story, once, if it's all done.
local function finishStory(player: Player)
	local today = Daily.today()
	local story: any, balance: number, day: number = nil, 0, 0
	PlayerData.update(player, function(data)
		local T = data.today
		local mine = Config.todayStory(T.id)
		if not mine or T.done or T.got < mine.need then
			return
		end
		T.done = true
		T.doneDay = today
		T.stamps[mine.id] = (T.stamps[mine.id] or 0) + 1
		data.coins += TODAY.COINS
		story, balance, day = mine, data.coins, T.day
	end)
	if story then
		Analytics.todayStory(player, story.id, day, Analytics.TODAY_FINISHED)
		Analytics.coinsEarned(player, TODAY.COINS, balance, `today:{story.id}`)
		Remotes.TodayDone:FireClient(player, story.id, TODAY.COINS)
	end
end

-- Counts something they did (from Goals.event) towards their story, if it's what it asks for.
local function storyHeard(player: Player, kind: string, what: string?)
	local data = PlayerData.get(player)
	local story = data and Config.todayStory(data.today.id)
	if not (data and story) or data.today.done or story.kind ~= kind or (story.what and story.what ~= what) then
		return
	end
	local first, day = false, 0
	PlayerData.update(player, function(d)
		local T = d.today
		if T.id ~= story.id or T.done then
			return
		end
		first = T.got == 0
		T.got = math.min(T.got + 1, story.need)
		day = T.day
	end)
	if first then
		Analytics.todayStory(player, story.id, day, Analytics.TODAY_STARTED)
	end
	finishStory(player)
end

-- They've read the board: their story has been shown (noted once, for the analytics, unless
-- they've done it already).
local function readBoard(player: Player)
	local data = PlayerData.get(player)
	local story = data and Config.todayStory(data.today.id)
	if not (data and story) or data.today.shown or data.today.done then
		return
	end
	local shown, day = false, 0
	PlayerData.update(player, function(d)
		if d.today.id == story.id and not d.today.shown and not d.today.done then
			d.today.shown = true
			shown, day = true, d.today.day
		end
	end)
	if shown then
		Analytics.todayStory(player, story.id, day, Analytics.TODAY_SHOWN)
	end
end

---------------------------------------------------------------- the present and little helps

-- Gives today's present, if they haven't had it, starts today's little helps, if they're still
-- on an earlier day's, and gives them a new story, if it's time.
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
	-- (a story already done enough, say if Config.TODAY asks for less than it did, is paid now)
	finishStory(player)
	pickStory(player)
end

-- Pays for little help number `slot` (1 to 3) of today's, if it isn't done yet.
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

-- Something happened (from Goals.event) that might count towards their story or today's
-- little helps.
local function heard(player: Player, kind: string, what: string?)
	local data = PlayerData.get(player)
	if data and Daily.today() > data.requests.day then
		newDay(player) -- a new day began since the last look: start its little helps first
	end
	storyHeard(player, kind, what)
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
	Goals.onStoryDone(newDay) -- a new player's first present, and their first story

	-- A new day starting while people play (or a story that's due, say once they can do one).
	task.spawn(function()
		while true do
			task.wait(Config.DAILY.CHECK_SECONDS)
			for _, player in Players:GetPlayers() do
				local data = PlayerData.get(player)
				local today = Daily.today()
				if data and (today > data.daily.last or today > data.requests.day or wantsStory(data, today)) then
					-- (for someone whose first present is waiting, this only starts new little helps)
					newDay(player)
				end
			end
		end
	end)

	-- Reading the board (its prompt is made in server/Town; Roblox checks they're close enough).
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		if prompt.Name == "RequestBoard" then
			readBoard(player)
		end
	end)

	-- "Visit" little helps: once a second, see whether anyone has got there.
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
	Remotes.TodayDone.OnServerEvent:Connect(function() end)
end

return Daily
