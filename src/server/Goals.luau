-- The goals: the First Story, then the Adventures a player chooses (the lists are in
-- shared/Goals). The server watches for each one itself: other scripts tell it when a player
-- talks to someone, opens a shop, buys a hat, makes a home, adopts a pet, plants and picks
-- in the Garden, finishes a Cafe shift, catches a fish or tidies the library's shelves, and it
-- checks where players are for "visit" goals. Nothing a player's computer says can finish a
-- goal; all it can do is choose which Adventure to do next (ChooseAdventure).
-- Each goal pays its coins and sunshine once, the ids of finished goals are saved in
-- PlayerData, and the player's screen is told so it can say "Well done!".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Config = require(Shared.Config)
local GoalList = require(Shared.Goals)
local Analytics = require(script.Parent.Analytics)
local PlayerData = require(script.Parent.PlayerData)
local RemoteGuard = require(script.Parent.RemoteGuard)

local Remotes = Shared:WaitForChild("Remotes")

local S = Config.STUDS
local CHECK_SECONDS = 1 -- how often "visit" goals look where players are
local NEXT_SECONDS = 3.5 -- a pause before a goal that's already done ticks itself, so messages don't overlap

local Goals = {}

local settle: (Player) -> ()

-- Those who want to know when a player finishes the First Story (server/Daily).
local storyListeners: { (Player) -> () } = {}

-- Pays for `goal` and marks it done, if it's still the goal they're on.
local function complete(player: Player, goal: GoalList.Goal)
	local paid, storyNow, finished, bonus, balance, newStory = false, false, false, false, 0, false
	PlayerData.update(player, function(data)
		local now = GoalList.current(data.goalsDone, data.adventure)
		if not now or now.id ~= goal.id then
			return
		end
		paid = true
		data.coins += goal.coins
		data.sun += goal.sun
		table.insert(data.goalsDone, goal.id)
		-- (only after a "say hello" goal, so hellos for an Adventure put aside aren't lost)
		if goal.kind == "talk" then
			data.goalMet = {}
		end
		if data.adventure == goal.id then
			data.adventure = nil
		end
		storyNow = GoalList.storyStep(goal.id) ~= nil and GoalList.storyDone(data.goalsDone)
		if GoalList.allDone(data.goalsDone) then
			finished = true
			-- the bonus only once, even if more goals are added after someone's finished
			if not data.goalsFinished then
				data.goalsFinished = true
				bonus = true
				data.coins += GoalList.FINISH.coins
				data.sun += GoalList.FINISH.sun
			end
		end
		balance = data.coins
		newStory = data.newStory
	end)
	if not paid then
		return
	end
	if bonus then
		Analytics.coinsEarned(player, goal.coins, balance - GoalList.FINISH.coins, `goal:{goal.id}`)
		Analytics.coinsEarned(player, GoalList.FINISH.coins, balance, "goal:finish")
	else
		Analytics.coinsEarned(player, goal.coins, balance, `goal:{goal.id}`)
	end
	local step = GoalList.storyStep(goal.id)
	if step and newStory then
		Analytics.storyStep(player, step)
	end
	Remotes.GoalDone:FireClient(player, goal.id, goal.coins, goal.sun, storyNow, finished, bonus)
	if storyNow then
		for _, listener in storyListeners do
			task.spawn(listener, player)
		end
	end
	task.delay(NEXT_SECONDS, settle, player)
end

-- Ticks the goal they're on if they've already done it (they had a hat, a home, a pet,
-- something planted, a Cafe shift finished, a fish caught or a library stamp before they got to
-- that goal).
settle = function(player: Player)
	local data = PlayerData.get(player)
	local goal = data and GoalList.current(data.goalsDone, data.adventure)
	if not (data and goal and player.Parent) then
		return
	end
	local planted = false
	for _, bed in data.garden do
		planted = planted or bed.crop ~= nil
	end
	if (goal.kind == "hat" and #data.hats > 0) or (goal.kind == "home" and data.home ~= nil)
		or (goal.kind == "pet" and data.pet ~= nil) or (goal.kind == "plant" and planted)
		or (goal.kind == "cafe" and data.cafe.shifts > 0)
		or (goal.kind == "fish" and next(data.fishBook.caught) ~= nil)
		or (goal.kind == "library" and data.library.stamps > 0) then
		complete(player, goal)
	end
end

-- Others who want to hear about the same things (the board's little helps and today's story,
-- server/Daily).
local listeners: { (Player, string, string?) -> () } = {}

-- Runs `callback(player, kind, what)` for everything Goals.event hears about.
function Goals.onEvent(callback: (Player, string, string?) -> ())
	table.insert(listeners, callback)
end

-- Runs `callback(player)` when a player finishes the First Story.
function Goals.onStoryDone(callback: (Player) -> ())
	table.insert(storyListeners, callback)
end

-- Something happened that might finish a goal, a little help or today's story (server/Daily).
-- `kind` is one of the kinds in shared/Goals, or one that only the board uses: "coin" (a coin
-- picked up), "water" (a Garden bed watered) or "decorate" (something added, moved or changed
-- inside your house). `what` says which resident for "talk", which shop for "shop", and which
-- crop for "plant", "harvest" and "water".
function Goals.event(player: Player, kind: string, what: string?)
	for _, listener in listeners do
		listener(player, kind, what)
	end
	local data = PlayerData.get(player)
	local goal = data and GoalList.current(data.goalsDone, data.adventure)
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
			complete(player, goal)
		end
	elseif kind == "shop" then
		if goal.shop == nil or goal.shop == what then
			complete(player, goal)
		end
	else
		complete(player, goal)
	end
end

function Goals.start()
	-- GoalDone only goes from the server to players; anything a player sends on it is ignored.
	Remotes.GoalDone.OnServerEvent:Connect(function() end)

	-- Choosing the next Adventure on the Goals screen. Only once the First Story is done, and
	-- only one that's real and not done yet.
	Remotes.ChooseAdventure.OnServerEvent:Connect(function(player, id)
		if not RemoteGuard.allow(player, "ChooseAdventure") then
			return
		end
		local data = PlayerData.get(player)
		if typeof(id) ~= "string" or not data or not GoalList.isAdventure(id) then
			return
		end
		if not GoalList.storyDone(data.goalsDone) or table.find(data.goalsDone, id) or data.adventure == id then
			return
		end
		local firstChoice = false
		PlayerData.update(player, function(d)
			-- the first Adventure they ever choose (not a change of mind) is the funnel's last step
			firstChoice = d.newStory and d.adventure == nil
			for _, goal in GoalList.ADVENTURES do
				firstChoice = firstChoice and not table.find(d.goalsDone, goal.id)
			end
			d.adventure = id
		end)
		if firstChoice then
			Analytics.storyStep(player, #GoalList.STORY + 1)
		end
		-- a home or pet they already have ticks it straight away
		task.delay(0.5, settle, player)
	end)

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
				local goal = data and GoalList.current(data.goalsDone, data.adventure)
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
