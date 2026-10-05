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

Config.PLAZA_R = 10 -- web units: the paved circle round the fountain
Config.FOUNTAIN_R = 3.4 -- web units: keep walkers this far from the middle
Config.EDGE_R = 34 -- web units: the hedge round the town; nobody walks past it

-- Where you appear (on the ground, facing the fountain).
Config.SPAWN = CFrame.lookAt(Config.fromWeb(0, 6.2), Vector3.zero)

-- The shops round the square. Only Clover's Hat Shop is open so far.
Config.SHOPS = {
	{ id = "hats", angle = 36, label = "Hat Shop", wall = "#f7e8c8", roof = "#2f8a7c", awning = "#f07055", door = "#1f5f57", sign = "#2f8a7c", open = true },
	{ id = "clothes", angle = 108, label = "Clothes Shop", wall = "#fbe3d2", roof = "#f07055", awning = "#2f8a7c", door = "#1f5f57", sign = "#d9604a" },
	{ id = "pets", angle = 252, label = "Pet Shop", wall = "#e2f1e6", roof = "#f6c64a", awning = "#f07055", door = "#f07055", sign = "#6fa057" },
	{ id = "post", angle = 324, label = "Post Office", wall = "#f7e8c8", roof = "#d9b3dc", awning = "#f6c64a", door = "#f07055", sign = "#2f8a7c" },
}
Config.SHOP_DIST = 19.5 -- web units from the fountain to each shop's middle

-- The roads out of town. The places at the end aren't built yet, so each road ends at a gate.
Config.ROADS = {
	{ angle = 0, name = "Kart Track", color = "#f07055" },
	{ angle = 72, name = "Cafe", color = "#2f8a7c" },
	{ angle = 144, name = "Garden", color = "#6fa057" },
	{ angle = 216, name = "Home Pond", color = "#5a8fae" },
	{ angle = 288, name = "Art Studio", color = "#b583b9" },
}

---------------------------------------------------------------- coins

Config.COIN_RETURN_SECONDS = 180 -- a coin you pick up comes back after this long
Config.COIN_HEIGHT = 0.85 * S -- how high coins float above the ground
Config.COIN_PICK_RADIUS = 1.25 * S -- how close you need to walk

-- Every coin has a name so the server can check it. Built once, here, so the server and the
-- players always agree.
Config.COINS = {} :: { { id: string, position: Vector3 } }
do
	local function add(pos: Vector3, height: number?)
		table.insert(Config.COINS, {
			id = "c" .. (#Config.COINS + 1),
			position = pos + Vector3.new(0, height or Config.COIN_HEIGHT, 0),
		})
	end
	-- a ring round the fountain
	for i = 0, 5 do
		add(Config.polar(i * 60 + 30, 6.5))
	end
	-- a little trail along each road
	for _, road in Config.ROADS do
		for _, dist in { 13, 19, 25 } do
			add(Config.polar(road.angle, dist))
		end
	end
	-- tucked away behind each shop
	for _, shop in Config.SHOPS do
		add(Config.polar(shop.angle, 25))
	end
	-- one in the fountain, for anyone who hops in
	add(Config.polar(90, 2.2), 0.95 * S)
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
Config.RESIDENT_WALK_SPEED = 7

-- Used when a resident says hello for the first time each visit.
Config.GREETINGS = { "Hi", "Hello", "Oh, hi", "Hey there", "Good to see you" }

---------------------------------------------------------------- players

-- Players can chat using Roblox's own chat, which Roblox filters and keeps to each player's
-- age settings. Set this to false to hide the chat box altogether.
Config.PLAYER_CHAT = true

Config.PLAYER_WALK_SPEED = 16
Config.PLAYER_JUMP_HEIGHT = 6

return Config
