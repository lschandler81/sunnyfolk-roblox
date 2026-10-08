-- Fern's Garden, at the end of the Garden road (Config.GARDEN), from the web game's garden.
--
--   * Garden.build() makes the place itself, once, when the town is built: a clearing with
--     Fern's shed, six bed edges, a well, a scarecrow, trees, lamps and flowers. The soil and
--     whatever's growing are drawn by each player's own screen (client/Garden), from their own
--     save, so everyone has their own six beds and the server makes nothing per player.
--   * Garden.start() checks every plant, water and harvest (the GardenAction remote). Crops
--     grow by the server's clock (os.time), so they carry on while the player's away; each
--     stage needs watering first. Only players with Config.GARDEN.SUN sunshine may garden.
--
-- GardenAction(what, bed, crop): what is "plant" (with a crop id), "water" or "harvest"; bed
-- is 1 to 6. Returns (true, coins) or (false, "a kind message").

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Build = require(Shared.Build)
local Config = require(Shared.Config)
local Analytics = require(script.Parent.Parent.Analytics)
local Goals = require(script.Parent.Parent.Goals)
local PlayerData = require(script.Parent.Parent.PlayerData)
local RemoteGuard = require(script.Parent.Parent.RemoteGuard)

local Remotes = Shared:WaitForChild("Remotes")

local G = Config.GARDEN
local C = Build.C
local S = Config.STUDS
local DECOR = Build.DECOR

local Garden = {}

---------------------------------------------------------------- the place

-- A spot in the Garden: x across, z towards the way in (web units from the middle).
local function at(x: number, z: number, turn: number?): CFrame
	return Config.gardenFrame() * CFrame.new(x * S, 0, z * S) * CFrame.Angles(0, turn or 0, 0)
end

local function well(base: CFrame)
	Build.cylinder(1.0 * S, 0.7 * S, base * CFrame.new(0, 0.35 * S, 0), C.stone)
	Build.cylinder(0.8 * S, 0.1 * S, base * CFrame.new(0, 0.66 * S, 0), C.water, DECOR)
	Build.cylinder(1.1 * S, 0.16 * S, base * CFrame.new(0, 0.78 * S, 0), C.stoneDark)
	for _, side in { -1, 1 } do
		Build.block(Vector3.new(0.16, 1.95, 0.16) * S, base * CFrame.new(side * 1.0 * S, 1.72 * S, 0), C.woodDark)
		-- the roof: two slabs meeting at the top
		Build.block(Vector3.new(1.55, 0.1, 1.3) * S, base * CFrame.new(side * 0.68 * S, 3.05 * S, 0) * CFrame.Angles(0, 0, -side * 0.47), C.coral)
	end
	Build.cylinder(0.06 * S, 2.15 * S, base * CFrame.new(0, 2.1 * S, 0) * CFrame.Angles(0, 0, math.pi / 2), C.wood, DECOR)
	Build.cylinder(0.2 * S, 0.3 * S, base * CFrame.new(0, 1.35 * S, 0), C.skyBlue, DECOR) -- the bucket
end

local function scarecrow(base: CFrame)
	Build.cylinder(0.09 * S, 2.4 * S, base * CFrame.new(0, 1.2 * S, 0), C.woodDark)
	Build.cylinder(0.05 * S, 2.0 * S, base * CFrame.new(0, 1.6 * S, 0) * CFrame.Angles(0, 0, math.pi / 2), C.woodDark, DECOR)
	Build.blob(Vector3.new(0.9, 0.9, 0.6) * S, base * CFrame.new(0, 1.55 * S, 0), Color3.fromHex("#6f9fc8"), DECOR)
	Build.blob(Vector3.new(0.7, 0.55, 0.85) * S, base * CFrame.new(0, 2.3 * S, -0.1 * S), Color3.fromHex("#c98b52"), DECOR)
	Build.blob(Vector3.new(0.55, 0.42, 0.4) * S, base * CFrame.new(0, 2.24 * S, -0.42 * S), Color3.fromHex("#e8c49a"), DECOR)
	Build.cylinder(0.75 * S, 0.05 * S, base * CFrame.new(0, 2.62 * S, 0), Color3.fromHex("#f2d48a"), DECOR)
	Build.blob(Vector3.new(0.5, 0.3, 0.5) * S, base * CFrame.new(0, 2.75 * S, 0), Color3.fromHex("#f2d48a"), DECOR)
	for _, side in { -1, 1 } do
		Build.ball(0.1 * S, base * CFrame.new(side * 0.3 * S, 2.42 * S, -0.27 * S), C.ink, DECOR)
	end
end

-- Builds the Garden. Call it while the town is being built (it goes in the town's folder).
function Garden.build()
	-- a lighter clearing, and paths: in from the road, and between the rows of beds
	Build.cylinder((G.radius - 1) * S, 0.06, at(0, 0) * CFrame.new(0, 0.03, 0), Color3.fromHex("#b4dc94"), DECOR)
	local path = C.path
	Build.block(Vector3.new(2.6 * S, 0.1, (G.radius - 6) * S), at(0, 6 + (G.radius - 6) / 2) * CFrame.new(0, 0.07, 0), path, DECOR)
	for _, z in { -0.3, 7.6 } do
		Build.block(Vector3.new(24 * S, 0.1, 2.2 * S), at(0, z) * CFrame.new(0, 0.07, 0), path, DECOR)
	end

	-- the beds' wooden edges (the soil in them is drawn by each player's screen)
	local w, d = G.BED_W, G.BED_D
	for i = 1, #G.BEDS do
		local bed = Config.gardenBed(i)
		for _, side in { -1, 1 } do
			Build.block(Vector3.new(w + 0.3, 0.32, 0.18) * S, bed * CFrame.new(0, 0.16 * S, side * (d / 2 + 0.06) * S), C.wood)
			Build.block(Vector3.new(0.18, 0.32, d + 0.3) * S, bed * CFrame.new(side * (w / 2 + 0.06) * S, 0.16 * S, 0), C.wood)
		end
	end

	-- Fern's shed, its door facing the way in
	Build.house(at(-11, -15.5), {
		w = 5.2,
		d = 4,
		h = 2.8,
		wall = Color3.fromHex("#f6e2c4"),
		roof = C.leaf,
		door = C.teal,
		label = "Fern's Garden",
		sign = C.leaf,
		chimney = false,
		yard = false,
	})
	well(at(11, -14))
	scarecrow(at(12.5, 9, -0.5))

	for _, spot in { { -16.5, 4.5, 1.2 }, { 16.5, -3.5, 1.1 }, { -14.5, 13.5, 1.0 }, { 7, 16.5, 0.9 }, { -16, -6, 1.0 } } do
		Build.tree(at(spot[1], spot[2]), spot[3], true)
	end
	for _, spot in { { -3.5, 16 }, { 3.5, -13.5 } } do
		Build.lamp(at(spot[1], spot[2]))
	end
	-- flowers round the edge, leaving the way in clear (and not inside the shed)
	for i = 0, 69 do
		local a = i / 70 * math.pi * 2
		local r = G.radius - 2.6 + math.sin(i * 7) * 0.6
		local x, z = math.sin(a) * r, math.cos(a) * r
		local wayIn = z > G.radius - 8 and math.abs(x) < 4.5
		local shed = x < -8 and z < -12.5
		if not (wayIn or shed) then
			Build.flower(at(x, z), Build.FLOWERS[i % 4 + 1], (0.3 + (i % 3) * 0.08) * S)
		end
	end
end

---------------------------------------------------------------- gardening

-- Is the player near enough to bed `i`?
local function near(player: Player, i: number): boolean
	local root = player.Character and player.Character.PrimaryPart
	if not root then
		return false
	end
	local gap = root.Position - Config.gardenBed(i).Position
	return Vector3.new(gap.X, 0, gap.Z).Magnitude <= G.REACH
end

local function action(player: Player, what: any, bed: any, crop: any): (boolean, any)
	local data = PlayerData.get(player)
	if not data then
		return false, "Just a moment!"
	end
	if data.sun < G.SUN then
		return false, `The Garden opens with {G.SUN} sunshine.`
	end
	if typeof(bed) ~= "number" or bed ~= bed or bed % 1 ~= 0 or bed < 1 or bed > #G.BEDS then
		return false, "Something went wrong. Please try again."
	end
	if not near(player, bed) then
		return false, "Walk a little closer to the bed."
	end
	local now = os.time()
	local plot = data.garden[bed]
	local stage, thirsty = Config.gardenState(plot, now)

	if what == "plant" then
		local info = typeof(crop) == "string" and G.CROPS[crop]
		if not info then
			return false, "Fern doesn't have those seeds."
		end
		if plot.crop then
			return false, "Something's already growing there."
		end
		PlayerData.update(player, function(d)
			d.garden[bed] = { crop = crop, stage = 0, readyAt = nil }
		end)
		return true, 0
	elseif what == "water" then
		if not thirsty then
			return false, "It doesn't need water just now."
		end
		local info = G.CROPS[plot.crop]
		PlayerData.update(player, function(d)
			-- (the stage it's reached, now watered and growing on)
			d.garden[bed] = { crop = plot.crop, stage = stage, readyAt = now + info.stage }
		end)
		return true, 0
	elseif what == "harvest" then
		if not plot.crop or stage < G.STAGES then
			return false, "It isn't ready yet."
		end
		local info = G.CROPS[plot.crop]
		local balance = nil
		PlayerData.update(player, function(d)
			d.garden[bed] = { crop = nil, stage = 0, readyAt = nil }
			d.coins += info.coins
			balance = d.coins
		end)
		if not balance then
			return false, "Something went wrong. Please try again."
		end
		Analytics.coinsEarned(player, info.coins, balance, `garden:{plot.crop}`)
		Goals.event(player, "harvest", plot.crop)
		return true, info.coins
	end
	return false, "Something went wrong. Please try again."
end

function Garden.start()
	Remotes.GardenAction.OnServerInvoke = function(player, what, bed, crop)
		if not RemoteGuard.allow(player, "Garden") then
			return false, "Just a moment!"
		end
		return action(player, what, bed, crop)
	end
end

return Garden
