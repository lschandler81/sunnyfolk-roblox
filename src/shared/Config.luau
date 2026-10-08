-- Settings shared by the server and every player: where things are in the town square,
-- where the coins float, and who lives here.
--
-- Positions come from the web game (src/world/hub.js and map.js), which measures in its own
-- units. One web unit is 2.8 studs, so `polar(36, 19.5)` is 19.5 web units from the fountain.

local Config = {}

Config.STUDS = 2.8 -- studs per web-game unit
local S = Config.STUDS

-- A spot on the ground at compass angle `angle` (0 = north = -Z, 90 = east = +X),
-- `dist` web units from the fountain.
function Config.polar(angle: number, dist: number): Vector3
	local a = math.rad(angle)
	return Vector3.new(math.sin(a) * dist * S, 0, -math.cos(a) * dist * S)
end

-- The turn (radians about Y) that makes something's front (+Z) face the fountain from `angle`.
function Config.faceIn(angle: number): number
	return -math.rad(angle)
end

-- Turns a web-game [x, z] position into studs.
function Config.fromWeb(x: number, z: number): Vector3
	return Vector3.new(x * S, 0, z * S)
end

---------------------------------------------------------------- the town square

-- The square is about twice the size of the web game's, so there's room to explore on
-- Roblox. Distances are in web units from the fountain.
Config.FOUNTAIN_SCALE = 1.5 -- the fountain is half as big again
Config.FOUNTAIN_R = 3.4 * Config.FOUNTAIN_SCALE -- walkers keep this far from the middle
Config.PLAZA_R = 17 -- the paved circle round the fountain
Config.ROAD_W = 4.4 -- how wide the roads are
Config.SHOP_DIST = 29 -- to the middle of each shop
Config.EDGE_R = 72 -- the hedge round the town; nobody walks past it

-- Parts smaller than this (in studs, on their longest side) cast no shadow: flowers, flags,
-- trims and so on, whose shadows nobody would notice. Keeps phones running smoothly.
Config.SHADOW_SIZE = 2

-- Where you appear (on the ground, facing the fountain).
Config.SPAWN = CFrame.lookAt(Config.fromWeb(0, 11), Vector3.zero)

-- The shops round the square. All but the Post Office are open so far.
Config.SHOPS = {
	{ id = "hats", angle = 36, label = "Hat Shop", wall = "#f7e8c8", roof = "#2f8a7c", awning = "#f07055", door = "#1f5f57", sign = "#2f8a7c", open = true },
	{ id = "clothes", angle = 108, label = "Clothes Shop", wall = "#fbe3d2", roof = "#f07055", awning = "#2f8a7c", door = "#1f5f57", sign = "#d9604a", open = true },
	{ id = "pets", angle = 252, label = "Pet Shop", wall = "#e2f1e6", roof = "#f6c64a", awning = "#f07055", door = "#f07055", sign = "#6fa057", open = true },
	{ id = "post", angle = 324, label = "Post Office", wall = "#f7e8c8", roof = "#d9b3dc", awning = "#f6c64a", door = "#f07055", sign = "#2f8a7c" },
}

-- The roads out of town. The places at the end aren't built yet, so each road ends at a gate.
Config.ROADS = {
	{ angle = 0, name = "Kart Track", color = "#f07055" },
	{ angle = 72, name = "Cafe", color = "#2f8a7c" },
	{ angle = 144, name = "Garden", color = "#6fa057", place = "garden" }, -- see Config.GARDEN
	{ angle = 216, name = "Home Pond", color = "#5a8fae", open = true },
	{ angle = 288, name = "Art Studio", color = "#b583b9" },
}

-- Home Pond: where each player picks a plot for their own house. There are two ponds, each
-- with a ring of plots round it, all facing the water: Home Pond at the end of the Home Pond
-- road (plots 1 to 10), and Lily Pond beside it (plots 11 to 20), reached by a path that
-- branches off the road just inside the town hedge. Plot numbers are saved, so plots 1 to 10
-- must never move.
Config.HOME = {
	ponds = {
		{ name = "Home Pond", angle = 216, dist = 96 }, -- which way from the fountain, and how far
		{ name = "Lily Pond", angle = 180, dist = 96, color = "#d9b3dc", branch = 64 },
	},
	radius = 26, -- the hedge round each pond's neighbourhood
	pondR = 6,
	ringR = 9.5, -- the path round each pond
	plotR = 19.5, -- from a pond's middle to each house
	plotsPerPond = 10,
	plots = 20, -- one for each player on a server (set the server size to match)
	wayIn = 40, -- degrees left open for the way in to each pond
}
-- `branch`: how far from the fountain Lily Pond's path leaves the Home Pond road. `color`: its
-- gate (Home Pond's is sky blue).

-- The library on the south lawn, and a gazebo on the east lawn.
Config.LIBRARY = { angle = 180, dist = 38 }
Config.GAZEBO = { angle = 108, dist = 47 }

-- Cottages along the roads out of town. A label puts a name sign over the door; the others
-- are waiting for friends who'll move in later.
Config.COTTAGES = {
	{ road = 72, dist = 44, side = 1, label = "Puddles' House", wall = "#fff1c9", roof = "#5aa9d8", door = "#f6c64a", sign = "#5a8fae", pond = true },
	{ road = 288, dist = 44, side = -1, label = "Pebble's House", wall = "#eef3f6", roof = "#3b4a6b", door = "#f07055", sign = "#3b4a6b" },
	{ road = 144, dist = 50, side = -1, wall = "#e4f2d8", roof = "#6fa057", door = "#d9b3dc" },
	{ road = 216, dist = 50, side = 1, wall = "#fbe3d2", roof = "#f07055", door = "#2f8a7c" },
	{ road = 0, dist = 54, side = 1, wall = "#f7e8c8", roof = "#d9b3dc", door = "#f6c64a" },
	{ road = 0, dist = 54, side = -1, wall = "#e2f1e6", roof = "#f6c64a", door = "#f07055" },
}
Config.COTTAGE_OFFSET = 9 -- from the middle of the road to the cottage

-- Where a cottage stands (on the ground, its front door facing the road), and the point on the
-- road in front of it.
function Config.cottageAt(cottage): (CFrame, Vector3)
	local road = Config.polar(cottage.road, cottage.dist)
	local spot = road + Config.polar(cottage.road + 90 * cottage.side, Config.COTTAGE_OFFSET)
	return CFrame.lookAt(spot, road) * CFrame.Angles(0, math.pi, 0), road
end

---------------------------------------------------------------- the Garden

-- Fern's Garden, at the end of the Garden road (see server/places/Garden and client/Garden),
-- from the web game's garden. Its gate opens once you've said hello to Clover (the First
-- Story, shared/Goals). Everyone has their own six beds in it: plant seeds (free), water each
-- stage, and it grows by the server's clock, even while you're away; then harvest for coins.
-- Distances are web units.
Config.GARDEN = {
	angle = 144, -- which way from the fountain
	dist = 94, -- from the fountain to its middle
	radius = 24, -- its hedge, which joins the town's
	-- the beds: x across, z towards the way in (from the middle), and their size
	BEDS = { { -7, -4.6 }, { 0, -4.6 }, { 7, -4.6 }, { -7, 4 }, { 0, 4 }, { 7, 4 } },
	BED_W = 4.8,
	BED_D = 3.7,
	REACH = 20, -- studs: how close to a bed you must be to plant, water or harvest it
	-- the ribbon across the way in, until you've said hello to Clover: wide enough to cover the whole
	-- gap where the town's hedge and the Garden's meet (that gap is about 17 wide)
	GATE_WIDTH = 24,
	-- each player's screen thinks it's this many seconds earlier than the server, so a bed
	-- never says "Water" or "Harvest" a moment before the server agrees
	CLIENT_LAG = 1,
	-- the little sign over a bed ("Needs water", "Ready!"): how high it floats over the bed
	-- (studs), and how far away it can be seen (studs). It shows through things, so your animal
	-- never hides it, and it goes while you're at that bed (its button says the same). While a
	-- crop grows there's no button, and the sign counts down instead ("Growing · 0:17").
	SIGN_HEIGHT = 7,
	SIGN_DISTANCE = 70,
	SIGN_SIZE = Vector2.new(170, 30), -- pixels (the goal's pin sits just above it)
	STAGES = 3, -- a crop is ready at stage 3 (each stage before needs watering)
	-- a player's very first crop (planted during the First Story) takes this long a stage
	-- (seconds), whichever crop it is; every crop after uses its own time below
	FIRST_STAGE = 20,
	-- Studio only: turn this on (true) to make every crop grow at FIRST_STAGE speed, to check
	-- how each one looks at every stage. It does nothing outside Studio.
	STUDIO_FAST = false,
	ORDER = { "sunflower", "carrot", "strawberry", "pumpkin" },
	-- each stage takes `stage` seconds once watered; `count` plants fill a bed
	CROPS = {
		sunflower = { name = "Sunflowers", stage = 2 * 60, coins = 4, count = 3 },
		carrot = { name = "Carrots", stage = 10 * 60, coins = 8, count = 6 },
		strawberry = { name = "Strawberries", stage = 30 * 60, coins = 15, count = 4 },
		pumpkin = { name = "Giant pumpkin", stage = 3 * 60 * 60, coins = 30, count = 1 },
	},
}

-- The Garden Book (client/GardenBook): a sticker for your first pick, and one for each crop
-- the first time you pick it. The server counts every pick (server/places/Garden). Filling
-- the book unlocks the sunflower front garden for your home (Houses.GARDENS).
Config.GARDEN_BOOK = { "first", "sunflower", "carrot", "strawberry", "pumpkin" }

-- Which stickers a Garden Book (as saved: { picked = { crop = count }, first = true }) has.
function Config.bookStickers(book: any): { [string]: boolean }
	local picked = if typeof(book) == "table" and typeof(book.picked) == "table" then book.picked else {}
	local got = { first = typeof(book) == "table" and book.first == true }
	for _, crop in Config.GARDEN.ORDER do
		got[crop] = typeof(picked[crop]) == "number" and picked[crop] > 0
	end
	return got
end

-- Is every sticker in the book?
function Config.bookFull(book: any): boolean
	local got = Config.bookStickers(book)
	for _, id in Config.GARDEN_BOOK do
		if not got[id] then
			return false
		end
	end
	return true
end

-- The Garden's middle, on the ground, with +Z pointing back along the road to town.
function Config.gardenFrame(): CFrame
	local G = Config.GARDEN
	local centre = Config.polar(G.angle, G.dist)
	return CFrame.lookAt(centre, Vector3.zero) * CFrame.Angles(0, math.pi, 0)
end

-- The middle of bed `i`, on the ground (facing the same way as the Garden).
function Config.gardenBed(i: number): CFrame
	local spot = Config.GARDEN.BEDS[i]
	return Config.gardenFrame() * CFrame.new(spot[1] * S, 0, spot[2] * S)
end

-- Where a bed has got to at time `now` (seconds, server clock): its stage (0 seeds to
-- STAGES ripe), whether it needs watering, and when the current stage finishes (or nil).
-- A watered stage that's finished counts as the next stage, needing water again.
function Config.gardenState(plot: any, now: number): (number, boolean, number?)
	if not (plot and plot.crop) then
		return 0, false, nil
	end
	local stage = plot.stage or 0
	local readyAt = plot.readyAt
	if readyAt and now >= readyAt then
		stage += 1
		readyAt = nil
	end
	stage = math.min(stage, Config.GARDEN.STAGES)
	return stage, stage < Config.GARDEN.STAGES and readyAt == nil, readyAt
end

---------------------------------------------------------------- pets

-- Pets from the Pet Shop (see shared/PetBuilder, server/Pets, client/Pets and client/PetShop),
-- from the web game's pet.js. Each player can have one, and change its kind, colour and name
-- for free once they've adopted it. Names come from the list (nobody types one in).
Config.PETS = {
	ADOPT_PRICE = 40,
	ORDER = { "puppy", "kitten", "duckling" },
	KINDS = {
		puppy = { name = "Puppy", colors = { "#d9a46c", "#8a5a36", "#f3e2c8" } },
		kitten = { name = "Kitten", colors = { "#f2a65a", "#9ea3ab", "#4a4f5c" } },
		duckling = { name = "Duckling", colors = { "#f6d84a", "#f7f3e8", "#c9a26a" } },
	},
	NAMES = {
		"Noodle", "Peanut", "Socks", "Bean", "Muffin", "Pickle",
		"Button", "Sprout", "Nugget", "Dumpling", "Pip-squeak", "Biscotti",
	},
	-- things to wear: a collar, and something on top of the head ("short" fits on a button)
	GEAR = {
		{ id = "collar-teal", slot = "collar", name = "Teal collar", price = 6, color = "#2f8a7c" },
		{ id = "collar-yellow", slot = "collar", name = "Sunny collar", price = 6, color = "#f6c64a" },
		{ id = "collar-lilac", slot = "collar", name = "Lilac collar", price = 6, color = "#d9b3dc" },
		{ id = "collar-blue", slot = "collar", name = "Sky collar", price = 6, color = "#9cc3d8" },
		{ id = "bow", slot = "top", name = "Bow", short = "Bow", price = 10 },
		{ id = "flower", slot = "top", name = "Flower", short = "Flower", price = 12 },
		{ id = "party", slot = "top", name = "Party hat", short = "Party", price = 15 },
		{ id = "crown", slot = "top", name = "Little crown", short = "Crown", price = 30 },
	},
	-- following: each player's own screen moves the pets (no physics, nothing sent as they walk)
	BEHIND = 5, -- studs behind its owner
	SIDE = 2.5, -- and this far to the side
	CATCH_UP = 45, -- further away than this (studs), it pops back beside its owner
	SPEED = 24, -- its top speed, studs a second
	SIT_AFTER = 0.6, -- seconds of its owner standing still before it sits
	NEAR = 60, -- closer to the camera than this (studs): moved every frame
	FAR = 150, -- further than this: not shown at all
	SHOW_AGAIN = 10, -- a hidden pet shows again this many studs nearer than FAR (so it doesn't flicker)
	STEADY = 0.2, -- seconds its owner must stay at a height before it follows (not the top of a jump)
	FAR_STEP = 1 / 20, -- in between: moved at most this often (seconds)
	NAME_DISTANCE = 40, -- its name shows within this many studs
	HOP = 0, -- how fast a pet hops up when its owner jumps (studs a second); 0 for no hop
	GRAVITY = 70, -- how fast a hop slows and comes down
}

-- Find a piece of pet gear by its id.
function Config.petGear(id: string?)
	for _, gear in Config.PETS.GEAR do
		if gear.id == id then
			return gear
		end
	end
	return nil
end

-- Studio only: this many pretend pets walk round you, to check the frame rate with a crowd
-- (say 20). 0 for none. It does nothing outside Studio.
Config.PET_TEST_CROWD = 0

---------------------------------------------------------------- the daily present and the request board

-- A present each day you visit (see server/Daily.luau). Days are counted on the server's
-- clock (UTC), and go round 1 to 7. Missing a day doesn't start you again: your next visit is
-- simply the next day of the seven.
Config.DAILY = {
	COINS = { 5, 6, 7, 8, 10, 12, 15 }, -- coins on days 1 to 7
	-- day 7 also gives the cheapest shop hat you haven't got; if you've got them all, these
	-- coins instead
	ALL_HATS_COINS = 20,
	CHECK_SECONDS = 30, -- how often the server looks to see whether a new day has started
}

-- The request board on the lawn by the fountain: three requests a day, the same for everyone,
-- picked by the day's number. Each pays coins once. (A library request comes back once the
-- library has something to do: Step 22.)
Config.REQUEST_BOARD = { angle = 198, dist = 20.5 } -- where the board stands
Config.REQUESTS_PER_DAY = 3
Config.REQUESTS = {
	{ id = "coins", kind = "coin", need = 15, coins = 8, text = "Pick up 15 coins" },
	{ id = "puddles", kind = "talk", who = "puddles", coins = 4, text = "Say hello to Puddles" },
	{ id = "pebble", kind = "talk", who = "pebble", coins = 4, text = "Say hello to Pebble" },
	{ id = "clover", kind = "talk", who = "clover", coins = 4, text = "Say hello to Clover" },
	{ id = "hat", kind = "hat", coins = 8, text = "Buy a hat at Clover's" },
	{ id = "homepond", kind = "visit", pond = 1, coins = 5, text = "Visit Home Pond" },
	{ id = "lilypond", kind = "visit", pond = 2, coins = 5, text = "Visit Lily Pond" },
	{ id = "gazebo", kind = "visit", at = Config.polar(Config.GAZEBO.angle, Config.GAZEBO.dist), coins = 5, text = "Visit the gazebo" },
}
Config.REQUEST_VISIT_RADIUS = 6 -- web units: how close to a place counts as visiting it
Config.REQUEST_POND_EXTRA = 2 -- for a pond, anywhere on its ring path counts: Config.HOME.ringR plus this

-- Where a "visit" request wants you to go.
function Config.requestSpot(request): Vector3?
	if request.pond then
		local pond = Config.HOME.ponds[request.pond]
		return if pond then Config.polar(pond.angle, pond.dist) else nil
	end
	return request.at
end

-- The day's three requests (indexes into Config.REQUESTS), the same for everyone on that day.
function Config.requestsFor(day: number): { number }
	local random = Random.new(day * 7919 + 11)
	local left = {}
	for i = 1, #Config.REQUESTS do
		table.insert(left, i)
	end
	local picked: { number } = {}
	while #picked < Config.REQUESTS_PER_DAY and #left > 0 do
		local index = table.remove(left, random:NextInteger(1, #left)) :: number
		table.insert(picked, index)
	end
	return picked
end

---------------------------------------------------------------- coins

Config.COIN_RETURN_SECONDS = 180 -- a coin you pick up comes back after this long
Config.COIN_HEIGHT = 0.85 * S -- how high coins float above the ground
Config.COIN_PICK_RADIUS = 1.25 * S -- how close you need to walk
Config.COIN_MAX_PER_MINUTE = 40 -- more pickups than this in a minute are ignored

-- Every coin has a name so the server can check it. Built once, here, so the server and the
-- players always agree (the "random" ones use the same seed everywhere).
Config.COINS = {} :: { { id: string, position: Vector3 } }
do
	local function add(pos: Vector3, height: number?)
		table.insert(Config.COINS, {
			id = "c" .. (#Config.COINS + 1),
			position = pos + Vector3.new(0, height or Config.COIN_HEIGHT, 0),
		})
	end
	-- a ring round the fountain
	for i = 0, 9 do
		add(Config.polar(i * 36 + 18, 8.5))
	end
	-- a trail along each road
	for _, road in Config.ROADS do
		for _, dist in { 21, 30, 39, 48, 57, 65 } do
			add(Config.polar(road.angle, dist))
		end
	end
	-- tucked away behind each shop and the library
	for _, shop in Config.SHOPS do
		add(Config.polar(shop.angle, 35))
	end
	add(Config.polar(Config.LIBRARY.angle, 45))
	-- in front of each cottage, and one in the gazebo
	for _, cottage in Config.COTTAGES do
		local at = Config.cottageAt(cottage)
		add((at * CFrame.new(0, 0, 4.5 * S)).Position)
	end
	add(Config.polar(Config.GAZEBO.angle, Config.GAZEBO.dist), 1.3 * S)
	-- scattered in the meadows between the roads
	local random = Random.new(11)
	for i = 0, 9 do
		local angle = 36 + 72 * (i % 5) + random:NextNumber(-14, 14)
		add(Config.polar(angle, random:NextNumber(50, 66)))
	end
	-- one in the fountain, for anyone who hops in
	add(Config.polar(90, 2.2 * Config.FOUNTAIN_SCALE), 0.95 * S * Config.FOUNTAIN_SCALE)
end

Config.COIN_BY_ID = {} :: { [string]: { id: string, position: Vector3 } }
for _, coin in Config.COINS do
	Config.COIN_BY_ID[coin.id] = coin
end

---------------------------------------------------------------- animals and residents

-- The animals you can be from the start (more join as you make friends, later on).
Config.START_ANIMALS = { "capybara", "bunny", "guineapig" }

-- Who lives in the square in this version. Their looks and lines come from
-- assets/characters/sunnyfolk.json (residents).
Config.RESIDENTS = { "clover", "puddles", "pebble" }

-- Where each resident likes to be in this bigger square (web units: a spot, and how far they
-- stroll from it). Anyone not listed uses their home from sunnyfolk.json.
Config.RESIDENT_HOMES = {
	clover = { at = Config.polar(36, Config.SHOP_DIST - 5.5), r = 1.5 }, -- outside her Hat Shop
	puddles = { at = Config.polar(216, 8.5), r = 2.5 }, -- by the fountain
	pebble = { at = Config.polar(316, 22), r = 3 }, -- near the Post Office
}
Config.RESIDENT_WALK_SPEED = 7

-- Used when a resident says hello for the first time each visit.
Config.GREETINGS = { "Hi", "Hello", "Oh, hi", "Hey there", "Good to see you" }

---------------------------------------------------------------- animation

-- How far from the camera each animal is animated (see client/Animator.luau), in studs.
Config.ANIMATE = {
	NEAR = 60, -- closer than this: every frame
	FAR = 150, -- further than this: standing still
	FAR_STEP = 1 / 20, -- in between: at most this often (seconds), hard to spot at that distance
}

---------------------------------------------------------------- saving

-- How players' saves are kept safe (see server/PlayerData.luau).
Config.SAVE = {
	AUTOSAVE_SECONDS = 120, -- save everyone this often (it also keeps their save locked to this server)
	LOCK_SECONDS = 300, -- a lock not refreshed for this long belongs to a server that's gone
	RETRY_SECONDS = 3, -- when a save is locked or a load fails, wait this long before trying again
	LOAD_TRIES = 6, -- give up (and kindly ask the player to come back) after this many tries
	LEAVE_TRIES = 3, -- tries at the last save when a player leaves
	CHECK_SECONDS = 0.1, -- how often to look again while waiting for another save to finish
	CLOSE_SECONDS = 25, -- how long a closing server waits for everyone's last save
}

---------------------------------------------------------------- guarding the remotes

-- How often each player may ask the server for each thing (see server/RemoteGuard.luau): at
-- most `calls` in any `seconds`. Anything more is quietly ignored. These are well above what
-- normal play needs, so only a script hammering the server notices them.
Config.REMOTE_LIMITS = {
	Buy = { calls = 4, seconds = 2 }, -- buying a hat or clothes
	Wear = { calls = 6, seconds = 2 }, -- putting on or taking off a hat or clothes
	CollectCoin = { calls = 12, seconds = 2 },
	Play = { calls = 3, seconds = 5 },
	SetHome = { calls = 3, seconds = 10 },
	StudioNextDay = { calls = 2, seconds = 2 }, -- Studio only (server/Daily)
	Pet = { calls = 6, seconds = 2 }, -- adopting, changing and dressing your pet (server/Pets)
	Garden = { calls = 8, seconds = 2 }, -- planting, watering and harvesting (server/places/Garden)
	ChooseAdventure = { calls = 4, seconds = 2 }, -- choosing an Adventure on the Goals screen (server/Goals)
	Emote = { calls = 4, seconds = 3 }, -- waving, cheering, dancing, sitting (server/Emotes)
}
-- Changing clothes rebuilds your animal. Quick changes are saved up and done together, at
-- most this often (seconds), so nobody's animal is rebuilt many times a second.
Config.CLOTHES_REBUILD_SECONDS = 1

---------------------------------------------------------------- analytics

Config.ANALYTICS = {
	-- Coin pickups are added up and sent to Roblox's analytics together, once this many seconds
	-- after a player's first uncounted pickup (and when they leave), instead of one per coin.
	PICKUP_SECONDS = 60,
}

---------------------------------------------------------------- badges

-- Badges (see server/Badges.luau). Make each one in the Creator Dashboard (Sunnyfolk >
-- Associated Items > Badges) and paste its id here. A badge whose id is 0 is skipped, so the
-- game works before they exist (in Studio, the Output says when one would have been given).
Config.BADGES = {
	chooseAnimal = 987446869448604, -- chose an animal for the first time (Welcome to Sunnyfolk!)
	firstHat = 2111861747121851, -- got a first hat (Hat Fan)
	firstHome = 3675593365643579, -- made a first home (Home Sweet Home)
	coins = 210790741519207, -- earned Config.BADGE_COINS coins in all (Coin Collector)
	week = 1161193825742019, -- got the day 7 present (Seven Sunny Days)
	allGoals = 2034554655062774, -- finished all the goals (Sunnyfolk Explorer)
}
Config.BADGE_COINS = 100
Config.BADGE_RETRY_SECONDS = 60 -- if Roblox couldn't give a badge, wait this long before asking again

---------------------------------------------------------------- testing

-- Turn this on (true) to check how hats and clothes look: pressing Play in Studio builds a
-- fitting room with every animal wearing everything (see server/Wardrobe.luau). It does
-- nothing outside Studio. Turn it off again to play normally.
Config.WARDROBE_CHECK = false

---------------------------------------------------------------- screens

-- Sizes for the game's screens, which are designed for a landscape phone first.
Config.UI = {
	TOUCH = 44, -- the smallest button, in pixels, on the smallest phone (a child's finger)
	MAX_SCALE = 1.6, -- how much a screen may grow on a tablet or computer
	-- The HUD (coins, buttons, the goal card) grows on taller screens too, a little less:
	-- full size on a screen this many pixels tall, and up to HUD_MAX_SCALE bigger.
	HUD_HEIGHT = 520,
	HUD_MAX_SCALE = 1.4,
	-- A screen less tall than this (pixels) is a phone on its side: the goal card and speech
	-- bubbles are made smaller there, so things don't pile up.
	SHORT_SCREEN = 420,
	-- On a TV (Xbox, PlayStation) players sit across the room, so everything is this much
	-- bigger (Roblox's console guidelines suggest 1.5).
	CONSOLE_SCALE = 1.5,
	-- On a TV, the edges of the picture can be cut off, so the HUD and the buttons at the
	-- bottom keep this far in from the edges (0.05 is 5% of the screen).
	TV_SAFE = 0.05,
	-- The game's buttons ("Talk", "Water"...) on a phone or tablet sit along the bottom, in the
	-- space between Roblox's thumbstick and the Run and jump buttons (client/Prompts):
	PROMPT_HEIGHT = 44, -- how tall each one is (pixels)
	-- the size of their words, and the smallest they may shrink to so a long one fits the space
	PROMPT_TEXT = 17,
	PROMPT_MIN_TEXT = 14,
	PROMPT_BOTTOM = 12, -- how far up from the bottom edge (pixels)
	THUMBSTICK = 0.4, -- the left part of the screen Roblox keeps for the thumbstick (0.4 is 40%)
	-- A screen whose shorter side is this many pixels or less is a phone, where Roblox's jump
	-- button is smaller and lower (client/Run and client/Prompts follow it).
	PHONE_SIZE = 500,
	-- how much of the right side (pixels) to keep clear for Run and jump (client/Run): on a
	-- phone, and on a tablet
	RUN_CLEAR_PHONE = 190,
	RUN_CLEAR_TABLET = 270,
	-- On a short screen (a phone on its side), what a resident says and the big messages
	-- ("Well done!") show at the top left, under Roblox's buttons, one under the other, clear
	-- of the HUD, your animal and the buttons (Ui.messages): how far down from the top and in
	-- from the left (pixels), and how wide at most (a part of the screen's width, and pixels).
	-- Elsewhere a resident's words float over their head and messages sit in the middle.
	MESSAGE_TOP = 64,
	MESSAGE_LEFT = 12,
	MESSAGE_WIDTH = 0.42,
	MESSAGE_MAX_WIDTH = 360,
	-- How long a big message stays (seconds): this long, plus a little for each letter, so a
	-- young reader has time for a long one; never longer than MESSAGE_MAX.
	MESSAGE_SECONDS = 3,
	MESSAGE_LETTER = 0.07,
	MESSAGE_MAX = 10,
	-- How far the picture of you turns (degrees) to show something worn on your back (the shops
	-- and "My things"): three-quarters round, so you see your face too.
	SHOW_BACK_TURN = 150,
	-- The goal's pin goes once you're this close (studs) to where it points: you've arrived,
	-- and it would only cover what you came to see.
	GOAL_PIN_ARRIVED = 25,
	GOAL_PIN_GAP = 12, -- pixels between a garden bed's sign and the goal's pin above it
}

---------------------------------------------------------------- emotes

-- Things your animal can do to say hello without typing (client/Emotes, client/Animator), each
-- with its picture on the emote buttons and how long it lasts (seconds). Sitting lasts until
-- you move. The server only passes the name on, to players within EMOTE_RANGE.
Config.EMOTES = {
	{ id = "wave", icon = "👋", seconds = 1.6 },
	{ id = "cheer", icon = "🎉", seconds = 1.8 },
	{ id = "dance", icon = "💃", seconds = 3.2 },
	{ id = "sit", icon = "💺" }, -- (a seat: an older picture than the chair, so every device has it)
}
Config.EMOTE_BUTTON = "😊" -- the picture on the button that opens them
Config.EMOTE_RANGE = 120 -- studs: players further away than this aren't sent your emote
Config.EMOTE_WAIT = 1 -- seconds between emotes on your own screen (the server has its own limit)

-- An emote by its id, or nil if there isn't one.
function Config.emote(id: any): { id: string, icon: string, seconds: number? }?
	for _, emote in Config.EMOTES do
		if emote.id == id then
			return emote
		end
	end
	return nil
end

---------------------------------------------------------------- players

-- Players can chat using Roblox's own chat, which Roblox filters and keeps to each player's
-- age settings. Set this to false to hide the chat box altogether.
Config.PLAYER_CHAT = true

Config.PLAYER_WALK_SPEED = 16
Config.PLAYER_RUN_SPEED = 26 -- holding Shift, or with the Run button on
Config.PLAYER_JUMP_HEIGHT = 6

return Config
