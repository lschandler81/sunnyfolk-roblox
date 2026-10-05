-- Remembers each player between visits: their coins, the animal they picked, and their hats.
--
-- It's kept in a Roblox DataStore. Players can see their own numbers through attributes on
-- their Player object (Coins, Hat, OwnedHats, Look), which the game's screens read.
--
-- In Studio, saving only works once the place is published and "Enable Studio Access to API
-- Services" is on (Game Settings > Security). Until then you can still play; nothing is saved.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Config = require(Shared.Config)
local Houses = require(Shared.Houses)
local Looks = require(Shared.Looks)

local STORE_NAME = "SunnyfolkPlayers1"
local AUTOSAVE_SECONDS = 120

export type Choice = { species: string, coat: string, scarf: number }
export type Data = {
	coins: number,
	look: Choice?, -- nil until they've picked an animal
	hat: string?, -- the hat they're wearing
	hats: { string }, -- every hat they own
	home: { design: Houses.Design, plot: number }?, -- their house at Home Pond, and which plot
}
type Profile = { data: Data, canSave: boolean, dirty: boolean }

local PlayerData = {}

local store: DataStore? = nil
local profiles: { [Player]: Profile } = {}
local loadedCallbacks: { (Player) -> () } = {}

local function blank(): Data
	return { coins = 0, look = nil, hat = nil, hats = {}, home = nil }
end

-- Only keep what makes sense, in case the saved data is old or odd.
local function tidy(saved: any): Data
	local data = blank()
	if typeof(saved) ~= "table" then
		return data
	end
	if typeof(saved.coins) == "number" then
		data.coins = math.max(0, math.floor(saved.coins))
	end
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
			scarf = if typeof(look.scarf) == "number" then math.clamp(math.floor(look.scarf), 1, #Looks.scarves()) else 1,
		}
	end
	local home = saved.home
	local design = typeof(home) == "table" and Houses.check(home.design)
	if design then
		local plot = if typeof(home.plot) == "number" then math.clamp(math.floor(home.plot), 1, Config.HOME.plots) else 1
		data.home = { design = design, plot = plot }
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
	player:SetAttribute("Look", if data.look then HttpService:JSONEncode(data.look) else nil)
	player:SetAttribute("HomeDesign", if data.home then HttpService:JSONEncode(data.home.design) else nil)
end

local function load(player: Player): (Data, boolean)
	if not store then
		return blank(), false
	end
	for attempt = 1, 3 do
		local ok, result = pcall(function()
			return (store :: DataStore):GetAsync(keyFor(player))
		end)
		if ok then
			return tidy(result), true
		end
		local message = tostring(result)
		if string.find(message, "Studio") or string.find(message, "publish") then
			warn("Sunnyfolk: saving is off while testing in Studio. To turn it on, publish the place and turn on"
				.. " Game Settings > Security > Enable Studio Access to API Services.")
			break
		end
		warn(`Sunnyfolk: couldn't load {player.Name}'s save (try {attempt} of 3): {message}`)
		task.wait(attempt * 2)
	end
	-- Play on, but don't save: that could overwrite a good save we just couldn't read.
	return blank(), false
end

local function save(player: Player, profile: Profile)
	if not (store and profile.canSave and profile.dirty) then
		return
	end
	profile.dirty = false
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(keyFor(player), function()
			return profile.data
		end)
	end)
	if not ok then
		profile.dirty = true
		warn(`Sunnyfolk: couldn't save {player.Name}'s game: {err}`)
	end
end

-- The player's data, or nil if it hasn't loaded yet.
function PlayerData.get(player: Player): Data?
	local profile = profiles[player]
	return profile and profile.data
end

-- Changes a player's data. `change` gets the data to edit; it's saved later.
function PlayerData.update(player: Player, change: (Data) -> ())
	local profile = profiles[player]
	if not profile then
		return
	end
	change(profile.data)
	profile.dirty = true
	publish(player, profile.data)
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
		local data, canSave = load(player)
		if not player.Parent then
			return -- they left while it was loading
		end
		profiles[player] = { data = data, canSave = canSave, dirty = false }
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
			save(player, profile)
			profiles[player] = nil
		end
	end)

	game:BindToClose(function()
		local waiting = 0
		for player, profile in profiles do
			waiting += 1
			task.spawn(function()
				save(player, profile)
				waiting -= 1
			end)
		end
		local deadline = os.clock() + 25
		while waiting > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_SECONDS)
			for player, profile in profiles do
				task.spawn(save, player, profile)
			end
		end
	end)
end

return PlayerData
