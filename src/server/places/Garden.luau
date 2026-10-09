-- Fern's Garden, at the end of the Garden road (Config.GARDEN), from the web game's garden.
--
--   * Garden.build() makes the place itself, once, when the town is built: a clearing with
--     Fern's shed (with a "Garden Book" button at its door, client/GardenBook), six bed edges,
--     a stone well, a scarecrow, trees, lamps and flowers. The soil and
--     whatever's growing are drawn by each player's own screen (client/Garden), from their own
--     save, so everyone has their own six beds and the server makes nothing per player.
--   * Garden.start() checks every plant, water and harvest (the GardenAction remote). Crops
--     grow by the server's clock (os.time), so they carry on while the player's away; each
--     stage needs watering first. The Garden opens once a player has said hello to Clover
--     (the First Story's first goal, shared/Goals). Whatever they plant while "Plant your
--     first seeds" is their goal is their quick first crop: each stage takes
--     Config.GARDEN.FIRST_STAGE, so the whole plant, water, grow, pick loop fits in their
--     first couple of minutes.
--
-- Every harvest is counted in the player's Garden Book (their stickers come from the counts,
-- Config.bookStickers); their screen sees the change and celebrates a new sticker.
--
-- GardenAction(what, bed, crop): what is "plant" (with a crop id), "water" or "harvest"; bed
-- is 1 to 6. Returns (true, coins) for a harvest, (true, seconds it'll grow) for watering,
-- (true, 0) for planting, or (false, "a kind message").

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Build = require(Shared.Build)
local Config = require(Shared.Config)
local GoalList = require(Shared.Goals)
local Analytics = require(script.Parent.Parent.Analytics)
local Goals = require(script.Parent.Parent.Goals)
local PlayerData = require(script.Parent.Parent.PlayerData)
local RemoteGuard = require(script.Parent.Parent.RemoteGuard)

local Remotes = Shared:WaitForChild("Remotes")

local G = Config.GARDEN
local C = Build.C
local S = Config.STUDS
local DECOR = Build.DECOR
local FAST_TEST = G.STUDIO_FAST and RunService:IsStudio() -- every crop quick, for testing

local Garden = {}

---------------------------------------------------------------- the place

-- A spot in the Garden: x across, z towards the way in (web units from the middle).
local function at(x: number, z: number, turn: number?): CFrame
	return Config.gardenFrame() * CFrame.new(x * S, 0, z * S) * CFrame.Angles(0, turn or 0, 0)
end

-- The well, like the web game's: a ring of chunky stones round the water, two posts holding a
-- little gabled roof, and a rope and bucket hanging from a crank. One clear cylinder is what
-- you bump into; the rest you'd walk through, so it costs physics nothing.
local function well(base: CFrame)
	local function u(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x * S, y * S, z * S)
	end
	Build.cylinder(1.2 * S, 0.9 * S, u(0, 0.45, 0), C.stone, { Transparency = 1, CastShadow = false })
	Build.cylinder(0.86 * S, 0.62 * S, u(0, 0.31, 0), C.water, DECOR)
	-- two rows of ten stones, the top row set half a stone round
	for row = 0, 1 do
		for i = 0, 9 do
			local a = (i + row * 0.5) / 10 * math.pi * 2
			local tint = if (i * 7 + row * 3) % 3 == 0 then C.stoneDark else C.stone
			local stone = u(math.sin(a) * 0.97, 0.2 + row * 0.34, math.cos(a) * 0.97) * CFrame.Angles(0, a, 0)
			Build.blob(Vector3.new(0.64, 0.38, 0.36) * S, stone, tint, DECOR)
		end
	end
	-- the posts, the axle with its drum, and the crank's arm and handle on the right
	for _, side in { -1, 1 } do
		Build.block(Vector3.new(0.16, 2.12, 0.16) * S, u(side * 1.0, 1.8, 0), C.woodDark, DECOR)
	end
	local across = CFrame.Angles(0, 0, math.pi / 2) -- a cylinder lying along x
	Build.cylinder(0.06 * S, 2.25 * S, u(0, 2.1, 0) * across, C.wood, DECOR)
	Build.cylinder(0.12 * S, 0.3 * S, u(0, 2.1, 0) * across, C.wood, DECOR)
	Build.block(Vector3.new(0.08, 0.36, 0.08) * S, u(1.16, 1.96, 0), C.woodDark, DECOR)
	Build.cylinder(0.04 * S, 0.22 * S, u(1.24, 1.8, 0) * across, C.woodDark, DECOR)
	-- the rope, the bucket, and its handle: two little bars meeting over the middle
	Build.cylinder(0.025 * S, 0.62 * S, u(0, 1.74, 0), Color3.fromHex("#d9c08f"), DECOR)
	Build.cylinder(0.19 * S, 0.3 * S, u(0, 1.3, 0), Color3.fromHex("#5a8fae"), DECOR)
	for _, side in { -1, 1 } do
		Build.block(Vector3.new(0.03, 0.22, 0.03) * S, u(side * 0.09, 1.52, 0) * CFrame.Angles(0, 0, side * 0.95), C.woodDark, DECOR)
	end
	-- the gabled roof resting on the posts, with a ridge along the top and a trim at each eave
	local run, rise = 1.35, 0.68
	local length, tilt = math.sqrt(run * run + rise * rise) + 0.12, math.atan2(rise, run)
	for _, side in { -1, 1 } do
		Build.block(Vector3.new(length, 0.1, 1.3) * S, u(side * run / 2, 2.72 + rise / 2, 0) * CFrame.Angles(0, 0, -side * tilt), C.coral, DECOR)
		Build.block(Vector3.new(0.06, 0.06, 1.3) * S, u(side * 1.4, 2.66, 0), Color3.fromHex("#c95a43"), DECOR)
	end
	Build.cylinder(0.08 * S, 1.4 * S, u(0, 2.72 + rise + 0.04, 0) * CFrame.Angles(math.pi / 2, 0, 0), Color3.fromHex("#c95a43"), DECOR)
end

-- A friendly capybara scarecrow, facing -Z: a shirt with dungarees over it, straw poking out
-- of its sleeves, rosy cheeks and a proper straw hat. Only its post is solid.
local function scarecrow(base: CFrame)
	local function u(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x * S, y * S, z * S)
	end
	local STRAW = Color3.fromHex("#f2d48a")
	local STRAW_DARK = Color3.fromHex("#e0b85c")
	local SHIRT = Color3.fromHex("#f08f6e")
	local DUNGAREES = Color3.fromHex("#6f9fc8")
	local FUR = Color3.fromHex("#c98b52")
	-- the post and the pole its arms hang on
	Build.cylinder(0.09 * S, 2.4 * S, u(0, 1.2, 0), C.woodDark)
	Build.cylinder(0.05 * S, 2.0 * S, u(0, 1.6, 0) * CFrame.Angles(0, 0, math.pi / 2), C.woodDark, DECOR)
	-- the shirt and its sleeves, then the dungarees: trousers, a bib with two buttons, and straps
	Build.blob(Vector3.new(0.85, 0.85, 0.6) * S, u(0, 1.6, 0), SHIRT, DECOR)
	for _, side in { -1, 1 } do
		Build.blob(Vector3.new(0.55, 0.3, 0.3) * S, u(side * 0.55, 1.6, 0), SHIRT, DECOR)
	end
	Build.blob(Vector3.new(0.92, 0.55, 0.64) * S, u(0, 1.38, 0), DUNGAREES, DECOR)
	Build.block(Vector3.new(0.4, 0.3, 0.05) * S, u(0, 1.7, -0.29), DUNGAREES, DECOR)
	for _, side in { -1, 1 } do
		Build.block(Vector3.new(0.07, 0.24, 0.04) * S, u(side * 0.15, 1.92, -0.22) * CFrame.Angles(0.75, 0, 0), DUNGAREES, DECOR)
		Build.ball(0.07 * S, u(side * 0.13, 1.8, -0.32), C.yellow, DECOR)
	end
	-- straw tufts poking out at each hand, fanned out
	for _, side in { -1, 1 } do
		for k = -1, 1 do
			Build.blob(Vector3.new(0.34, 0.07, 0.07) * S, u(side * 0.95, 1.6 + k * 0.05, k * 0.04) * CFrame.Angles(0, 0, side * k * 0.45), if k == 0 then STRAW else STRAW_DARK, DECOR)
		end
	end
	-- the head: fur, a snout with a little nose, eyes, ears and rosy cheeks
	Build.blob(Vector3.new(0.7, 0.55, 0.85) * S, u(0, 2.3, -0.1), FUR, DECOR)
	Build.blob(Vector3.new(0.55, 0.42, 0.4) * S, u(0, 2.24, -0.42), Color3.fromHex("#e8c49a"), DECOR)
	Build.blob(Vector3.new(0.16, 0.07, 0.05) * S, u(0, 2.34, -0.6), Color3.fromHex("#6b4a36"), DECOR)
	for _, side in { -1, 1 } do
		Build.ball(0.11 * S, u(side * 0.3, 2.42, -0.27), C.ink, DECOR)
		Build.blob(Vector3.new(0.14, 0.12, 0.08) * S, u(side * 0.26, 2.48, 0.05), FUR:Lerp(C.ink, 0.15), DECOR)
		Build.blob(Vector3.new(0.06, 0.1, 0.13) * S, u(side * 0.29, 2.28, -0.34), Color3.fromHex("#f4a6a0"), DECOR)
	end
	-- the straw hat, tipped a little: a wide brim, a round crown and a coral band
	local hat = u(0, 2.6, -0.05) * CFrame.Angles(-0.1, 0, 0.1)
	Build.cylinder(0.72 * S, 0.05 * S, hat, STRAW, DECOR)
	Build.cylinder(0.3 * S, 0.3 * S, hat * CFrame.new(0, 0.17 * S, 0), STRAW, DECOR)
	Build.cylinder(0.31 * S, 0.08 * S, hat * CFrame.new(0, 0.07 * S, 0), C.coral, DECOR)
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
	-- the Garden Book's button, at the shed door (the shed's front faces the way in, +Z)
	local door = Build.block(Vector3.new(3, 3, 1), at(-11, -15.5 + 2.9) * CFrame.new(0, 1.6, 0), C.wood,
		{ Name = "GardenBookSpot", Transparency = 1, CanCollide = false, CanQuery = false })
	local book = Instance.new("ProximityPrompt")
	book.Name = "GardenBook"
	book.ActionText = "Garden Book"
	book.ObjectText = "Fern's shed"
	book.HoldDuration = 0
	book.MaxActivationDistance = 12
	book.RequiresLineOfSight = false
	book.Style = Enum.ProximityPromptStyle.Custom -- shown at the bottom of the screen (client/Prompts)
	book.Parent = door
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
	if not GoalList.gardenOpen(data.goalsDone) then
		return false, "Say hello to Clover first!"
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
			-- their very first crop, planted while that's their goal, grows fast
			local quick = not table.find(d.goalsDone, "plant")
			d.garden[bed] = { crop = crop, stage = 0, readyAt = nil, quick = if quick then true else nil }
		end)
		Goals.event(player, "plant", crop)
		return true, 0
	elseif what == "water" then
		if not thirsty then
			return false, "It doesn't need water just now."
		end
		local grow = if plot.quick or FAST_TEST then G.FIRST_STAGE else G.CROPS[plot.crop].stage
		PlayerData.update(player, function(d)
			-- (the stage it's reached, now watered and growing on)
			d.garden[bed] = { crop = plot.crop, stage = stage, readyAt = now + grow, quick = plot.quick }
		end)
		Goals.event(player, "water", plot.crop)
		return true, grow
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
			-- counted in the Garden Book
			d.gardenBook.picked[plot.crop] = (d.gardenBook.picked[plot.crop] or 0) + 1
			d.gardenBook.first = true
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
