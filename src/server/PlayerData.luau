-- Remembers each player between visits: their coins, the animal they picked, their hats,
-- their home, and how far they've got through the goals (with the sunshine they've earned).
--
-- It's kept in a Roblox DataStore. Players can see their own numbers through attributes on
-- their Player object (Coins, Hat, OwnedHats, Look, HomeDesign, Goal, GoalCount, GoalMet,
-- Sun), which the game's screens read.
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
local VERSION = 2 -- the save version this code writes (see migrate)
-- the game's own fields in a save
local FIELDS = { "coins", "look", "hat", "hats", "home", "goal", "goalCount", "goalMet", "sun" }
local SAVE = Config.SAVE
local IN_STUDIO = RunService:IsStudio()

-- This server's name in save locks. A Studio test run has no JobId, so it makes up its own.
local JOB = if game.JobId ~= "" then game.JobId else "studio-" .. HttpService:GenerateGUID(false)

local COME_BACK = "Sorry, we couldn't open your Sunnyfolk save just now. Your coins and things are safe."
	.. " Please try again in a few minutes!"
local SOMEWHERE_ELSE = "You've opened Sunnyfolk somewhere else, so this game has closed. Your coins and"
	.. " things are safe!"

export type Choice = { species: string, coat: string, scarf: number }
export type Data = {
	coins: number,
	look: Choice?, -- nil until they've picked an animal
	hat: string?, -- the hat they're wearing
	hats: { string }, -- every hat they own
	home: { design: Houses.Design, plot: number }?, -- their house at Home Pond, and which plot
	goal: number, -- the goal they're on (see shared/Goals): 1 to #LIST, or #LIST + 1 when all done
	goalCount: number, -- progress on a counting goal (coins picked up since it started)
	goalMet: { string }, -- for a "say hello" goal, who they've said hello to so far
	sun: number, -- sunshine earned
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

local store: DataStore? = nil
local profiles: { [Player]: Profile } = {}
local loadedCallbacks: { (Player) -> () } = {}
-- Players (by UserId) whose save this server is opening or closing right now. A quick rejoin
-- on the same server waits for that to finish, so the two visits never mix up their saves.
local busy: { [number]: boolean } = {}

local function blank(): Data
	return { coins = 0, look = nil, hat = nil, hats = {}, home = nil, goal = 1, goalCount = 0, goalMet = {}, sun = 0 }
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
	local look = saved.look
	if typeof(look) == "table" and table.find(Config.START_ANIMALS, look.species) then
		data.look = {
			species = look.species,
			coat = Looks.coat(look.species, look.coat).id,
			scarf = math.clamp(count(look.scarf) or 1, 1, #Looks.scarves()),
		}
	end
	local home = saved.home
	local design = typeof(home) == "table" and Houses.check(home.design)
	if design then
		local plot = math.clamp(count(home.plot) or 1, 1, Config.HOME.plots)
		data.home = { design = design, plot = plot }
	end
	data.goal = math.clamp(count(saved.goal) or 1, 1, #GoalList.LIST + 1)
	data.goalCount = count(saved.goalCount) or 0
	if typeof(saved.goalMet) == "table" then
		for _, id in saved.goalMet do
			if typeof(id) == "string" and table.find(Config.RESIDENTS, id) and not table.find(data.goalMet, id) then
				table.insert(data.goalMet, id)
			end
		end
	end
	data.sun = count(saved.sun) or 0
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
	player:SetAttribute("Look", if data.look then HttpService:JSONEncode(data.look) else nil)
	player:SetAttribute("HomeDesign", if data.home then HttpService:JSONEncode(data.home.design) else nil)
	player:SetAttribute("Goal", data.goal)
	player:SetAttribute("GoalCount", data.goalCount)
	player:SetAttribute("GoalMet", table.concat(data.goalMet, ","))
	player:SetAttribute("Sun", data.sun)
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
	change(profile.data)
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
