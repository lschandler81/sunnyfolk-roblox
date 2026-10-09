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

-- The roads out of town. A road with a `place` carries on into it (the Garden, the Cafe); the
-- others end at a closed gate, for places that aren't built yet.
Config.ROADS = {
	{ angle = 0, name = "Kart Track", color = "#f07055" },
	{ angle = 72, name = "Cafe", color = "#2f8a7c", place = "cafe" }, -- see Config.CAFE
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
	door = 3.6, -- from a plot's middle to just outside its house's front door (the door's buttons)
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

-- The duck pond beside a cottage with `pond` (Puddles' house): x across and z towards the road
-- from the cottage's middle, and its size (web units).
Config.DUCK_POND = { name = "Puddles' pond", x = -9.5, z = -1.5, r = 4.2 }

-- Where a cottage stands (on the ground, its front door facing the road), and the point on the
-- road in front of it.
function Config.cottageAt(cottage): (CFrame, Vector3)
	local road = Config.polar(cottage.road, cottage.dist)
	local spot = road + Config.polar(cottage.road + 90 * cottage.side, Config.COTTAGE_OFFSET)
	return CFrame.lookAt(spot, road) * CFrame.Angles(0, math.pi, 0), road
end

-- The middle of a cottage's duck pond, on the ground.
function Config.duckPond(cottage): CFrame
	local D = Config.DUCK_POND
	return Config.cottageAt(cottage) * CFrame.new(D.x * S, 0, D.z * S)
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

---------------------------------------------------------------- the Cafe

-- Biscuit's Cafe, at the end of the Cafe road (see server/places/Cafe and client/Cafe), from
-- the web game's cafe. Ask Biscuit for a shift: visitors sit at the tables, each with a
-- picture of what they'd like; pick it up at the counter and carry it to their table. When
-- they've eaten and gone, carry their dirty plates to the wash-up tub, so the table is ready
-- for the next visitor. Nobody has to read, nothing has a timer, and a slow order just waits.
-- A friend nearby can join the same shift: the orders are shared, and every helper is paid
-- for every order. The road's arch has a ribbon across it until you've SUN sunshine (the
-- First Story gives exactly that).
-- Distances are web units, like the Garden's.
Config.CAFE = {
	angle = 72, -- which way from the fountain
	dist = 94, -- from the fountain to its middle
	radius = 24, -- its hedge, which joins the town's
	SUN = 4, -- sunshine needed to go in
	GATE_WIDTH = 24, -- the ribbon across the way in (like Config.GARDEN.GATE_WIDTH)
	-- the counter (x across, z towards the way in, from the middle), and its four stations
	COUNTER_Z = -8.2,
	STATIONS = { "cocoa", "cake", "pancakes", "soup" }, -- left to right, as you face the counter
	STATION_X = { -4.5, -1.5, 1.5, 4.5 },
	WASH_X = -7.9, -- the wash-up tub, just past the counter's left end, for dirty plates
	-- the six tables, and the visitors' chairs on the outer side of each
	TABLES = { { -8, -1 }, { -5, 6.5 }, { -9, 12.5 }, { 8, -1 }, { 5, 6.5 }, { 9, 12.5 } },
	CHAIR = 1.35, -- from a table's middle to its chair
	ENTRANCE = 19.5, -- where visitors come in and go out (z)
	MENU = {
		cocoa = { name = "Cocoa" },
		cake = { name = "Yuzu cake" },
		pancakes = { name = "Pancakes" },
		soup = { name = "Pumpkin soup" },
	},
	-- a shift
	ORDERS = 8, -- visitors in a shift (about three minutes); it ends once all their plates are washed
	ORDER_COINS = 2, -- every helper gets this for every order served, whoever served it
	FINISH_COINS = 6, -- and this for finishing the shift
	-- the most coins anyone can earn at the cafe in an hour (HOUR seconds), so shifts can't be
	-- farmed; after that, shifts still work, without coins
	COINS_PER_HOUR = 60,
	HOUR = 60 * 60,
	MAX_HELPERS = 4,
	-- how many visitors wait at once: with 1 helper, 2 helpers, and 3 or more
	WAITING = { 2, 3, 4 },
	FIRST_SECONDS = 1.5, -- after the shift starts, the first visitor comes in
	NEXT_SECONDS = 3, -- the gap between visitors coming in
	ARRIVE_SECONDS = 6, -- a visitor's walk from the way in to their chair
	EAT_SECONDS = 4, -- a visitor eats this long before leaving
	-- how close (studs) a helper must be: to a station's middle (or the wash-up tub's) to pick
	-- food up (or wash up), and to a table's middle to serve it or clear its plates (the server
	-- checks; the buttons show a little closer)
	PICK_REACH = 12,
	SERVE_REACH = 16,
	STATION_BUTTON = 7, -- studs: how close a station's button shows
	TABLE_BUTTON = 11, -- and a table's
	LEAVE = 6, -- web units past the hedge: a helper further out than this has left the shift
	DRAW_DISTANCE = 250, -- studs: visitors are only drawn on your screen this close to the cafe
	CHECK_SECONDS = 0.5, -- how often the server looks after the shift
}

-- The Cafe's middle, on the ground, with +Z pointing back along the road to town.
function Config.cafeFrame(): CFrame
	local K = Config.CAFE
	local centre = Config.polar(K.angle, K.dist)
	return CFrame.lookAt(centre, Vector3.zero) * CFrame.Angles(0, math.pi, 0)
end

-- A spot in the Cafe: x across, z towards the way in (web units from the middle), turned `turn`.
function Config.cafeAt(x: number, z: number, turn: number?): CFrame
	return Config.cafeFrame() * CFrame.new(x * S, 0, z * S) * CFrame.Angles(0, turn or 0, 0)
end

-- Where you stand to use station `i` (in front of the counter), on the ground.
function Config.cafeStation(i: number): CFrame
	return Config.cafeAt(Config.CAFE.STATION_X[i], Config.CAFE.COUNTER_Z + 1.4)
end

-- Where you stand to wash up dirty plates (in front of the tub), on the ground.
function Config.cafeWash(): CFrame
	return Config.cafeAt(Config.CAFE.WASH_X, Config.CAFE.COUNTER_Z + 1.4)
end

-- The middle of table `i`, on the ground.
function Config.cafeTable(i: number): CFrame
	local spot = Config.CAFE.TABLES[i]
	return Config.cafeAt(spot[1], spot[2])
end

-- How many visitors wait at once with `helpers` helpers.
function Config.cafeWaiting(helpers: number): number
	local list = Config.CAFE.WAITING
	return list[math.clamp(helpers, 1, #list)]
end

---------------------------------------------------------------- fishing

-- Fishing at Home Pond, Lily Pond and Puddles' pond (server/Fishing, client/Fishing and
-- client/FishBook), from the web game's fishing.js: cast, wait for the splash, then reel in.
-- The server picks when a fish bites and which fish it is, so tapping fast catches nothing
-- extra. Every fish goes back in the water. A fish new to your Fish Book pays a few coins, and
-- a full book gives a badge (Config.BADGES.fishBook). Nothing is bought: no bait, no rods.
--
-- The web game's Whiskery Catfish and Moonfish only bite at night, and its Puddle Fish only in
-- the rain. This town is always a sunny afternoon (Lighting.ClockTime 14.5 in
-- default.project.json), so those three are left out.
Config.FISHING = {
	REACH = 3.5, -- web units past a pond's edge: how far back you can stand and still fish
	FIRST_BITE = 2.5, -- seconds: until you've caught your first fish, every cast bites this soon
	BITE_MIN = 3, -- after that, a fish bites between BITE_MIN and BITE_MAX seconds after you cast
	BITE_MAX = 7,
	BITE_SECONDS = 3, -- after its splash, a fish waits this long for you to reel in
	LAG = 1, -- seconds the server allows on top of BITE_SECONDS, for the trip there and back
	NEW_COINS = 3, -- coins for a fish that's new in your book (none for one you've caught before)
	NEW_BOOST = 3, -- a fish not in your book yet bites this many times as often, so the book fills
	BOBBER = 0.5, -- where the bobber lands: this far in from the pond's edge to its middle
	BOBBER_GAP = 8, -- studs: standing in the water, it lands at least this far in front of you
	WATER_Y = 0.25, -- studs: the top of the ponds' water (server/Town)
	-- where: "any" pond, "pond" (Home Pond and Puddles' pond) or "lake" (Lily Pond). weight: how
	-- often it bites, against the others in that pond. The colours and shapes are the web game's.
	-- (The rarer ones bite a little more often here than there, so the book can be filled.)
	FISH = {
		{ id = "minnow", name = "Minnow", where = "any", weight = 10, body = "#b8c4c8", fin = "#8e9ca2", size = 0.6 },
		{ id = "goldfish", name = "Goldfish", where = "pond", weight = 7, body = "#f28a3a", fin = "#f6c64a", size = 0.7 },
		{ id = "bluegill", name = "Bluegill", where = "any", weight = 6, body = "#5aa9a8", fin = "#3f6f8a", size = 0.8 },
		{ id = "perch", name = "Stripy Perch", where = "lake", weight = 6, body = "#c9c25a", fin = "#e8743b", stripes = "#5a6a3a", size = 0.85 },
		{ id = "trout", name = "Spotty Trout", where = "lake", weight = 5, body = "#a88a62", fin = "#8a6a48", spots = "#5a4436", size = 0.95 },
		{ id = "koi", name = "Koi", where = "pond", weight = 4, body = "#faf3e8", fin = "#f2b8a0", spots = "#e8603a", size = 0.95 },
		{ id = "rainbow", name = "Rainbow Trout", where = "lake", weight = 3, body = "#b8c8c0", fin = "#9aa8a0", stripes = "#f28ab0", size = 1.0 },
		{ id = "yuzufish", name = "Yuzu Fish", where = "any", weight = 2, body = "#f6d84a", fin = "#8cc63f", round = true, size = 0.8 },
		{ id = "golden", name = "Golden Fish", where = "any", weight = 1, body = "#f2c14e", fin = "#e8a830", glow = true, size = 1.0 },
	},
}

-- The ponds you can fish in: each one's name, middle (on the ground), size (web units) and
-- which fish live there ("pond" or "lake").
Config.FISHING_PONDS = {} :: { { name: string, centre: Vector3, r: number, kind: string } }
do
	local H = Config.HOME
	for i, pond in H.ponds do
		table.insert(Config.FISHING_PONDS, {
			name = pond.name,
			centre = Config.polar(pond.angle, pond.dist),
			r = H.pondR,
			kind = if i == 1 then "pond" else "lake", -- Home Pond, then Lily Pond
		})
	end
	for _, cottage in Config.COTTAGES do
		if cottage.pond then
			table.insert(Config.FISHING_PONDS, {
				name = Config.DUCK_POND.name,
				centre = Config.duckPond(cottage).Position,
				r = Config.DUCK_POND.r,
				kind = "pond",
			})
		end
	end
end

-- A fish by its id, or nil if there isn't one.
function Config.fish(id: any)
	for _, fish in Config.FISHING.FISH do
		if fish.id == id then
			return fish
		end
	end
	return nil
end

-- How many of each fish a Fish Book (as saved: { caught = { fish = count } }) has.
function Config.fishCaught(book: any): { [string]: number }
	local caught = if typeof(book) == "table" and typeof(book.caught) == "table" then book.caught else {}
	local counts = {}
	for _, fish in Config.FISHING.FISH do
		local n = caught[fish.id]
		if typeof(n) == "number" and n > 0 then
			counts[fish.id] = n
		end
	end
	return counts
end

-- Is every fish in the book?
function Config.fishBookFull(book: any): boolean
	local caught = Config.fishCaught(book)
	for _, fish in Config.FISHING.FISH do
		if not caught[fish.id] then
			return false
		end
	end
	return true
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

---------------------------------------------------------------- inside your house

-- Going inside your house: a living room, a kitchen and a bedroom upstairs, to decorate with
-- furniture from the web game's furniture.js (see shared/Furniture, server/Interiors and
-- client/Decorator). Sizes are in floor tiles (one web unit, Config.STUDS each). A house is
-- only built while its owner is inside, far away from town, and only its owner can go in.
Config.ROOM = {
	-- where houses are built: a row of spots this far apart (studs), well past what Roblox
	-- loads round each player, so nobody's screen ever loads anyone else's house
	ORIGIN = Vector3.new(0, 0, 3000),
	GAP = 1100,
	WALL_H = 3.2, -- how tall the walls are
	UPSTAIRS = 3.4, -- how high the bedroom floor is (on top of the living room's walls)
	-- Your screen hides everything upstairs while you're downstairs, so the bedroom's floor never
	-- gets in the camera's way; it shows once you're this far up the stairs (0 to 1).
	SHOW_UPSTAIRS = 0.6,
	WALL_Y = 1.85, -- how high things hang on a wall (their middle, above the floor)
	LAWN = { w = 44, d = 30, x = 1, z = 2 }, -- the grass round the house: its size and middle
	MAX_PIECES = 20, -- furniture in each room
	MAX_OWNED = 60, -- furniture a player can own in all (no more than fits in all the rooms)
	DOOR_REACH = 18, -- studs: how close to your front door you must be to go in
	FAR = 90, -- studs from a house's middle: anyone further away isn't in it
	CHECK_SECONDS = 2, -- how often the server looks to see who's in which house
	FADE_SECONDS = 0.35, -- the screen fades out and in as you go in and out
	-- decorating (client/Decorator): the camera looks down into the room at this angle (degrees),
	-- from the front at first (the turn buttons take it round to each side), from far
	-- enough back to see the whole room with this much room to spare (1 just fits); and a
	-- piece you're holding floats this high (tiles) over its spot
	CAMERA_PITCH = 60,
	CAMERA_ROOM = 1.15,
	-- after decorating, and going in or out, the camera goes back behind your animal: this far
	-- behind and this high (studs)
	CAMERA_BEHIND = { distance = 16, height = 6 },
	HOLD_LIFT = 0.25,
	-- walking round inside: a wall between your animal and where the camera wants to be (up to
	-- REACH studs behind you) fades to see-through (FADE: 0 solid, 1 gone), like a dollhouse,
	-- checked this often (seconds). Roblox's camera doesn't bump into a faded wall.
	CUTAWAY = { REACH = 60, FADE = 0.8, SECONDS = 0.1 },
	-- The rooms. x and z: where each room's middle is in the house (tiles). `up`: upstairs.
	-- `front`: the front door, on the inside of the front wall (first tile and how wide; you go out
	-- with the "Go outside" button by it). `doors`: gaps in the
	-- walls to the next room (first tile from the back, or from the left, and how wide).
	-- `clear`: tiles kept free of furniture (doorways, the stairs), as x, z, width, depth.
	-- `noHang`: walls nothing hangs on, or (as a list) the stretches of a wall nothing hangs on
	-- (first tile and how many). `hole`: where the stairs come up through an upstairs floor
	-- (x, z, width, depth), with a banister along its open side.
	ROOMS = {
		{
			id = "living", name = "Living room", short = "Living", icon = "🛋️", w = 12, d = 9, x = 0, z = 0,
			front = { 5, 2 },
			doors = { left = { { 3, 2 } } },
			-- (the front door's two rows keep the spot where you come in clear)
			clear = { { 5, 7, 2, 2 }, { 0, 3, 1, 2 }, { 10, 0, 2, 9 } },
			-- (the stairs run along the right wall, and the landing covers the back wall's end)
			noHang = { right = true, back = { { 10, 2 } } },
			stairs = true,
		},
		{
			id = "kitchen", name = "Kitchen", short = "Kitchen", icon = "🍳", w = 8, d = 9, x = -10.6, z = 0,
			doors = { right = { { 3, 2 } } },
			clear = { { 7, 3, 1, 2 } },
		},
		{
			-- right over the living room, the same size
			id = "bedroom", name = "Bedroom", short = "Bedroom", icon = "🛏️", w = 12, d = 9, x = 0, z = 0, up = true,
			-- (the stairs come up at the back right: keep where you arrive clear too)
			clear = { { 10, 0, 2, 9 } },
			hole = { 10, 2, 2, 7 },
		},
	},
	-- The stairs in the living room, up its right side from near the front to the back, coming
	-- up through the bedroom's floor (its `hole`): which tiles across, and where they start and
	-- end (z, tiles from the room's middle). `guardFrom`: how far up (0 to 1) the invisible wall
	-- on the open side starts, so the bottom steps can be stepped onto from the side.
	STAIRS = { x = 10, w = 2, bottom = 3, top = -2.5, steps = 10, guardFrom = 0.35 },
	-- Furniture (from furniture.js, with its prices), in the order the shop shows it. w and d:
	-- the tiles it covers. `layer`: "floor" (you bump into it), "rug" (you walk on it) or
	-- "wall" (it hangs on a wall). `tall`: how high you bump into it.
	PIECES = {
		{ id = "bed", name = "Cosy bed", price = 40, w = 2, d = 3, layer = "floor", tall = 0.9 },
		{ id = "rug", name = "Round rug", price = 15, w = 3, d = 3, layer = "rug" },
		{ id = "armchair", name = "Armchair", price = 30, w = 2, d = 2, layer = "floor", tall = 1.3 },
		{ id = "bookshelf", name = "Bookshelf", price = 25, w = 2, d = 1, layer = "floor", tall = 1.9 },
		{ id = "plant", name = "Potted plant", price = 10, w = 1, d = 1, layer = "floor", tall = 1.2 },
		{ id = "stove", name = "Cosy stove", price = 35, w = 2, d = 1, layer = "floor", tall = 1.2 },
		{ id = "table", name = "Round table", price = 20, w = 2, d = 2, layer = "floor", tall = 0.9 },
		{ id = "stool", name = "Comfy stool", price = 8, w = 1, d = 1, layer = "floor", tall = 0.65 },
		{ id = "wardrobe", name = "Wardrobe", price = 30, w = 2, d = 1, layer = "floor", tall = 2.4 },
		{ id = "lamp", name = "Floor lamp", price = 18, w = 1, d = 1, layer = "floor", tall = 2 },
		-- (not in furniture.js: priced like its toy box and wall clock)
		{ id = "petBed", name = "Pet bed", price = 12, w = 1, d = 1, layer = "floor", tall = 0.35 },
		{ id = "picture", name = "Sunny picture", price = 12, w = 2, d = 1, layer = "wall" },
	},
	-- Wallpapers and floors. Each room has its own; one bought can be used in every room.
	WALLS = {
		{ id = "cream", name = "Cream", color = "#f6e7cf", trim = "#d9b48a", price = 0 },
		{ id = "mint", name = "Mint", color = "#cfeadc", trim = "#8fbfa6", price = 10 },
		{ id = "peach", name = "Peach", color = "#f9d9c6", trim = "#e0a184", price = 10 },
	},
	FLOORS = {
		{ id = "honey", name = "Honey wood", color = "#d9a46c", line = "#b8844e", price = 0 },
		{ id = "pale", name = "Pale wood", color = "#ead2a8", line = "#cdb084", price = 10 },
		{ id = "mintTiles", name = "Mint tiles", color = "#bfe0cf", line = "#9cc7b2", price = 10, tiles = true },
	},
	-- A new house: one free piece in each room, so it feels like home straight away.
	START = {
		living = { { id = "rug", x = 4, z = 3, r = 0 } },
		kitchen = { { id = "stove", x = 3, z = 0, r = 0 } },
		bedroom = { { id = "bed", x = 7, z = 0, r = 0 } },
	},
}

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

-- Who lives in town in this version. Their looks and lines come from
-- assets/characters/sunnyfolk.json (residents). Chef Pepper needs guineapig-grumpy.glb
-- imported into SunnyfolkModels; until it is, he stays away (server/Residents).
Config.RESIDENTS = { "clover", "puddles", "pebble", "biscuit", "pepper" }

-- Where each resident likes to be in this bigger square (web units: a spot, and how far they
-- stroll from it). Anyone not listed uses their home from sunnyfolk.json.
Config.RESIDENT_HOMES = {
	clover = { at = Config.polar(36, Config.SHOP_DIST - 5.5), r = 1.5 }, -- outside her Hat Shop
	puddles = { at = Config.polar(216, 8.5), r = 2.5 }, -- by the fountain
	pebble = { at = Config.polar(316, 22), r = 3 }, -- near the Post Office
	biscuit = { at = Config.cafeAt(0, -9.8).Position, r = 1 }, -- behind her counter
	pepper = { at = Config.cafeAt(6.4, -10.6).Position, r = 0.6 }, -- by his stove
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
	Cafe = { calls = 8, seconds = 2 }, -- starting a shift, picking up food, serving (server/places/Cafe)
	Fish = { calls = 6, seconds = 2 }, -- casting, reeling in, putting the rod away (server/Fishing)
	Room = { calls = 10, seconds = 2 }, -- going in and out, buying and placing furniture (server/Interiors)
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
	fishBook = 0, -- filled the Fish Book (FISH_BOOK_BADGE_ID: make it, then paste its id here)
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
	-- The note on a gate that isn't open yet ("Fern's Garden opens once...") shows only this
	-- close (studs), when you're at the gate, so it doesn't hang in the sky over the town.
	GATE_SIGN_DISTANCE = 30,
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
