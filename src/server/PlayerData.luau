-- Remembers each player between visits: their coins, the animal they picked, their hats and
-- clothes, their pet, their home, their garden and Garden Book, the goals they've done (with
-- the sunshine they've earned), their daily present, today's requests and their cafe shifts.
--
-- It's kept in a Roblox DataStore. Players can see their own numbers through attributes on
-- their Player object (Coins, Hat, OwnedHats, OwnedClothes, Wearing, Pet, PetGear, Look,
-- HomeDesign, Garden, GardenBook, Goal, GoalsDone, GoalMet, Sun, DailyStreak, Requests), which the game's
-- screens read. Everyone's Pet attribute is seen by every player, so their screens can show it.
--
-- Keeping saves safe:
--   * Only one server at a time can have a player's save open. Opening it writes a lock (this
--     server's id and the time) into the save; every autosave refreshes the lock, and leaving
--     lets go of it. Another server waits for the lock, and takes it over only once it's old
--     (Config.SAVE.LOCK_SECONDS), which means the server that held it has gone.
--   * Saving reads what's stored first, and never writes over newer data or a save another
--     server has taken over. It only writes the game's own fields and keeps anything else.
--   * Saves have a version number, and migrate() brings older saves up to date.
--   * If a save can't be opened, the player is kindly asked to come back, rather than playing
--     on and losing what they do.
--
-- In Studio, saving only works once the place is published and "Enable Studio Access to API
-- Services" is on (Game Settings > Security). Until then you can still play; nothing is saved.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Config = require(Shared.Config)
local GoalList = require(Shared.Goals)
local Houses = require(Shared.Houses)
local Looks = require(Shared.Looks)

local STORE_NAME = "SunnyfolkPlayers1"
local VERSION = 10 -- the save version this code writes (see migrate)
-- the game's own fields in a save
local FIELDS = {
	"coins", "earned", "look", "hat", "hats", "clothes", "wearing", "pet", "petGear", "home", "garden",
	"gardenBook", "goalsDone", "adventure", "goalMet", "goalsFinished", "newStory", "sun", "daily", "requests", "cafe",
}
local SAVE = Config.SAVE
local IN_STUDIO = RunService:IsStudio()

-- This server's name in save locks. A Studio test run has no JobId, so it makes up its own.
local JOB = if game.JobId ~= "" then game.JobId else "studio-" .. HttpService:GenerateGUID(false)

local COME_BACK = "Sorry, we couldn't open your Sunnyfolk save just now. Your coins and things are safe."
	.. " Please try again in a few minutes!"
local SOMEWHERE_ELSE = "You've opened Sunnyfolk somewhere else, so this game has closed. Your coins and"
	.. " things are safe!"

export type Choice = { species: string, coat: string, scarf: number }
export type Bed = { crop: string?, stage: number, readyAt: number?, quick: boolean? }
export type Data = {
	coins: number,
	earned: number, -- every coin they've ever been given, however (spending doesn't lower it)
	look: Choice?, -- nil until they've picked an animal
	hat: string?, -- the hat they're wearing
	hats: { string }, -- every hat they own
	clothes: { string }, -- every piece of clothing they own (from the Clothes Shop)
	wearing: { string }, -- the clothes they have on: at most one for each slot (Looks.SLOTS)
	-- their pet (Config.PETS): its kind, which colour and name (numbers into the lists), and
	-- the gear it has on; nil until they adopt one
	pet: { kind: string, color: number, name: number, collar: string?, top: string? }?,
	petGear: { string }, -- every piece of pet gear they own
	home: { design: Houses.Design, plot: number }?, -- their house at Home Pond, and which plot
	-- their beds in the Garden (one for each of Config.GARDEN.BEDS): what's planted (or nil), its
	-- stage (0 seeds to Config.GARDEN.STAGES ripe), and when the watered stage finishes (server
	-- clock, os.time), or nil while it waits for water. See Config.gardenState. `quick` is their
	-- very first crop, whose stages take Config.GARDEN.FIRST_STAGE.
	garden: { Bed },
	-- the Garden Book: how many of each crop they've picked (Config.GARDEN.ORDER), and whether
	-- they've had their first pick. Its stickers come from these (Config.bookStickers).
	gardenBook: { picked: { [string]: number }, first: boolean },
	goalsDone: { string }, -- the ids of the goals they've done (see shared/Goals)
	adventure: string?, -- the Adventure they've chosen to do next, if any
	goalMet: { string }, -- for a "say hello" goal, who they've said hello to so far
	goalsFinished: boolean, -- they've had the bonus for finishing the goals (it's only given once)
	-- they started the First Story after it came in (Step 16), so its steps go in the analytics
	-- funnel; players from older saves aren't counted
	newStory: boolean,
	sun: number, -- sunshine earned
	-- the daily present: the last day (server day number, see server/Daily) one was given,
	-- which of the 7 days it was (0 before the first), and the day this round of seven began
	daily: { last: number, streak: number, start: number },
	-- today's requests (Config.requestsFor(day)): progress on each, and which are done
	requests: { day: number, got: { number }, done: { boolean } },
	-- the Cafe: how many shifts they've finished, and the coins they've earned there since
	-- `hourStart` (server clock, os.time), which Config.CAFE.COINS_PER_HOUR caps
	cafe: { shifts: number, hourStart: number, hourCoins: number },
}
type Profile = {
	data: Data,
	canSave: boolean, -- false when saving is off (Studio) or another server has the save now
	stamp: number, -- counts saves; the stored one is never newer than ours when we write
	saving: boolean, -- a save is being written right now
	closing: boolean, -- the last save (they're leaving) has started: no other saves after it
	closed: boolean, -- the last save has finished (or given up)
}

local PlayerData = {}

-- What a player has unlocked for their house (Houses.allowed): the sunflower garden, once
-- their Garden Book is full.
function PlayerData.unlocks(data: Data): Houses.Unlocks
	return { gardenBook = Config.bookFull(data.gardenBook) }
end

local store: DataStore? = nil
local profiles: { [Player]: Profile } = {}
local loadedCallbacks: { (Player) -> () } = {}
-- Players (by UserId) whose save this server is opening or closing right now. A quick rejoin
-- on the same server waits for that to finish, so the two visits never mix up their saves.
local busy: { [number]: boolean } = {}

-- Every bed in the Garden, with nothing planted.
local function emptyGarden(): { Bed }
	local beds = {}
	for i = 1, #Config.GARDEN.BEDS do
		beds[i] = { crop = nil, stage = 0, readyAt = nil }
	end
	return beds
end

local function blank(): Data
	return {
		coins = 0,
		earned = 0,
		look = nil,
		hat = nil,
		hats = {},
		clothes = {},
		wearing = {},
		pet = nil,
		petGear = {},
		home = nil,
		garden = emptyGarden(),
		gardenBook = { picked = {}, first = false },
		goalsDone = {},
		adventure = nil,
		goalMet = {},
		goalsFinished = false,
		newStory = true,
		sun = 0,
		daily = { last = 0, streak = 0, start = 0 },
		requests = { day = 0, got = {}, done = {} },
		cafe = { shifts = 0, hourStart = 0, hourCoins = 0 },
	}
end

-- Brings an old save up to date, one version at a time, before tidy() checks it. Saves from
-- before there were versions count as version 0.
local function migrate(saved: any): any
	if typeof(saved) ~= "table" then
		return saved
	end
	local version = if typeof(saved.version) == "number" then saved.version else 0
	if version < 1 then
		-- Version 1 added the version number, the lock and the stamp. The game's fields are the
		-- same as before, so there's nothing to change.
		version = 1
	end
	if version < 2 then
		-- Version 2 added the goals and sunshine. Older saves start at the first goal with no
		-- sunshine, which tidy() fills in.
		version = 2
	end
	if version < 3 then
		-- Version 3 added the daily present and the request board. Older saves start with no
		-- present given yet and no requests, which tidy() fills in.
		version = 3
	end
	if version < 4 then
		-- Version 4 added clothes. Older saves start with none, which tidy() fills in.
		version = 4
	end
	if version < 5 then
		-- Version 5 added the total of coins ever earned. Older saves don't know how many
		-- they've spent, so their total starts at the coins they have now.
		if saved.earned == nil then
			saved.earned = saved.coins
		end
		version = 5
	end
	if version < 6 then
		-- Version 6 added pets, and a note of having had the bonus for finishing the goals.
		-- Back then there were 8 goals, so goal 9 meant they'd finished them all (and had the
		-- bonus); now there's a 9th goal for them to do, without a second bonus.
		if typeof(saved.goal) == "number" and saved.goal >= 9 then
			saved.goalsFinished = true
		end
		version = 6
	end
	if version < 7 then
		-- Version 7 added the Garden. Older saves start with empty beds, which tidy() fills in.
		version = 7
	end
	if version < 8 then
		-- Version 8 keeps the ids of the goals done, instead of the number of the goal they were
		-- on, for the First Story and Adventures. Every goal before the old number counts as done
		-- (goals that were taken out are dropped). Anyone past the old Garden goal (the last one)
		-- has finished the First Story, so planting counts as done too. They aren't counted in the
		-- First Story's analytics.
		local step = if typeof(saved.goal) == "number" then saved.goal else 1
		local done = {}
		for i, id in GoalList.OLD_ORDER do
			if i < step and GoalList.BY_ID[id] then
				table.insert(done, id)
			end
		end
		if step > #GoalList.OLD_ORDER then
			table.insert(done, "plant")
		end
		saved.goalsDone = done
		saved.newStory = false
		-- The library request was taken out, which changes the three requests each day picks, so
		-- today's requests start again from nothing (once, on the day of this update).
		saved.requests = nil
		version = 8
	end
	if version < 9 then
		-- Version 9 added the Garden Book. Nobody's picks were counted before, so it starts
		-- empty, except that anyone who'd already picked something (they'd done the "harvest"
		-- goal) has the first-pick sticker.
		local done = if typeof(saved.goalsDone) == "table" then saved.goalsDone else {}
		saved.gardenBook = { picked = {}, first = table.find(done, "harvest") ~= nil }
		version = 9
	end
	if version < 10 then
		-- Version 10 added the Cafe. Older saves start with no shifts and no cafe coins this
		-- hour, which tidy() fills in.
		version = 10
	end
	saved.version = version
	return saved
end

-- A whole number of at least 0, or nil if `value` isn't a proper number (nor "not a number").
local function count(value: any): number?
	if typeof(value) ~= "number" or value ~= value or value == math.huge then
		return nil
	end
	return math.max(0, math.floor(value))
end

-- Only keep what makes sense, in case the saved data is old or odd.
local function tidy(saved: any): Data
	local data = blank()
	if typeof(saved) ~= "table" then
		return data
	end
	data.coins = count(saved.coins) or 0
	data.earned = math.max(count(saved.earned) or 0, data.coins)
	if typeof(saved.hats) == "table" then
		for _, hatId in saved.hats do
			if typeof(hatId) == "string" and Looks.hat(hatId) and not table.find(data.hats, hatId) then
				table.insert(data.hats, hatId)
			end
		end
	end
	if typeof(saved.hat) == "string" and table.find(data.hats, saved.hat) then
		data.hat = saved.hat
	end
	if typeof(saved.clothes) == "table" then
		for _, id in saved.clothes do
			if typeof(id) == "string" and Looks.shopItem(id) and not table.find(data.clothes, id) then
				table.insert(data.clothes, id)
			end
		end
	end
	if typeof(saved.petGear) == "table" then
		for _, id in saved.petGear do
			if typeof(id) == "string" and Config.petGear(id) and not table.find(data.petGear, id) then
				table.insert(data.petGear, id)
			end
		end
	end
	local pet = saved.pet
	local petKind = typeof(pet) == "table" and Config.PETS.KINDS[pet.kind]
	if petKind then
		-- gear it wears must be owned, and in the right place
		local function worn(id: any, slot: string): string?
			local gear = typeof(id) == "string" and table.find(data.petGear, id) and Config.petGear(id)
			return if gear and gear.slot == slot then gear.id else nil
		end
		data.pet = {
			kind = pet.kind,
			color = math.clamp(count(pet.color) or 1, 1, #petKind.colors),
			name = math.clamp(count(pet.name) or 1, 1, #Config.PETS.NAMES),
			collar = worn(pet.collar, "collar"),
			top = worn(pet.top, "top"),
		}
	end
	if typeof(saved.wearing) == "table" then
		-- only clothes they own, and one for each slot
		local slots = {}
		for _, id in saved.wearing do
			local item = typeof(id) == "string" and table.find(data.clothes, id) and Looks.shopItem(id)
			if item and not slots[item.slot] then
				slots[item.slot] = true
				table.insert(data.wearing, id)
			end
		end
	end
	local look = saved.look
	if typeof(look) == "table" and table.find(Config.START_ANIMALS, look.species) then
		data.look = {
			species = look.species,
			coat = Looks.coat(look.species, look.coat).id,
			scarf = math.clamp(count(look.scarf) or 1, 1, #Looks.scarves()),
		}
	end
	-- the Garden Book: a count for each crop there is, and the first pick (which any count means)
	local book = saved.gardenBook
	if typeof(book) == "table" then
		for _, crop in Config.GARDEN.ORDER do
			local picked = typeof(book.picked) == "table" and count(book.picked[crop]) or 0
			if picked > 0 then
				data.gardenBook.picked[crop] = picked
				data.gardenBook.first = true
			end
		end
		data.gardenBook.first = data.gardenBook.first or book.first == true
	end
	local home = saved.home
	-- (a garden from a full Garden Book stays only while the book is full, which it always is)
	local design = typeof(home) == "table" and Houses.check(home.design, PlayerData.unlocks(data))
	if design then
		local plot = math.clamp(count(home.plot) or 1, 1, Config.HOME.plots)
		data.home = { design = design, plot = plot }
	end
	if typeof(saved.goalsDone) == "table" then
		for _, id in saved.goalsDone do
			if typeof(id) == "string" and GoalList.BY_ID[id] and not table.find(data.goalsDone, id) then
				table.insert(data.goalsDone, id)
			end
		end
	end
	if typeof(saved.adventure) == "string" and GoalList.isAdventure(saved.adventure)
		and not table.find(data.goalsDone, saved.adventure) then
		data.adventure = saved.adventure
	end
	data.goalsFinished = saved.goalsFinished == true
	data.newStory = saved.newStory ~= false
	if typeof(saved.goalMet) == "table" then
		for _, id in saved.goalMet do
			if typeof(id) == "string" and table.find(Config.RESIDENTS, id) and not table.find(data.goalMet, id) then
				table.insert(data.goalMet, id)
			end
		end
	end
	data.sun = count(saved.sun) or 0
	-- the garden: one entry for each bed, with only crops that exist and sensible numbers
	for i = 1, #Config.GARDEN.BEDS do
		local plot = typeof(saved.garden) == "table" and saved.garden[i]
		local crop = typeof(plot) == "table" and typeof(plot.crop) == "string" and Config.GARDEN.CROPS[plot.crop] and plot.crop
		if crop then
			-- (a watered stage can't finish later than one stage from now)
			local readyAt = count(plot.readyAt)
			data.garden[i] = {
				crop = crop,
				stage = math.clamp(count(plot.stage) or 0, 0, Config.GARDEN.STAGES),
				readyAt = if readyAt then math.min(readyAt, os.time() + Config.GARDEN.CROPS[crop].stage) else nil,
				quick = if plot.quick == true then true else nil,
			}
		else
			data.garden[i] = { crop = nil, stage = 0, readyAt = nil }
		end
	end
	local daily = saved.daily
	if typeof(daily) == "table" then
		data.daily = {
			last = count(daily.last) or 0,
			streak = math.clamp(count(daily.streak) or 0, 0, #Config.DAILY.COINS),
			start = count(daily.start) or 0,
		}
	end
	local cafe = saved.cafe
	if typeof(cafe) == "table" then
		-- (an hour can't start in the future)
		data.cafe = {
			shifts = count(cafe.shifts) or 0,
			hourStart = math.min(count(cafe.hourStart) or 0, os.time()),
			hourCoins = math.min(count(cafe.hourCoins) or 0, Config.CAFE.COINS_PER_HOUR),
		}
	end
	local requests = saved.requests
	if typeof(requests) == "table" then
		data.requests.day = count(requests.day) or 0
		for i = 1, Config.REQUESTS_PER_DAY do
			local got = typeof(requests.got) == "table" and count(requests.got[i])
			data.requests.got[i] = got or 0
			data.requests.done[i] = typeof(requests.done) == "table" and requests.done[i] == true
		end
	end
	return data
end

local function keyFor(player: Player): string
	return `player_{player.UserId}`
end

-- Shows the player their own numbers.
local function publish(player: Player, data: Data)
	player:SetAttribute("Coins", data.coins)
	player:SetAttribute("Hat", data.hat)
	player:SetAttribute("OwnedHats", table.concat(data.hats, ","))
	player:SetAttribute("OwnedClothes", table.concat(data.clothes, ","))
	player:SetAttribute("Wearing", table.concat(data.wearing, ","))
	player:SetAttribute("Pet", if data.pet then HttpService:JSONEncode(data.pet) else nil)
	player:SetAttribute("PetGear", table.concat(data.petGear, ","))
	player:SetAttribute("Garden", HttpService:JSONEncode(data.garden))
	player:SetAttribute("GardenBook", HttpService:JSONEncode(data.gardenBook))
	player:SetAttribute("Look", if data.look then HttpService:JSONEncode(data.look) else nil)
	player:SetAttribute("HomeDesign", if data.home then HttpService:JSONEncode(data.home.design) else nil)
	local goal = GoalList.current(data.goalsDone, data.adventure)
	player:SetAttribute("Goal", if goal then goal.id else nil) -- the goal they're on
	player:SetAttribute("GoalsDone", table.concat(data.goalsDone, ","))
	player:SetAttribute("GoalMet", table.concat(data.goalMet, ","))
	player:SetAttribute("Sun", data.sun)
	player:SetAttribute("DailyStreak", data.daily.streak)
	player:SetAttribute("Requests", HttpService:JSONEncode(data.requests))
end

-- Is this save open on another server that's still running?
local function openElsewhere(stored: any): boolean
	local lock = if typeof(stored) == "table" then stored.lock else nil
	if typeof(lock) ~= "table" or lock.job == JOB then
		return false
	end
	-- In Studio, a lock left by an earlier test run (stopped before it could let go) is ours to take
	if IN_STUDIO and typeof(lock.job) == "string" and string.sub(lock.job, 1, 7) == "studio-" then
		return false
	end
	local age = os.time() - (tonumber(lock.time) or 0)
	return age < SAVE.LOCK_SECONDS
end

-- Opens a player's save on this server, locking it. Returns "open" and what was stored (nil for
-- a new player), "locked" if another server has it open, or "failed" and the error.
local function open(player: Player): (string, any)
	local stored, locked = nil, false
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(keyFor(player), function(old)
			stored, locked = old, false
			if openElsewhere(old) then
				locked = true
				return nil -- leave it exactly as it is
			end
			local record = if typeof(old) == "table" then table.clone(old) else {}
			record.lock = { job = JOB, time = os.time() }
			return record
		end)
	end)
	if not ok then
		return "failed", tostring(err)
	end
	return if locked then "locked" else "open", stored
end

-- Lets go of this server's lock on a save, without changing anything else in it.
local function letGo(player: Player)
	pcall(function()
		(store :: DataStore):UpdateAsync(keyFor(player), function(old)
			if typeof(old) ~= "table" or typeof(old.lock) ~= "table" or old.lock.job ~= JOB then
				return nil
			end
			local record = table.clone(old)
			record.lock = nil
			return record
		end)
	end)
end

-- Loads a player's save. Returns the data (nil if it couldn't be opened, so they should be asked
-- to come back), whether it'll be saved, and the stamp of what was stored.
local function load(player: Player): (Data?, boolean, number)
	if not store then
		if IN_STUDIO then
			return blank(), false, 0 -- testing without saving
		end
		return nil, false, 0
	end
	for attempt = 1, SAVE.LOAD_TRIES do
		local status, result = open(player)
		if status == "open" then
			if typeof(result) == "table" and typeof(result.version) == "number" and result.version > VERSION then
				-- Saved by a newer version of the game (while servers are updating). Don't open it
				-- here, or this older code could write over things it doesn't understand.
				warn(`Sunnyfolk: {player.Name}'s save is from a newer version of the game`)
				return nil, false, 0
			end
			local saved = migrate(result)
			local stamp = if typeof(saved) == "table" and typeof(saved.stamp) == "number" then saved.stamp else 0
			return tidy(saved), true, stamp
		elseif status == "failed" then
			if IN_STUDIO then
				-- Usually "Enable Studio Access to API Services" is off (Roblox's wording for that
				-- changes, so any failure counts). Play on in Studio with nothing saved.
				warn(`Sunnyfolk: saving is off in this Studio test ({result}). To turn it on, publish the place`
					.. " and turn on Game Settings > Security > Enable Studio Access to API Services.")
				return blank(), false, 0
			end
			warn(`Sunnyfolk: couldn't open {player.Name}'s save (try {attempt} of {SAVE.LOAD_TRIES}): {result}`)
		else
			warn(`Sunnyfolk: {player.Name}'s save is still open on another server (try {attempt} of {SAVE.LOAD_TRIES})`)
		end
		if not player.Parent then
			return nil, false, 0
		end
		task.wait(SAVE.RETRY_SECONDS)
	end
	return nil, false, 0
end

-- Writes a player's data. `release` lets go of the lock too (when they leave). Returns whether
-- it was saved. It never writes over newer data, or a save another server has taken over.
local function save(player: Player, profile: Profile, release: boolean?): boolean
	-- Once the last save has started, nothing else may save (it would lock the save again).
	if not (store and profile.canSave) or (profile.closing and not release) then
		return false
	end
	while profile.saving do
		task.wait(SAVE.CHECK_SECONDS)
	end
	if not profile.canSave or (profile.closing and not release) then
		return false
	end
	profile.saving = true
	local outcome, newStamp = "saved", profile.stamp
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(keyFor(player), function(old)
			outcome = "saved"
			local stored = if typeof(old) == "table" then old else {}
			local ours = typeof(stored.lock) == "table" and stored.lock.job == JOB
			if typeof(stored.lock) == "table" and not ours then
				outcome = "taken" -- another server has opened this save since
				return nil
			end
			-- A newer stamp under our own lock is our own earlier save (one that worked but
			-- reported an error), so it's fine to carry on. Under no lock, it's someone else's.
			local storedStamp = tonumber(stored.stamp) or 0
			if storedStamp > profile.stamp and not ours then
				outcome = "newer" -- what's stored is newer than what we have
				return nil
			end
			local record = table.clone(stored) -- keeps anything we don't know about
			for _, field in FIELDS do
				record[field] = (profile.data :: any)[field]
			end
			newStamp = math.max(storedStamp, profile.stamp) + 1
			record.version = VERSION
			record.stamp = newStamp
			record.lock = if release then nil else { job = JOB, time = os.time() }
			return record
		end)
	end)
	profile.saving = false
	if not ok then
		warn(`Sunnyfolk: couldn't save {player.Name}'s game (it'll try again): {err}`)
		return false
	end
	if outcome == "saved" then
		profile.stamp = newStamp
		return true
	end
	-- The player must have opened the game on another server. Stop saving here, so we never
	-- write over what that server saves.
	profile.canSave = false
	warn(`Sunnyfolk: {player.Name}'s save is open somewhere else now ({outcome}), so this server has stopped saving it`)
	if player.Parent and not release then
		player:Kick(SOMEWHERE_ELSE)
	end
	return false
end

-- The last save when a player leaves (or the server closes): lets go of the lock, and tries a
-- few times if it fails, so they don't lose their last few minutes.
local function saveOnLeaving(player: Player, profile: Profile)
	if profile.closing then
		-- Already started (leaving and the server closing both ask for it): wait for it to finish.
		while not profile.closed do
			task.wait(SAVE.CHECK_SECONDS)
		end
		return
	end
	profile.closing = true
	for _ = 1, SAVE.LEAVE_TRIES do
		if save(player, profile, true) then
			profile.canSave = false -- saved and let go: this server never writes it again
			break
		end
		if not profile.canSave then
			break
		end
		task.wait(SAVE.RETRY_SECONDS)
	end
	profile.closed = true
end

-- The player's data, or nil if it hasn't loaded yet.
function PlayerData.get(player: Player): Data?
	local profile = profiles[player]
	return profile and profile.data
end

-- Changes a player's data. `change` gets the data to edit; it's saved later.
function PlayerData.update(player: Player, change: (Data) -> ())
	local profile = profiles[player]
	if not profile or profile.closing then
		return -- not loaded yet, or they're leaving and their last save has started
	end
	local before = profile.data.coins
	change(profile.data)
	-- coins given (by any part of the game) count towards the total ever earned
	local gained = profile.data.coins - before
	if gained > 0 then
		profile.data.earned += gained
	end
	publish(player, profile.data)
end

-- Saves a player's data straight away (say, right after they buy something), instead of
-- waiting for the next autosave. Returns whether it was saved.
function PlayerData.saveNow(player: Player): boolean
	local profile = profiles[player]
	return profile ~= nil and save(player, profile)
end

-- Runs `callback(player)` once each player's data has loaded.
function PlayerData.onLoaded(callback: (Player) -> ())
	table.insert(loadedCallbacks, callback)
	for player in profiles do
		task.spawn(callback, player)
	end
end

function PlayerData.start()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn(`Sunnyfolk: saving is off ({result})`)
	end

	local function added(player: Player)
		-- After a quick leave and rejoin on this same server, wait for the last visit to finish.
		local id = player.UserId
		while busy[id] do
			task.wait(SAVE.CHECK_SECONDS)
		end
		if profiles[player] then
			return -- already loaded (a player who joins as the server starts can be seen twice)
		end
		busy[id] = true
		-- If loading hits an error, treat it like a save that couldn't be opened.
		local ok, data, canSave, stamp = pcall(load, player)
		if not ok then
			warn(`Sunnyfolk: something went wrong opening {player.Name}'s save: {data}`)
			data, canSave, stamp = nil, false, 0
		end
		if not (data and player.Parent) then
			-- They left while it was loading, or it couldn't be opened: let go of any lock this
			-- server took (letGo only ever clears this server's own lock).
			if store then
				letGo(player)
			end
			busy[id] = nil
			if player.Parent then
				player:Kick(COME_BACK)
			end
			return
		end
		profiles[player] = { data = data, canSave = canSave, stamp = stamp, saving = false, closing = false, closed = false }
		busy[id] = nil
		publish(player, data)
		player:SetAttribute("Saving", canSave)
		player:SetAttribute("Loaded", true)
		for _, callback in loadedCallbacks do
			task.spawn(callback, player)
		end
	end
	Players.PlayerAdded:Connect(added)
	for _, player in Players:GetPlayers() do
		task.spawn(added, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		local profile = profiles[player]
		if profile then
			busy[player.UserId] = true
			saveOnLeaving(player, profile)
			profiles[player] = nil
			busy[player.UserId] = nil
		end
	end)

	game:BindToClose(function()
		local waiting = 0
		for player, profile in profiles do
			waiting += 1
			task.spawn(function()
				saveOnLeaving(player, profile)
				waiting -= 1
			end)
		end
		-- wait for everyone's last save, and for any save still being opened to be let go
		local deadline = os.clock() + SAVE.CLOSE_SECONDS
		while (waiting > 0 or next(busy) ~= nil) and os.clock() < deadline do
			task.wait(SAVE.CHECK_SECONDS)
		end
	end)

	-- Autosave, which also keeps each save's lock fresh.
	task.spawn(function()
		while true do
			task.wait(SAVE.AUTOSAVE_SECONDS)
			for player, profile in profiles do
				task.spawn(save, player, profile)
			end
		end
	end)
end

return PlayerData
