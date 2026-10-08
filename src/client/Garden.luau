-- The Garden on this player's own screen (Config.GARDEN; the server checks everything in
-- server/places/Garden):
--   * your six beds: the soil (darker once watered) and whatever's growing, drawn from your
--     own save (the Garden attribute), so other players see their own beds, not yours
--   * a button at each bed saying what to do next, in a word or two ("Plant seeds", "Water",
--     "Harvest", with the crop's name beside it on a computer), and a little sign high over
--     the bed when it needs water or is ready (hidden while you're at that bed, since its
--     button says the same). While a crop grows there's nothing to do, so there's no button,
--     and the sign counts down instead ("Growing · 4:32").
--   * the seed card, to choose what to plant
--   * a ribbon across the Garden road's arch until you've said hello to Clover, which you
--     can't walk through (the server still refuses to garden for anyone who hasn't)
--   * the "later" line on the goal card ("Your sunflowers are growing"), for GoalsPanel
-- Crops grow by the server's clock: Workspace:GetServerTimeNow() matches its os.time().

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Build = require(Shared.Build)
local Config = require(Shared.Config)
local GoalList = require(Shared.Goals)
local Controls = require(script.Parent.Controls)
local Hud = require(script.Parent.Hud)
local Ui = require(script.Parent.Ui)

local Remotes = Shared:WaitForChild("Remotes")
local player = Players.LocalPlayer

local G = Config.GARDEN
local C = Build.C
local S = Config.STUDS
local LOOK = 0.5 -- seconds between looks at how the beds are doing
local SOIL_DRY = Color3.fromHex("#9c7454")
local SOIL_WET = Color3.fromHex("#6e4e36")
local ORANGE = Color3.fromHex("#f08c3a")
local PROPS = { CanCollide = false, CanTouch = false, CanQuery = false, CastShadow = false }

local Garden = {}

local screen: ScreenGui? = nil

-- "20 seconds", "2 min", "1½ hours"...
local function howLong(seconds: number): string
	if seconds < 60 then
		local whole = math.max(1, math.round(seconds))
		return if whole == 1 then "1 second" else `{whole} seconds`
	elseif seconds < 60 * 60 then
		return `{math.max(1, math.round(seconds / 60))} min`
	end
	local hours = seconds / 3600
	local whole = math.floor(hours)
	local half = hours - whole >= 0.25 and hours - whole < 0.75
	if hours - whole >= 0.75 then
		whole += 1
	end
	local text = if half then `{whole}½` else tostring(whole)
	return text .. (if whole == 1 and not half then " hour" else " hours")
end

local function clock(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	if seconds >= 3600 then
		return `{math.floor(seconds / 3600)}h {math.floor(seconds % 3600 / 60)}m`
	end
	return `{math.floor(seconds / 60)}:{string.format("%02d", seconds % 60)}`
end

local function myGarden(): { any }
	local saved = player:GetAttribute("Garden")
	if typeof(saved) == "string" then
		local ok, beds = pcall(function()
			return HttpService:JSONDecode(saved)
		end)
		if ok and typeof(beds) == "table" then
			return beds
		end
	end
	return {}
end

local function goalsDone(): { string }
	return GoalList.fromAttribute(player:GetAttribute("GoalsDone"))
end

local function isOpen(): boolean
	return GoalList.gardenOpen(goalsDone())
end

-- Whether what you plant now grows fast: your quick first crop (as the server decides it),
-- or any crop while Config.GARDEN.STUDIO_FAST is on in Studio.
local function firstCrop(): boolean
	return not table.find(goalsDone(), "plant") or (G.STUDIO_FAST and RunService:IsStudio())
end

-- A gentle line about your garden for the goal card: a crop that's ready, then one that needs
-- water, then one that's growing ("Your sunflowers are growing"). Nil if nothing's planted.
function Garden.laterLine(): string?
	local now = Workspace:GetServerTimeNow() - G.CLIENT_LAG
	local best, bestNeed = nil, math.huge
	for _, plot in myGarden() do
		local info = plot and plot.crop and G.CROPS[plot.crop]
		if info then
			local stage, thirsty = Config.gardenState(plot, now)
			local need = if stage >= G.STAGES then 1 elseif thirsty then 2 else 3
			if need < bestNeed then
				best, bestNeed = info, need
			end
		end
	end
	if not best then
		return nil
	end
	local one = best.count == 1 -- "Your giant pumpkin is growing"
	local name = string.lower(best.name)
	if bestNeed == 1 then
		return `Your {name} {if one then "is" else "are"} ready to pick!`
	elseif bestNeed == 2 then
		return `Your {name} {if one then "needs" else "need"} water`
	end
	return `Your {name} {if one then "is" else "are"} growing`
end

-- Where the Garden goal points: the bed that needs you (ready to harvest first, then needing
-- water, then empty for planting), the nearest of those; or, if every bed is growing, the one
-- that's ready soonest. The middle of the bed, on the ground.
function Garden.bedThatNeedsYou(from: Vector3): Vector3
	local now = Workspace:GetServerTimeNow() - G.CLIENT_LAG
	local garden = myGarden()
	local best, bestScore = 1, math.huge
	for i = 1, #G.BEDS do
		local plot = garden[i]
		local stage, thirsty, readyAt = Config.gardenState(plot, now)
		local spot = Config.gardenBed(i).Position
		local need = if not (plot and plot.crop) then 2
			elseif stage >= G.STAGES then 0
			elseif thirsty then 1
			else 3
		-- what it needs comes first; then the nearest (or, if growing, the soonest ready)
		local score = need * 1e6 + (if need == 3 then (readyAt or now) - now else (spot - from).Magnitude)
		if score < bestScore then
			best, bestScore = i, score
		end
	end
	return Config.gardenBed(best).Position
end

---------------------------------------------------------------- drawing a bed

-- Where each plant goes in a bed (studs from its middle), like the web game's plantSpots.
local function spots(count: number): { Vector2 }
	local cols = if count >= 6 then 3 elseif count >= 3 then count else 1
	local rows = math.ceil(count / cols)
	local out = {}
	for i = 0, count - 1 do
		local c, r = i % cols, i // cols
		table.insert(out, Vector2.new(
			(c - (cols - 1) / 2) * (G.BED_W / (cols + 0.3)) * S,
			(r - (rows - 1) / 2) * (G.BED_D / (rows + 0.6)) * S
		))
	end
	return out
end

-- One plant at `at` (on the soil), at its stage.
local function plant(crop: string, stage: number, at: CFrame, n: number)
	local function u(x: number, y: number, z: number): CFrame
		return at * CFrame.new(x * S, y * S, z * S)
	end
	if stage == 0 then
		Build.blob(Vector3.new(0.3, 0.14, 0.3) * S, u(0, 0.05, 0), Color3.fromHex("#7a5a3e"), PROPS)
		return
	end
	if stage == 1 then
		for _, side in { -1, 1 } do
			Build.blob(Vector3.new(0.2, 0.05, 0.1) * S, u(side * 0.08, 0.17, 0) * CFrame.Angles(0, 0, side * 0.5), C.leaf, PROPS)
		end
		Build.cylinder(0.02 * S, 0.18 * S, u(0, 0.09, 0), C.leafDark, PROPS)
		return
	end
	local ripe = stage >= G.STAGES
	if crop == "sunflower" then
		local h = if ripe then 1.9 else 1.0
		Build.cylinder(0.05 * S, h * S, u(0, h / 2, 0), C.leafDark, PROPS)
		for _, side in { -1, 1 } do
			Build.blob(Vector3.new(0.4, 0.06, 0.22) * S, u(side * 0.2, h * 0.45, 0) * CFrame.Angles(0, 0, side * 0.4), C.leaf, PROPS)
		end
		if ripe then
			-- its face turned up a little: a ring of twelve yellow petals (over a darker ring, so no
			-- gaps show between them) round a domed brown middle
			local face = u(0, h, 0.04) * CFrame.Angles(-0.35, 0, 0) -- (its front looks along +Z)
			Build.disc(0.27 * S, 0.04 * S, face * CFrame.new(0, 0, -0.03 * S), Color3.fromHex("#e0a52a"), PROPS)
			for i = 0, 11 do
				local petal = face * CFrame.Angles(0, 0, i / 12 * math.pi * 2) * CFrame.new(0, 0.3 * S, 0)
				Build.blob(Vector3.new(0.14, 0.3, 0.05) * S, petal, if i % 2 == 0 then C.yellow else C.yellowLight, PROPS)
			end
			Build.blob(Vector3.new(0.34, 0.34, 0.14) * S, face * CFrame.new(0, 0, 0.03 * S), Color3.fromHex("#7a4a26"), PROPS)
			Build.blob(Vector3.new(0.2, 0.2, 0.1) * S, face * CFrame.new(0, 0, 0.08 * S), Color3.fromHex("#5a3418"), PROPS)
		else
			Build.ball(0.2 * S, u(0, h + 0.05, 0), C.leaf, PROPS)
		end
	elseif crop == "carrot" then
		-- feathery fronds on thin stalks, leaning out; when ripe, the carrot's orange top shows
		-- above the soil
		local random = Random.new(n)
		local spin = random:NextNumber(0, math.pi * 2)
		local tall = if ripe then 0.38 else 0.26
		local base = if ripe then 0.12 else 0.04
		if ripe then
			Build.blob(Vector3.new(0.26, 0.22, 0.26) * S, u(0, 0.04, 0), ORANGE, PROPS)
			Build.blob(Vector3.new(0.2, 0.06, 0.2) * S, u(0, 0.14, 0), ORANGE:Lerp(C.leafDark, 0.35), PROPS)
		end
		for i = 0, 4 do
			local a = spin + i / 5 * math.pi * 2
			local lean = u(0, base, 0) * CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, -0.38)
			Build.cylinder(0.014 * S, tall * S, lean * CFrame.new(0, tall / 2 * S, 0), C.leafDark, PROPS)
			Build.blob(Vector3.new(0.15, 0.26, 0.05) * S, lean * CFrame.new(0, (tall + 0.1) * S, 0),
				if i % 2 == 0 then C.leaf else C.leafLight, PROPS)
		end
	elseif crop == "strawberry" then
		-- a rosette of leaves round a darker middle; while growing, white flowers and a little
		-- green berry; when ripe, plump red berries with green tops resting on the leaves
		local random = Random.new(n)
		local spin = random:NextNumber(0, math.pi * 2)
		Build.blob(Vector3.new(0.24, 0.2, 0.24) * S, u(0, 0.1, 0), C.leafDark, PROPS)
		for i = 0, 5 do
			local a = spin + i / 6 * math.pi * 2
			local leaf = u(0, 0, 0) * CFrame.Angles(0, -a, 0) * CFrame.new(0.2 * S, 0.13 * S, 0) * CFrame.Angles(0, 0, 0.3)
			Build.blob(Vector3.new(0.36, 0.06, 0.26) * S, leaf, if i % 2 == 0 then C.leaf else C.leafLight, PROPS)
		end
		if ripe then
			local RED = Color3.fromHex("#e8484a")
			for i = 0, 2 do
				local a = spin + 0.5 + i / 3 * math.pi * 2
				-- (just past the ends of the leaves, so the whole berry shows)
				local at = u(0, 0, 0) * CFrame.Angles(0, -a, 0) * CFrame.new(0.42 * S, 0, 0)
				-- a strawberry: wide at the top, coming to a round point, with a leafy cap and stalk
				Build.blob(Vector3.new(0.24, 0.24, 0.24) * S, at * CFrame.new(0, 0.17 * S, 0), RED, PROPS)
				Build.blob(Vector3.new(0.14, 0.14, 0.14) * S, at * CFrame.new(0, 0.06 * S, 0), RED, PROPS)
				Build.blob(Vector3.new(0.2, 0.05, 0.2) * S, at * CFrame.new(0, 0.29 * S, 0), C.leafDark, PROPS)
				Build.cylinder(0.015 * S, 0.14 * S, at * CFrame.new(-0.03 * S, 0.36 * S, 0) * CFrame.Angles(0, 0, 0.5), C.leafDark, PROPS)
			end
		else
			for i = 0, 2 do
				local a = spin + 0.5 + i / 3 * math.pi * 2
				local at = u(0, 0, 0) * CFrame.Angles(0, -a, 0) * CFrame.new(0.16 * S, 0, 0)
				Build.cylinder(0.015 * S, 0.3 * S, at * CFrame.new(0, 0.18 * S, 0), C.leafDark, PROPS)
				if i == 0 then
					Build.blob(Vector3.new(0.12, 0.14, 0.12) * S, at * CFrame.new(0, 0.3 * S, 0), C.leafLight, PROPS)
				else
					Build.blob(Vector3.new(0.18, 0.04, 0.18) * S, at * CFrame.new(0, 0.34 * S, 0), C.white, PROPS)
					Build.ball(0.07 * S, at * CFrame.new(0, 0.36 * S, 0), C.yellow, PROPS)
				end
			end
		end
	elseif crop == "pumpkin" then
		-- big leaves and a vine along the soil; while growing, a small green pumpkin and a yellow
		-- flower; when ripe, a giant ribbed orange pumpkin with a curly stalk
		for i = 0, 3 do
			local a = i / 4 * math.pi * 2 + 0.4
			local leaf = u(0, 0, 0) * CFrame.Angles(0, -a, 0) * CFrame.new(0.95 * S, 0.1 * S, 0) * CFrame.Angles(0, 0, 0.15)
			Build.blob(Vector3.new(0.95, 0.07, 0.7) * S, leaf, if i % 2 == 0 then C.leaf else C.leafDark, PROPS)
		end
		local vine = u(0, 0.04, 0) * CFrame.Angles(0, -(0.4 + math.pi / 4), 0)
		Build.cylinder(0.035 * S, 1.2 * S, vine * CFrame.new(0.6 * S, 0, 0) * CFrame.Angles(0, 0, math.pi / 2), C.leafDark, PROPS)
		local size = if ripe then 1.25 else 0.45
		local main = if ripe then Color3.fromHex("#f0922e") else Color3.fromHex("#9cc06a")
		local rib = if ripe then Color3.fromHex("#dd7a1f") else Color3.fromHex("#86ad55")
		local y = 0.4 * size
		-- six bulging ribs round a middle
		Build.blob(Vector3.new(0.85, 0.76, 0.85) * size * S, u(0, y, 0), main, PROPS)
		for i = 0, 5 do
			local a = i / 6 * math.pi * 2
			local lobe = u(0, y, 0) * CFrame.Angles(0, -a, 0) * CFrame.new(0.28 * size * S, 0, 0)
			Build.blob(Vector3.new(0.5, 0.8, 0.5) * size * S, lobe, if i % 2 == 0 then main else rib, PROPS)
		end
		-- the stalk, with a little curl at the top
		local top = u(0, 0.8 * size, 0) * CFrame.Angles(0.15, 0, 0.2)
		Build.cylinder(0.07 * size * S, 0.3 * size * S, top * CFrame.new(0, 0.12 * size * S, 0), C.woodDark, PROPS)
		Build.cylinder(0.04 * size * S, 0.2 * size * S, top * CFrame.new(0.06 * size * S, 0.3 * size * S, 0) * CFrame.Angles(0, 0, -1.1), C.leafDark, PROPS)
		if not ripe then
			local flower = vine * CFrame.new(1.0 * S, 0.12 * S, 0)
			Build.blob(Vector3.new(0.34, 0.16, 0.34) * S, flower, C.yellow, PROPS)
			Build.ball(0.1 * S, flower * CFrame.new(0, 0.08 * S, 0), Color3.fromHex("#f0a23a"), PROPS)
		end
	end
end

-- One ripe plant of `crop` on its own, standing at the origin, for the Garden Book's stickers.
function Garden.ripeModel(crop: string): Model
	local model = Instance.new("Model")
	Build.into(model)
	plant(crop, G.STAGES, CFrame.identity, 1)
	return model
end

-- Draws bed `i` afresh: its soil and what's growing in it.
local function drawBed(model: Model, i: number, crop: string?, stage: number, watered: boolean)
	model:ClearAllChildren()
	Build.into(model)
	local bed = Config.gardenBed(i)
	local soil = if watered then SOIL_WET else SOIL_DRY
	Build.block(Vector3.new(G.BED_W * S, 0.2 * S, G.BED_D * S), bed * CFrame.new(0, 0.1 * S, 0), soil, PROPS)
	for k = -1, 1 do
		Build.block(Vector3.new((G.BED_W - 0.4) * S, 0.06 * S, 0.12 * S), bed * CFrame.new(0, 0.21 * S, k * 0.9 * S), soil:Lerp(Color3.new(0, 0, 0), 0.12), PROPS)
	end
	if crop then
		for n, spot in spots(G.CROPS[crop].count) do
			plant(crop, stage, bed * CFrame.new(spot.X, 0.2 * S, spot.Y), i * 10 + n)
		end
	end
end

---------------------------------------------------------------- the seed card

local function chooseSeeds(bed: number)
	if screen or Ui.openScreens > 0 then
		return
	end
	Controls.set(false, "garden")
	local gui = Ui.screen("Seeds", 17)
	screen = gui
	local card = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(560, 250),
		BackgroundColor3 = Ui.colors.paper,
		Parent = gui,
	}, { Ui.corner(22), Ui.stroke(3) })
	Ui.fitToScreen(card, 560, 250)
	local function close()
		if gui.Parent then
			gui:Destroy()
			screen = nil
			Controls.set(true, "garden")
		end
	end
	Ui.text({
		Text = "Plant some seeds",
		TextSize = 22,
		TextColor3 = Ui.colors.coral,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.fromOffset(300, Ui.TOUCH),
		Parent = card,
	})
	Ui.button("Not now", Ui.colors.cream, close, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(100, Ui.TOUCH),
		TextSize = 18,
		Parent = card,
	})
	Ui.text({
		Text = "Water them at each stage. They grow even while you're away!",
		TextSize = 14,
		TextColor3 = Ui.colors.teal,
		Position = UDim2.fromOffset(16, 52),
		Size = UDim2.new(1, -32, 0, 20),
		Parent = card,
	})
	local row = Ui.new("Frame", {
		Position = UDim2.fromOffset(12, 78),
		Size = UDim2.new(1, -24, 0, 160),
		BackgroundTransparency = 1,
		Parent = card,
	}, {
		Ui.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local first: GuiObject? = nil
	local quick = firstCrop()
	for i, id in G.ORDER do
		local info = G.CROPS[id]
		local tile = Ui.button("", Ui.colors.cream, function()
			close()
			local ok, why = Remotes.GardenAction:InvokeServer("plant", bed, id)
			if ok then
				Hud.announce("Planted!", "Now give them some water.")
			else
				Hud.announce("Oh!", why or "Something went wrong.")
			end
		end, {
			Size = UDim2.fromOffset(128, 160),
			LayoutOrder = i,
			Parent = row,
		})
		first = first or tile
		Ui.text({ Text = info.name, TextSize = 17, Position = UDim2.fromOffset(6, 18), Size = UDim2.new(1, -12, 0, 44), Parent = tile })
		Ui.text({
			Text = `Ready in {howLong((if quick then G.FIRST_STAGE else info.stage) * G.STAGES)}`,
			TextSize = 14,
			TextColor3 = Ui.colors.teal,
			Position = UDim2.fromOffset(6, 70),
			Size = UDim2.new(1, -12, 0, 36),
			Parent = tile,
		})
		local pay = Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 116),
			Size = UDim2.fromOffset(0, 28),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Parent = tile,
		}, {
			Ui.new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		Ui.coin(22, { LayoutOrder = 1, Parent = pay })
		Ui.text({ Text = `+{info.coins}`, TextSize = 18, TextWrapped = false, Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2, Parent = pay })
	end
	Ui.controller(gui, card, first :: GuiObject, close)
end

---------------------------------------------------------------- starting

function Garden.start()
	local folder = Instance.new("Folder")
	folder.Name = "MyGarden"
	folder.Parent = Workspace

	-- the ribbon across the Garden road's arch, until you've enough sunshine. It spans the
	-- whole gap where the town's hedge and the Garden's meet.
	local gate = CFrame.lookAt(Config.polar(G.angle, Config.EDGE_R - 0.5), Vector3.zero)
	local barrier = Ui.new("Part", {
		Name = "GardenRibbon",
		Anchored = true,
		CanCollide = true,
		CanQuery = false,
		CanTouch = false,
		Transparency = 1,
		Size = Vector3.new(G.GATE_WIDTH * S, 40, 1),
		CFrame = gate + Vector3.new(0, 20, 0),
	})
	local ribbon = Ui.new("Part", {
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromHex("#6fa057"),
		Size = Vector3.new(4.4 * S, 0.12 * S, 0.06 * S),
		CFrame = gate + Vector3.new(0, 1.2 * S, 0),
		Parent = barrier,
	})
	local sign = Ui.new("BillboardGui", {
		Size = UDim2.fromOffset(230, 64),
		StudsOffsetWorldSpace = Vector3.new(0, 2.2 * S, 0),
		MaxDistance = 60,
		LightInfluence = 0,
		Adornee = ribbon,
		Parent = barrier,
	})
	local signText = Ui.text({
		TextSize = 17,
		BackgroundTransparency = 0,
		BackgroundColor3 = Ui.colors.paper,
		Size = UDim2.fromScale(1, 1),
		Parent = sign,
	})
	Ui.corner(14).Parent = signText
	Ui.stroke(2.5).Parent = signText
	local function gateUpdate()
		barrier.Parent = if isOpen() then nil else Workspace
	end
	signText.Text = "Fern's Garden opens once you've said hello to Clover."
	player:GetAttributeChangedSignal("GoalsDone"):Connect(gateUpdate)
	gateUpdate()

	-- each bed: a model for what's drawn, a button, and a little sign
	type Bed = { model: Model, prompt: ProximityPrompt, badge: TextLabel, shownAs: string }
	local beds: { Bed } = {}
	for i = 1, #G.BEDS do
		local model = Instance.new("Model")
		model.Name = `Bed{i}`
		model.Parent = folder
		local spot = Ui.new("Part", {
			Name = `BedButton{i}`,
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			Transparency = 1,
			Size = Vector3.new(2, 2, 2),
			CFrame = Config.gardenBed(i) + Vector3.new(0, 2, 0),
			Parent = folder,
		})
		local prompt = Ui.new("ProximityPrompt", {
			Name = "GardenBed",
			KeyboardKeyCode = Enum.KeyCode.E,
			GamepadKeyCode = Enum.KeyCode.ButtonX,
			HoldDuration = 0,
			MaxActivationDistance = 14,
			RequiresLineOfSight = false,
			Style = Enum.ProximityPromptStyle.Custom, -- shown at the bottom of the screen (client/Prompts)
			Parent = spot,
		})
		prompt:SetAttribute("Bed", i)
		local billboard = Ui.new("BillboardGui", {
			Size = UDim2.fromOffset(G.SIGN_SIZE.X, G.SIGN_SIZE.Y),
			StudsOffsetWorldSpace = Vector3.new(0, G.SIGN_HEIGHT - 2, 0), -- (the spot is 2 up)
			MaxDistance = G.SIGN_DISTANCE,
			AlwaysOnTop = true, -- so your animal never hides it
			LightInfluence = 0,
			Adornee = spot,
			Parent = spot,
		})
		local badge = Ui.text({
			TextSize = 16,
			TextWrapped = false, -- one line, even for "Growing · 8h 59m"
			BackgroundTransparency = 0,
			Size = UDim2.fromScale(1, 1),
			Visible = false,
			Parent = billboard,
		})
		Ui.round().Parent = badge
		Ui.stroke(2.5).Parent = badge
		beds[i] = { model = model, prompt = prompt, badge = badge, shownAs = "" }
		-- while its button is showing, you're at this bed: the sign steps aside
		prompt.PromptShown:Connect(function()
			billboard.Enabled = false
		end)
		prompt.PromptHidden:Connect(function()
			billboard.Enabled = true
		end)
	end

	-- every half a second: how each bed is doing, by the server's clock
	local function look()
		local now = Workspace:GetServerTimeNow() - G.CLIENT_LAG
		local garden = myGarden()
		local open = isOpen()
		for i, bed in beds do
			local plot = garden[i]
			local crop = plot and plot.crop
			local stage, thirsty, readyAt = Config.gardenState(plot, now)
			local watered = crop ~= nil and readyAt ~= nil
			local key = `{crop}/{stage}/{watered}`
			if key ~= bed.shownAs then
				bed.shownAs = key
				drawBed(bed.model, i, crop, stage, watered)
			end
			local name = if crop then G.CROPS[crop].name else ""
			-- a word or two (a phone shows just these); a computer adds the crop's name
			local ready = crop ~= nil and stage >= G.STAGES
			local growing = crop ~= nil and not ready and not thirsty
			local prompt = bed.prompt
			prompt.Enabled = open and not growing
			prompt.ObjectText = name
			if not crop then
				prompt.ActionText = "Plant seeds"
			elseif ready then
				prompt.ActionText = "Harvest"
			else
				prompt.ActionText = "Water"
			end
			local badge = bed.badge
			badge.Visible = open and crop ~= nil
			badge.Text = if ready then "Ready!"
				elseif thirsty then "Needs water"
				else `Growing · {clock((readyAt or now) - now)}`
			badge.BackgroundColor3 = if ready then Ui.colors.yellow
				elseif thirsty then Color3.fromHex("#9cd3f0")
				else Ui.colors.mint
		end
	end
	task.spawn(function()
		while true do
			look()
			task.wait(LOOK)
		end
	end)
	player:GetAttributeChangedSignal("Garden"):Connect(look)

	local busy = false -- waiting for the server, so a quick second tap doesn't ask twice
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name ~= "GardenBed" or busy then
			return
		end
		local i = prompt:GetAttribute("Bed")
		if typeof(i) ~= "number" then
			return
		end
		local plot = myGarden()[i]
		local now = Workspace:GetServerTimeNow() - G.CLIENT_LAG
		local stage, thirsty, readyAt = Config.gardenState(plot, now)
		if not (plot and plot.crop) then
			chooseSeeds(i)
			return
		end
		local info = G.CROPS[plot.crop]
		busy = true
		if stage >= G.STAGES then
			local ok, result = Remotes.GardenAction:InvokeServer("harvest", i)
			if ok then
				Hud.announce(`{info.name}!`, `+{result} coins`)
			else
				Hud.announce("Oh!", result or "Something went wrong.")
			end
		elseif thirsty then
			local ok, result = Remotes.GardenAction:InvokeServer("water", i)
			if ok then
				local grow = if typeof(result) == "number" and result > 0 then result else info.stage
				Hud.announce("Watered!", `It'll grow for {howLong(grow)}.`)
			else
				Hud.announce("Oh!", if typeof(result) == "string" then result else "Something went wrong.")
			end
		else
			-- (only if it was watered just as the button went: growing beds have no button)
			Hud.announce("Growing nicely!", `Come back in {howLong((readyAt or now) - now)}.`)
		end
		busy = false
	end)
end

function Garden.isOpen(): boolean
	return screen ~= nil
end

return Garden
