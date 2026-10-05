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

-- Where you appear (on the ground, facing the fountain).
Config.SPAWN = CFrame.lookAt(Config.fromWeb(0, 11), Vector3.zero)

-- The shops round the square. Only Clover's Hat Shop is open so far.
Config.SHOPS = {
	{ id = "hats", angle = 36, label = "Hat Shop", wall = "#f7e8c8", roof = "#2f8a7c", awning = "#f07055", door = "#1f5f57", sign = "#2f8a7c", open = true },
	{ id = "clothes", angle = 108, label = "Clothes Shop", wall = "#fbe3d2", roof = "#f07055", awning = "#2f8a7c", door = "#1f5f57", sign = "#d9604a" },
	{ id = "pets", angle = 252, label = "Pet Shop", wall = "#e2f1e6", roof = "#f6c64a", awning = "#f07055", door = "#f07055", sign = "#6fa057" },
	{ id = "post", angle = 324, label = "Post Office", wall = "#f7e8c8", roof = "#d9b3dc", awning = "#f6c64a", door = "#f07055", sign = "#2f8a7c" },
}

-- The roads out of town. The places at the end aren't built yet, so each road ends at a gate.
Config.ROADS = {
	{ angle = 0, name = "Kart Track", color = "#f07055" },
	{ angle = 72, name = "Cafe", color = "#2f8a7c" },
	{ angle = 144, name = "Garden", color = "#6fa057" },
	{ angle = 216, name = "Home Pond", color = "#5a8fae", open = true },
	{ angle = 288, name = "Art Studio", color = "#b583b9" },
}

-- Home Pond: the neighbourhood at the end of the Home Pond road, where each player picks a
-- plot for their own house. Its plots sit in a ring round a pond, all facing it.
Config.HOME = {
	angle = 216, -- which way from the fountain
	dist = 96, -- from the fountain to the middle of the pond
	radius = 26, -- the hedge round the neighbourhood
	pondR = 6,
	ringR = 9.5, -- the path round the pond
	plotR = 19.5, -- from the pond's middle to each house
	plots = 10, -- one for each player on a server (set the server size to match)
	wayIn = 40, -- degrees left open for the road in
}

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

---------------------------------------------------------------- coins

Config.COIN_RETURN_SECONDS = 180 -- a coin you pick up comes back after this long
Config.COIN_HEIGHT = 0.85 * S -- how high coins float above the ground
Config.COIN_PICK_RADIUS = 1.25 * S -- how close you need to walk

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

---------------------------------------------------------------- testing

-- Turn this on (true) to check how hats and clothes look: pressing Play in Studio builds a
-- fitting room with every animal wearing everything (see server/Wardrobe.luau). It does
-- nothing outside Studio. Turn it off again to play normally.
Config.WARDROBE_CHECK = false

---------------------------------------------------------------- players

-- Players can chat using Roblox's own chat, which Roblox filters and keeps to each player's
-- age settings. Set this to false to hide the chat box altogether.
Config.PLAYER_CHAT = true

Config.PLAYER_WALK_SPEED = 16
Config.PLAYER_JUMP_HEIGHT = 6

return Config
