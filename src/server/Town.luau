-- Builds the town square when the game starts: the grass, the paved plaza, the fountain, the
-- shops, lamps with bunting, benches, flower planters, trees, a signpost, and gates on the
-- roads to places that aren't built yet. It all goes in Workspace.Town.
--
-- Sizes and places follow the web game (src/world/hub.js and props.js). They're written in
-- web units times S, so they're easy to compare.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Builder = require(Shared.CharacterBuilder)
local Config = require(Shared.Config)

local S = Config.STUDS

local Build = require(Shared.Build)

local C, FLOWERS, DECOR, LAMP_H = Build.C, Build.FLOWERS, Build.DECOR, Build.LAMP_H
local block, cylinder, ball, blob, label, yawAt = Build.block, Build.cylinder, Build.ball, Build.blob, Build.label, Build.yawAt
local flower, lamp, bunting, bench, planter = Build.flower, Build.lamp, Build.bunting, Build.bench, Build.planter
local bush, tree, house = Build.bush, Build.tree, Build.house
local random = Build.random

local Town = {}

local folder: Folder

---------------------------------------------------------------- the fountain

local function fountain()
	local o = CFrame.identity
	local F = S * Config.FOUNTAIN_SCALE
	-- the basin: a stone floor and a low round wall
	cylinder(3.2 * F, 0.3 * F, o * CFrame.new(0, 0.15 * F, 0), C.stone)
	local n = 32
	local wallR = 3.05 * F
	for i = 0, n - 1 do
		local a = (i / n) * math.pi * 2
		local at = CFrame.Angles(0, a, 0) * CFrame.new(0, 0, wallR)
		local width = 2 * math.pi * wallR / n * 1.15
		block(Vector3.new(width, 0.75 * F, 0.5 * F), at * CFrame.new(0, 0.42 * F, 0), C.stone)
		block(Vector3.new(width * 1.05, 0.12 * F, 0.62 * F), at * CFrame.new(0, 0.82 * F, 0), C.stoneDark)
	end
	-- the water
	cylinder(2.86 * F, 0.1 * F, o * CFrame.new(0, 0.58 * F, 0), C.water, { CanCollide = false, Transparency = 0.1, Reflectance = 0.1 })
	-- the middle: a column, the upper bowl and a giant stone yuzu on top
	cylinder(0.42 * F, 1.5 * F, o * CFrame.new(0, 1.0 * F, 0), C.stone)
	cylinder(1.4 * F, 0.4 * F, o * CFrame.new(0, 1.95 * F, 0), C.stone)
	cylinder(1.22 * F, 0.06 * F, o * CFrame.new(0, 2.16 * F, 0), C.water, { CanCollide = false, Reflectance = 0.1 })
	cylinder(0.2 * F, 0.6 * F, o * CFrame.new(0, 2.4 * F, 0), C.stone)
	local yuzu = ball(0.9 * F, o * CFrame.new(0, 2.95 * F, 0), C.yuzu)
	cylinder(0.04 * F, 0.2 * F, o * CFrame.new(0, 3.45 * F, 0), C.woodDark, DECOR)
	blob(Vector3.new(0.36, 0.06, 0.18) * F, o * CFrame.new(0.17 * F, 3.48 * F, 0) * CFrame.Angles(0, 0, 0.4), C.leaf, DECOR)
	-- water falling from the upper bowl into the basin
	cylinder(1.5 * F, 1.5 * F, o * CFrame.new(0, 1.38 * F, 0), C.waterLight, { CanCollide = false, CanQuery = false, Transparency = 0.6, CastShadow = false })
	-- and a little spray from the top
	local spout = Instance.new("Attachment")
	spout.Position = Vector3.new(0, 0.5 * F, 0)
	spout.Parent = yuzu
	local spray = Instance.new("ParticleEmitter")
	spray.Color = ColorSequence.new(Color3.fromHex("#e9fbff"), C.water)
	spray.Size = NumberSequence.new(0.35, 0.12)
	spray.Transparency = NumberSequence.new(0.1, 1)
	spray.Lifetime = NumberRange.new(0.8, 1.1)
	spray.Speed = NumberRange.new(12, 16)
	spray.SpreadAngle = Vector2.new(22, 22)
	spray.Acceleration = Vector3.new(0, -30, 0)
	spray.Rate = 45
	spray.LightEmission = 0.3
	spray.Parent = spout
end

---------------------------------------------------------------- shops

-- A cosy house with its front door facing +Z of `at`. Sizes are in web units. Returns the
-- spot just outside the front door.
-- A little round table with a hat on it, outside the Hat Shop.
local function hatStand(at: CFrame, hatId: string)
	cylinder(0.08 * S, 1.0 * S, at * CFrame.new(0, 0.5 * S, 0), C.tealDeep)
	cylinder(0.45 * S, 0.08 * S, at * CFrame.new(0, 1.04 * S, 0), C.cream)
	local hat = Builder.hatModel("capybara", hatId)
	if hat then
		hat:PivotTo(at * CFrame.new(0, 1.08 * S, 0) * CFrame.Angles(0, math.pi, 0))
		hat.Parent = folder
	end
end

-- A closed gate at the end of a road, for a place that's coming soon.
-- A gate at the end of a road. `open` is an arch to walk through; otherwise it's closed
-- with a ribbon, for a place that's coming soon.
local function gate(at: CFrame, name: string, color: Color3, open: boolean?)
	for _, side in { -1, 1 } do
		cylinder(0.24 * S, 4.2 * S, at * CFrame.new(side * 2.3 * S, 2.1 * S, 0), C.wood)
		ball(0.6 * S, at * CFrame.new(side * 2.3 * S, 4.35 * S, 0), color)
		bush(at * CFrame.new(side * 2.3 * S, 0, 0.5 * S), 0.7)
	end
	block(Vector3.new(5.4, 0.3, 0.4) * S, at * CFrame.new(0, 4.05 * S, 0), C.woodDark)
	local board = block(Vector3.new(3.6, 0.8, 0.12) * S, at * CFrame.new(0, 3.35 * S, 0.1 * S) * CFrame.Angles(0, math.pi, 0), C.cream)
	label(board, name, C.ink, C.cream)
	label(board, name, C.ink, C.cream, Enum.NormalId.Back)
	if open then
		return
	end
	-- a ribbon across, and a little sign
	block(Vector3.new(4.4, 0.12, 0.06) * S, at * CFrame.new(0, 1.2 * S, 0), color)
	local soon = block(Vector3.new(1.8, 0.6, 0.08) * S, at * CFrame.new(0, 1.0 * S, 0.08 * S) * CFrame.Angles(0, math.pi, 0.05), color, DECOR)
	label(soon, "Opening soon!", C.cream)
end

-- The signpost: one board pointing down each road.
local function signpost(at: Vector3)
	local h = 4.3 * S
	cylinder(0.12 * S, h, CFrame.new(at + Vector3.new(0, h / 2, 0)), C.woodDark)
	ball(0.34 * S, CFrame.new(at + Vector3.new(0, h + 0.05 * S, 0)), C.coral, DECOR)
	bush(CFrame.new(at), 0.6)
	for i, road in Config.ROADS do
		local target = Config.polar(road.angle, 30)
		local dir = Vector3.new(target.X - at.X, 0, target.Z - at.Z).Unit
		local y = (3.85 - (i - 1) * 0.42) * S
		local centre = at + dir * 1.05 * S + Vector3.new(0, y, 0)
		local board = block(Vector3.new(2.0, 0.4, 0.08) * S, CFrame.fromMatrix(centre, dir, Vector3.yAxis), C.cream, DECOR)
		label(board, road.name, Color3.fromHex(road.color), C.cream, Enum.NormalId.Front)
		label(board, road.name, Color3.fromHex(road.color), C.cream, Enum.NormalId.Back)
	end
end

---------------------------------------------------------------- keeping space clear

-- Places scenery (trees, bushes, flowers, rocks) mustn't go: buildings, the plaza and paths.
local clear: { { at: Vector3, r: number } } = {}
local paths: { { a: Vector3, b: Vector3, w: number } } = {}

local function keepClear(at: Vector3, radius: number)
	table.insert(clear, { at = at, r = radius * S })
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Is `spot` at least `margin` web units from everything that needs space?
local function isClear(spot: Vector3, margin: number): boolean
	for _, c in clear do
		if flat(spot - c.at).Magnitude < c.r + margin * S then
			return false
		end
	end
	for _, p in paths do
		local along = p.b - p.a
		local t = math.clamp((spot - p.a):Dot(along) / along:Dot(along), 0, 1)
		if flat(spot - (p.a + along * t)).Magnitude < p.w / 2 + margin * S then
			return false
		end
	end
	return true
end

-- A flat strip of path on the grass from `a` to `b`, `width` web units wide.
local function footpath(a: Vector3, b: Vector3, width: number, top: number?)
	a, b = flat(a), flat(b)
	local length = (b - a).Magnitude
	local at = CFrame.lookAt((a + b) / 2, b) + Vector3.new(0, (top or 0.07) - 0.05, 0)
	block(Vector3.new(width * S, 0.1, length), at, C.path)
	table.insert(paths, { a = a, b = b, w = width * S })
end

---------------------------------------------------------------- lawn things

local function flowerBed(at: CFrame, radius: number)
	cylinder(radius * S, 0.4 * S, at * CFrame.new(0, 0.2 * S, 0), C.stone)
	cylinder((radius - 0.15) * S, 0.06 * S, at * CFrame.new(0, 0.4 * S, 0), C.soil, DECOR)
	local n = math.round(radius * 7)
	for i = 1, n do
		local a = i * 2.4
		local r = math.sqrt(i / n) * (radius - 0.35)
		flower(at * CFrame.new(math.cos(a) * r * S, 0.4 * S, math.sin(a) * r * S), FLOWERS[(i % #FLOWERS) + 1], random:NextNumber(0.3, 0.5) * S)
	end
end

local function flowerPatch(at: Vector3)
	for i = 1, 6 do
		local a = random:NextNumber(0, math.pi * 2)
		local r = random:NextNumber(0, 1.3) * S
		flower(CFrame.new(at + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)), FLOWERS[(i % #FLOWERS) + 1], random:NextNumber(0.25, 0.45) * S)
	end
end

local function rock(at: Vector3, s: number)
	blob(Vector3.new(1.1, 0.6, 0.9) * s * S, CFrame.new(at + Vector3.new(0, 0.15 * s * S, 0)) * CFrame.Angles(0, random:NextNumber(0, 6), 0), C.stone)
end

-- A little pond with stones round the edge and lily pads.
local function pond(at: CFrame, radius: number)
	cylinder(radius * S, 0.3, at * CFrame.new(0, 0.1, 0), C.water, { CanCollide = false, Reflectance = 0.05 })
	local stones = math.round(radius * 4.3)
	for i = 0, stones - 1 do
		local s = random:NextNumber(0.7, 1.1)
		blob(Vector3.new(0.9, 0.45, 0.7) * s * S, at * CFrame.Angles(0, i / stones * math.pi * 2, 0) * CFrame.new(0, 0.1 * S, (radius + 0.1) * S), C.stone, DECOR)
	end
	for i = 1, math.round(radius * 1.5) do
		local a = random:NextNumber(0, math.pi * 2)
		local r = random:NextNumber(0.8, radius - 1) * S
		local pad = at * CFrame.new(math.cos(a) * r, 0.27, math.sin(a) * r)
		cylinder(0.45 * S, 0.04, pad, C.leaf, DECOR)
		if i % 3 == 0 then
			ball(0.3 * S, pad * CFrame.new(0, 0.1 * S, 0), Color3.fromHex("#f6b8d0"), DECOR)
		end
	end
	for i = 0, 4 do
		local reedAt = at * CFrame.Angles(0, 2.2 + i * 0.25, 0) * CFrame.new(0, 0, (radius - 0.6) * S)
		cylinder(0.05 * S, 1.2 * S, reedAt * CFrame.new(0, 0.6 * S, 0), C.leafDark, DECOR)
		block(Vector3.new(0.12, 0.35, 0.12) * S, reedAt * CFrame.new(0, 1.2 * S, 0), C.woodDark, DECOR)
	end
	keepClear(at.Position, radius + 0.8)
end

---------------------------------------------------------------- the square

local function plaza()
	-- the grass, then the paving in rings
	block(Vector3.new(1600, 4, 1600), CFrame.new(0, -2, 0), C.grass)
	local k = Config.PLAZA_R / 10
	local function ring(radius: number, top: number, color: Color3)
		cylinder(radius * k * S, 0.1, CFrame.new(0, top - 0.05, 0), color)
	end
	-- Flat layers are kept at least 0.04 studs apart, or the screen can't tell which is on top:
	-- plots 0.03, footpaths 0.07, roads 0.11, then the paving rings. They're all solid, so
	-- feet stand on top of them rather than sinking in.
	ring(10.6, 0.15, C.stoneDark)
	ring(10, 0.19, C.plaza)
	ring(7.7, 0.23, C.creamDeep)
	ring(7.4, 0.27, C.plazaLight)
	ring(4.8, 0.31, C.creamDeep)
	ring(4.2, 0.35, C.plaza)
	-- spokes in the paving
	for i = 0, 19 do
		local inner, outer = 4.8 * k, 7.4 * k
		local mid = Config.polar(i * 18 + 9, (inner + outer) / 2)
		block(Vector3.new(0.25 * S, 0.1, (outer - inner) * S), yawAt(mid + Vector3.new(0, 0.24, 0), Config.faceIn(i * 18 + 9)), C.creamDeep)
	end
	keepClear(Vector3.zero, Config.PLAZA_R + 2)

	-- lamps all round the edge, with bunting between them
	local lamps = {}
	for i = 0, 19 do
		local spot = Config.polar(i * 18 + 9, Config.PLAZA_R + 0.4)
		lamp(CFrame.new(spot))
		table.insert(lamps, spot + Vector3.new(0, (LAMP_H - 0.2) * S, 0))
	end
	for i = 1, #lamps do
		bunting(lamps[i], lamps[(i % #lamps) + 1])
	end

	-- benches in two rings, round flower beds, and planters in front of the shops
	for i = 0, 4 do
		local a = 36 + i * 72
		for _, side in { -1, 1 } do
			bench(yawAt(Config.polar(a + side * 18, 11), Config.faceIn(a + side * 18)))
			bench(yawAt(Config.polar(a + side * 12, Config.PLAZA_R - 1.6), Config.faceIn(a + side * 12)))
		end
		flowerBed(CFrame.new(Config.polar(a, 11)), 1.3)
		if a ~= 180 then
			planter(yawAt(Config.polar(a, Config.PLAZA_R + 2.2), Config.faceIn(a)), 3.2, 1.1)
		end
	end
end

-- The roads out of town, with street lamps, ending at gates.
local function roads()
	for _, road in Config.ROADS do
		if road.open then
			-- this one carries on to Home Pond, where an arch welcomes you in (see homePond)
			local H = Config.HOME
			local home = H.ponds[1]
			footpath(Config.polar(road.angle, Config.PLAZA_R - 0.5), Config.polar(road.angle, home.dist - H.ringR), Config.ROAD_W, 0.11)
		else
			footpath(Config.polar(road.angle, Config.PLAZA_R - 0.5), Config.polar(road.angle, Config.EDGE_R + 1), Config.ROAD_W, 0.11)
			gate(yawAt(Config.polar(road.angle, Config.EDGE_R - 0.5), Config.faceIn(road.angle)), road.name, Color3.fromHex(road.color))
		end
	end
end

local function streetLamps()
	for _, road in Config.ROADS do
		for i, dist in { 26, 36, 46, 56, 64 } do
			local side = if i % 2 == 0 then 1 else -1
			local spot = Config.polar(road.angle, dist) + Config.polar(road.angle + 90 * side, Config.ROAD_W / 2 + 0.9)
			if isClear(spot, 0.4) then
				lamp(CFrame.new(spot))
				keepClear(spot, 1)
			end
		end
	end
end

local function shops(): { [string]: CFrame }
	local doors = {}
	for _, shop in Config.SHOPS do
		local at = yawAt(Config.polar(shop.angle, Config.SHOP_DIST), Config.faceIn(shop.angle))
		local door = house(at, {
			w = 6.5,
			d = 5,
			h = 3.4,
			wall = Color3.fromHex(shop.wall),
			roof = Color3.fromHex(shop.roof),
			door = Color3.fromHex(shop.door),
			awning = Color3.fromHex(shop.awning),
			label = shop.label,
			sign = Color3.fromHex(shop.sign),
		})
		doors[shop.id] = door
		footpath(Config.polar(shop.angle, Config.PLAZA_R), door.Position, 2.6)
		keepClear(at.Position, 7)
		if shop.id == "hats" then
			-- three hats on show beside the door, next to where Clover stands
			for i, hatId in { "flowers", "party", "sunhat" } do
				hatStand(at * CFrame.new(-(1.3 + i * 1.1) * S, 0, 4.6 * S), hatId)
			end
		elseif not shop.open then
			local sign = block(Vector3.new(1.6, 0.5, 0.06) * S, door * CFrame.new(0, 1.35 * S, -0.7 * S) * CFrame.Angles(0, math.pi, 0), C.cream, DECOR)
			label(sign, "Opening soon!", C.ink, C.cream)
		end
	end
	return doors
end

-- The library on the south lawn: a porch on columns, steps, and two giant books.
local function library()
	local L = Config.LIBRARY
	local at = yawAt(Config.polar(L.angle, L.dist), Config.faceIn(L.angle))
	local w, d = 9, 6
	local blue = Color3.fromHex("#4a5aa8")
	local door = house(at, { w = w, d = d, h = 4, wall = Color3.fromHex("#e6eef7"), roof = blue, door = C.coral, label = "Library", sign = blue, chimney = false, yard = false })
	local front = d / 2
	for _, side in { -1, 1 } do
		for _, x in { 1.3, w / 2 - 0.5 } do
			cylinder(0.22 * S, 3.4 * S, at * CFrame.new(side * x * S, 2.05 * S, (front + 1.0) * S), C.white)
		end
	end
	block(Vector3.new(w + 0.4, 0.3, 1.6) * S, at * CFrame.new(0, 3.9 * S, (front + 0.75) * S), blue)
	block(Vector3.new(w - 0.4, 0.18, 1.4) * S, at * CFrame.new(0, 0.09 * S, (front + 0.9) * S), C.stone, DECOR)
	for _, book in { { -1.9, C.coral, 0.3, 0.1 }, { 1.95, C.teal, -0.25, -0.12 } } do
		local bookAt = at * CFrame.new(book[1] * S, 0.8 * S, (front + 1.9) * S) * CFrame.Angles(0, book[3], book[4])
		block(Vector3.new(0.7, 0.9, 0.22) * S, bookAt, book[2])
		block(Vector3.new(0.62, 0.84, 0.24) * S, bookAt, C.cream, DECOR)
	end
	local sign = block(Vector3.new(1.6, 0.5, 0.06) * S, door * CFrame.new(1.8 * S, 1.2 * S, -0.4 * S) * CFrame.Angles(0, math.pi, 0), C.cream, DECOR)
	label(sign, "Opening soon!", C.ink, C.cream)
	footpath(Config.polar(L.angle, Config.PLAZA_R), door.Position, 2.6)
	keepClear(at.Position, 8)
end

-- A cottage beside a road, with a path to its door.
local function cottage(c)
	local at, roadPoint = Config.cottageAt(c)
	local door = house(at, {
		w = 4.6,
		d = 4.4,
		h = 2.9,
		wall = Color3.fromHex(c.wall),
		roof = Color3.fromHex(c.roof),
		door = Color3.fromHex(c.door),
		label = c.label,
		sign = if c.sign then Color3.fromHex(c.sign) else nil,
	})
	footpath(roadPoint, door.Position, 2.2)
	keepClear(at.Position, 6)
	if c.pond then
		pond(at * CFrame.new(-9.5 * S, 0, -1.5 * S), 4.2)
	end
end

-- A round gazebo with a stepped roof, fairy lights and benches inside.
local function gazebo()
	local G = Config.GAZEBO
	local centre = Config.polar(G.angle, G.dist)
	local roadPoint = Config.polar(72, G.dist * math.cos(math.rad(G.angle - 72)))
	local at = CFrame.lookAt(centre, roadPoint) * CFrame.Angles(0, math.pi, 0) -- the way in faces the road
	local floor = 0.45 * S
	cylinder(4.6 * S, 0.2 * S, at * CFrame.new(0, 0.1 * S, 0), C.stone)
	cylinder(4.2 * S, 0.25 * S, at * CFrame.new(0, 0.325 * S, 0), C.cream)
	local postR = 3.7 * S
	for i = 0, 7 do
		local a = math.rad(22.5 + i * 45)
		cylinder(0.14 * S, 3.0 * S, at * CFrame.Angles(0, a, 0) * CFrame.new(0, floor + 1.5 * S, postR), C.white)
		if i ~= 7 then -- leave the way in open
			local mid = a + math.rad(22.5)
			local length = 2 * postR * math.sin(math.rad(22.5))
			local side = at * CFrame.Angles(0, mid, 0) * CFrame.new(0, 0, postR * math.cos(math.rad(22.5)))
			for _, y in { 0.45, 0.9 } do
				block(Vector3.new(length, 0.1 * S, 0.1 * S), side * CFrame.new(0, floor + y * S, 0), C.white, DECOR)
			end
			-- an invisible fence behind the rails, so you go in by the way in
			block(Vector3.new(length, 1.2 * S, 0.3 * S), side * CFrame.new(0, floor + 0.6 * S, 0), C.white, {
				Transparency = 1,
				Name = "Railing",
			})
		end
	end
	local tiers = { { 4.6, 0.3, 3.6, C.coral }, { 3.6, 0.45, 3.95, C.cream }, { 2.5, 0.45, 4.35, C.coral }, { 1.3, 0.45, 4.75, C.cream } }
	for _, t in tiers do
		cylinder(t[1] * S, t[2] * S, at * CFrame.new(0, t[3] * S, 0), t[4])
	end
	ball(0.7 * S, at * CFrame.new(0, 5.15 * S, 0), C.yellow)
	for i = 0, 15 do
		ball(0.18 * S, at * CFrame.Angles(0, i / 16 * math.pi * 2, 0) * CFrame.new(0, 3.38 * S, 4.5 * S), C.yellowLight, DECOR)
	end
	for _, a in { math.pi / 2, -math.pi / 2 } do
		bench(at * CFrame.Angles(0, a, 0) * CFrame.new(0, floor, 2.3 * S) * CFrame.Angles(0, math.pi, 0))
	end
	for i = 0, 3 do
		flowerBed(at * CFrame.Angles(0, math.rad(45 + i * 90), 0) * CFrame.new(0, 0, 6.3 * S), 1.1)
	end
	footpath(roadPoint, (at * CFrame.new(0, 0, 4.5 * S)).Position, 2.4)
	keepClear(centre, 8)
end

local function lawns()
	-- the big yuzu tree, a picnic and a notice board on the south lawn
	local yuzuTree = Config.polar(158, 33)
	tree(CFrame.new(yuzuTree), 1.8, true)
	keepClear(yuzuTree, 5)
	local picnic = yawAt(Config.polar(196, 26), 0.3)
	for i = 0, 3 do
		for j = 0, 3 do
			local color = if (i + j) % 2 == 1 then C.coral else C.cream
			block(Vector3.new(0.6, 0.04, 0.6) * S, picnic * CFrame.new((-0.9 + i * 0.6) * S, 0.06 * S, (-0.9 + j * 0.6) * S), color, DECOR)
		end
	end
	block(Vector3.new(0.7, 0.45, 0.5) * S, picnic * CFrame.new(0.4 * S, 0.3 * S, 0.2 * S), C.wood)
	ball(0.32 * S, picnic * CFrame.new(-0.5 * S, 0.2 * S, -0.3 * S), C.yuzu, DECOR)
	ball(0.32 * S, picnic * CFrame.new(-0.25 * S, 0.2 * S, -0.5 * S), C.yuzu, DECOR)
	keepClear(picnic.Position, 2.5)

	-- the request board: three requests a day (server/Daily, client/DailyPanel)
	local B = Config.REQUEST_BOARD
	local board = yawAt(Config.polar(B.angle, B.dist), Config.faceIn(B.angle - 3))
	for _, side in { -1, 1 } do
		cylinder(0.1 * S, 2.2 * S, board * CFrame.new(side * 1.1 * S, 1.1 * S, 0), C.woodDark)
	end
	local face = block(Vector3.new(2.6, 1.5, 0.15) * S, board * CFrame.new(0, 1.5 * S, 0), C.wood)
	block(Vector3.new(2.8, 0.2, 0.4) * S, board * CFrame.new(0, 2.35 * S, 0), C.coral)
	local heading = block(Vector3.new(2.4, 0.42, 0.06) * S, board * CFrame.new(0, 2.62 * S, 0) * CFrame.Angles(0, math.pi, 0), C.cream, DECOR)
	label(heading, "Requests", C.ink, C.cream)
	label(heading, "Requests", C.ink, C.cream, Enum.NormalId.Back)
	local read = Instance.new("ProximityPrompt")
	read.Name = "RequestBoard"
	read.ActionText = "Read"
	read.ObjectText = "Request Board"
	read.KeyboardKeyCode = Enum.KeyCode.E
	read.GamepadKeyCode = Enum.KeyCode.ButtonX
	read.HoldDuration = 0
	read.MaxActivationDistance = 12
	read.RequiresLineOfSight = false
	read.Style = Enum.ProximityPromptStyle.Custom -- shown at the bottom of the screen (client/Prompts)
	read.Parent = face
	for i = 0, 3 do
		local paper = { C.cream, C.white, C.yellow, C.skyBlue }
		block(Vector3.new(0.5, 0.6, 0.02) * S, board * CFrame.new((-0.85 + i * 0.57) * S, (1.5 + (i % 2) * 0.1) * S, 0.09 * S) * CFrame.Angles(0, 0, random:NextNumber(-0.1, 0.1)), paper[i + 1], DECOR)
	end
	keepClear(board.Position, 2.5)

	local post = Config.polar(126, 20.5)
	signpost(post)
	keepClear(post, 2)

	-- trees, bushes, flowers and rocks wherever there's room
	local function scatter(count: number, margin: number, place: (Vector3) -> ())
		local placed, tries = 0, 0
		while placed < count and tries < count * 12 do
			tries += 1
			local spot = Config.polar(random:NextNumber(0, 360), random:NextNumber(Config.PLAZA_R + 4, Config.EDGE_R - 3))
			if isClear(spot, margin) then
				place(spot)
				keepClear(spot, margin * 0.6)
				placed += 1
			end
		end
	end
	scatter(60, 2.6, function(spot)
		tree(CFrame.new(spot), random:NextNumber(0.9, 1.4), random:NextNumber() < 0.2)
	end)
	scatter(30, 1.4, function(spot)
		bush(yawAt(spot, random:NextNumber(0, 6)), random:NextNumber(0.8, 1.3))
	end)
	scatter(26, 1.2, flowerPatch)
	scatter(12, 1, function(spot)
		rock(spot, random:NextNumber(0.7, 1.5))
	end)
end

-- Home Pond and Lily Pond: each is a ring of plots round a pond, where players build their
-- houses. Returns each plot's middle, facing its pond, in plot-number order (Home Pond's 1 to
-- 10, then Lily Pond's 11 to 20). See Houses.build for what goes on a plot.
local function homePond(): { CFrame }
	local H = Config.HOME
	local plots = {}
	for _, info in H.ponds do
		local centre = Config.polar(info.angle, info.dist)
		local base = CFrame.lookAt(centre, Vector3.zero) * CFrame.Angles(0, math.pi, 0) -- +Z points back to town
		local function around(degrees: number, dist: number): CFrame
			return base * CFrame.Angles(0, math.rad(degrees), 0) * CFrame.new(0, 0, dist * S)
		end

		-- a pond that isn't at the end of the Home Pond road has a path from it: round the
		-- inside of the town hedge, then straight in through its gate
		local gateColor = if info.color then Color3.fromHex(info.color) else C.skyBlue
		if info.branch then
			local from = H.ponds[1].angle
			local pieces = 12
			for i = 0, pieces - 1 do
				local a = Config.polar(from + (info.angle - from) * i / pieces, info.branch)
				local b = Config.polar(from + (info.angle - from) * (i + 1) / pieces, info.branch)
				footpath(a, b + (b - a).Unit * 0.6 * S, 3)
			end
			footpath(Config.polar(info.angle, info.branch), Config.polar(info.angle, info.dist - H.ringR), 3)
			-- a round patch of path filling the corner where it turns in
			cylinder(1.5 * S, 0.1, CFrame.new(Config.polar(info.angle, info.branch) + Vector3.new(0, 0.02, 0)), C.path)
			-- a sign where the path leaves the road, pointing the way
			local turn = if info.angle < from then -1 else 1
			local post = Config.polar(from + 4 * turn, info.branch - 2.8)
			local h = 2.6 * S
			cylinder(0.12 * S, h, CFrame.new(post + Vector3.new(0, h / 2, 0)), C.woodDark)
			ball(0.3 * S, CFrame.new(post + Vector3.new(0, h + 0.05 * S, 0)), gateColor, DECOR)
			local ahead = Config.polar(from + 12 * turn, info.branch)
			local dir = Vector3.new(ahead.X - post.X, 0, ahead.Z - post.Z).Unit
			local at = post + dir * 1.1 * S + Vector3.new(0, 2.2 * S, 0)
			local board = block(Vector3.new(2.2, 0.5, 0.08) * S, CFrame.fromMatrix(at, dir, Vector3.yAxis), C.cream, DECOR)
			label(board, info.name, gateColor, C.cream, Enum.NormalId.Front)
			label(board, info.name, gateColor, C.cream, Enum.NormalId.Back)
			keepClear(post, 1.5)
		end

		pond(CFrame.new(centre), H.pondR)
		-- a path all the way round the pond
		local segments = 28
		for i = 0, segments - 1 do
			local a = around(i / segments * 360, H.ringR).Position
			local b = around((i + 1) / segments * 360, H.ringR).Position
			footpath(a, b + (b - a).Unit * 0.6 * S, 2.6)
		end

		-- the plots, in a ring with a gap for the way in
		local step = (360 - H.wayIn) / H.plotsPerPond
		for k = 0, H.plotsPerPond - 1 do
			local plot = around(H.wayIn / 2 + step * (k + 0.5), H.plotR) * CFrame.Angles(0, math.pi, 0) -- facing the pond
			block(Vector3.new(9.2, 0.1, 11.5) * S, plot * CFrame.new(0, -0.02, 2 * S), C.grassDark)
			footpath((plot * CFrame.new(0, 0, 2.6 * S)).Position, (plot * CFrame.new(0, 0, (H.plotR - H.ringR - 1) * S)).Position, 1.6)
			keepClear(plot.Position, 5)
			keepClear((plot * CFrame.new(0, 0, 5.5 * S)).Position, 3.5)
			table.insert(plots, plot)
		end
		-- trees between the plots; and by the pond, between the plots' paths, lamps and benches
		-- looking at the water (on the pond side, so they don't stand in front of the plots' signs)
		for k = 0, H.plotsPerPond do
			local between = H.wayIn / 2 + step * k
			local treeSpot = around(between, H.plotR + 1).Position
			if isClear(treeSpot, 0.5) then
				tree(CFrame.new(treeSpot), random:NextNumber(1.0, 1.3), random:NextNumber() < 0.3)
			end
			if k % 2 == 0 then
				lamp(around(between, H.pondR + 1.6))
			else
				Build.bench(around(between, H.pondR + 1.6) * CFrame.Angles(0, math.pi, 0))
			end
		end
		-- trees behind the houses
		for _ = 1, 40 do
			local spot = around(random:NextNumber(H.wayIn / 2, 360 - H.wayIn / 2), random:NextNumber(H.plotR + 3.5, H.radius - 1.5)).Position
			if isClear(spot, 1.5) then
				tree(CFrame.new(spot), random:NextNumber(1.0, 1.5), random:NextNumber() < 0.2)
				keepClear(spot, 1)
			end
		end
		-- the way in
		gate(around(0, H.radius - 2), info.name, gateColor, true)
		keepClear(centre, H.ringR + 1.5)
	end
	return plots
end

-- The hedge round the edge of town and each pond's neighbourhood, with woods and hills
-- beyond, and an invisible wall so nobody wanders off. Where two circles meet, they join up.
local function edge()
	local H = Config.HOME
	local circles = {
		{ centre = Vector3.zero, r = Config.EDGE_R },
	}
	for _, info in H.ponds do
		table.insert(circles, { centre = Config.polar(info.angle, info.dist), r = H.radius })
	end
	local function inside(spot: Vector3, margin: number): boolean
		for _, circle in circles do
			if flat(spot - circle.centre).Magnitude < (circle.r - margin) * S then
				return true
			end
		end
		return false
	end
	for _, circle in circles do
		local r = circle.r
		local around = math.floor(2 * math.pi * r / 3)
		for i = 0, around - 1 do
			local angle = i / around * 360
			local spot = circle.centre + Config.polar(angle, r + 0.8 + random:NextNumber(-0.3, 0.3))
			if not inside(spot, 0.5) then
				bush(yawAt(spot, random:NextNumber(0, 6)), random:NextNumber(1.2, 1.7), if i % 2 == 0 then C.leaf else C.leafDark)
			end
		end
		local walls = math.max(24, math.floor(r * 0.9))
		local width = 2 * math.pi * r * S / walls * 1.1
		for i = 0, walls - 1 do
			local angle = (i + 0.5) / walls * 360
			local spot = circle.centre + Config.polar(angle, r + 0.3)
			-- leave out pieces that are wholly inside the other circle (where the two join)
			local along = Config.polar(angle + 90, 1).Unit * width / 2
			if not (inside(spot - along, 0) and inside(spot + along, 0)) then
				block(Vector3.new(width, 60, 2), yawAt(spot + Vector3.new(0, 30, 0), Config.faceIn(angle)), C.leaf, {
					Transparency = 1,
					CanQuery = false,
					Name = "Edge",
				})
			end
		end
	end
	-- woods and hills outside
	local r = Config.EDGE_R
	local placed = 0
	while placed < 110 do
		local spot = Config.polar(random:NextNumber(0, 360), random:NextNumber(r + 3, r + 38))
		if not inside(spot, -3) then
			tree(CFrame.new(spot), random:NextNumber(1.1, 2.0), random:NextNumber() < 0.15)
			placed += 1
		end
	end
	for _ = 1, 18 do
		local spot = Config.polar(random:NextNumber(0, 360), random:NextNumber(r + 45, r + 100))
		local size = random:NextNumber(80, 180)
		if not inside(spot, -(size / S / 2 + 2)) then
			blob(Vector3.new(size, size * 0.45, size), CFrame.new(spot), if random:NextNumber() < 0.5 then C.grassDark else C.leafLight, DECOR)
		end
	end
end

local function sky()
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.22
	atmosphere.Offset = 0.1
	atmosphere.Color = Color3.fromHex("#cbeee3")
	atmosphere.Decay = Color3.fromHex("#9ccfc0")
	atmosphere.Glare = 0
	atmosphere.Haze = 0.8
	atmosphere.Parent = Lighting

	local clouds = Instance.new("Clouds")
	clouds.Cover = 0.55
	clouds.Density = 0.5
	clouds.Color = Color3.new(1, 1, 1)
	clouds.Parent = Workspace.Terrain

	local tint = Instance.new("ColorCorrectionEffect")
	tint.Saturation = 0.08
	tint.Contrast = 0.04
	tint.TintColor = Color3.fromHex("#fff8ee")
	tint.Parent = Lighting
end

---------------------------------------------------------------- building it all

-- In Studio, prints how much is in the Workspace, to see how heavy the town is.
function Town.count()
	if not RunService:IsStudio() then
		return
	end
	local parts, meshParts, models, lights, shadows, solid, small = 0, 0, 0, 0, 0, 0, 0
	for _, thing in Workspace:GetDescendants() do
		if thing:IsA("BasePart") then
			parts += 1
			if thing:IsA("MeshPart") then
				meshParts += 1
			end
			if thing.CastShadow then
				shadows += 1
			end
			if thing.CanCollide then
				solid += 1
			end
			local size = thing.Size
			if math.max(size.X, size.Y, size.Z) < Build.SHADOW_SIZE then
				small += 1
			end
		elseif thing:IsA("Model") then
			models += 1
		elseif thing:IsA("PointLight") then
			lights += 1
		end
	end
	-- Some settings can't be read by scripts in every Roblox version, so read them carefully.
	local function setting(name: string): string
		local ok, value = pcall(function()
			return (Workspace :: any)[name]
		end)
		return if ok then tostring(value) else "(can't be read here)"
	end
	print(`Town count: {parts} parts ({meshParts} MeshParts, {small} smaller than {Build.SHADOW_SIZE} studs),`
		.. ` {models} Models, {lights} PointLights, {shadows} cast shadows, {solid} solid.`
		.. ` StreamingEnabled = {setting("StreamingEnabled")}, StreamingTargetRadius = {setting("StreamingTargetRadius")}`)
end

-- Builds the town. Returns where the shop doors are, so the shopkeepers can stand by them.
function Town.build(): { doors: { [string]: CFrame }, plots: { CFrame } }
	-- The Baseplate template's floor and spawn pad aren't needed: the town has its own.
	for _, name in { "Baseplate", "SpawnLocation" } do
		local old = Workspace:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end

	folder = Instance.new("Folder")
	folder.Name = "Town"
	Build.into(folder)
	plaza()
	fountain()
	roads()
	local doors = shops()
	library()
	for _, c in Config.COTTAGES do
		cottage(c)
	end
	gazebo()
	local plots = homePond()
	streetLamps()
	lawns()
	edge()
	sky()
	folder.Parent = Workspace
	pcall(Town.count) -- only for Studio; it must never stop the game starting
	return { doors = doors, plots = plots }
end

return Town
