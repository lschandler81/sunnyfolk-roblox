-- The Garden on this player's own screen (Config.GARDEN; the server checks everything in
-- server/places/Garden):
--   * your six beds: the soil (darker once watered) and whatever's growing, drawn from your
--     own save (the Garden attribute), so other players see their own beds, not yours
--   * a button at each bed saying what to do next, in a word or two ("Plant seeds", "Water",
--     "Growing · 4:32", "Harvest", with the crop's name beside it on a computer), and a little
--     sign high over the bed when it needs water or is ready (hidden while you're at that bed,
--     since its button says the same)
--   * the seed card, to choose what to plant
--   * a ribbon across the Garden road's arch until you've enough sunshine, which you can't
--     walk through (the server still refuses to garden for anyone without it)
-- Crops grow by the server's clock: Workspace:GetServerTimeNow() matches its os.time().

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Build = require(Shared.Build)
local Config = require(Shared.Config)
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

-- "2 min", "1½ hours"...
local function howLong(seconds: number): string
	if seconds < 60 * 60 then
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

local function hasSun(): boolean
	local sun = player:GetAttribute("Sun")
	return typeof(sun) == "number" and sun >= G.SUN
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
			-- its face turned up a little: yellow petals behind a brown middle
			Build.disc(0.42 * S, 0.06 * S, u(0, h, 0.04) * CFrame.Angles(0.35, 0, 0), C.yellow, PROPS)
			Build.disc(0.2 * S, 0.1 * S, u(0, h, 0.02) * CFrame.Angles(0.35, 0, 0), Color3.fromHex("#7a4a26"), PROPS)
		else
			Build.ball(0.2 * S, u(0, h + 0.05, 0), C.leaf, PROPS)
		end
	elseif crop == "carrot" then
		for i = 0, 2 do
			Build.blob(Vector3.new(0.07, 0.4, 0.07) * S, u((i - 1) * 0.07, 0.2 + (if ripe then 0.1 else 0), 0) * CFrame.Angles(0, 0, (i - 1) * 0.35), if i == 1 then C.leafLight else C.leaf, PROPS)
		end
		if ripe then
			Build.blob(Vector3.new(0.22, 0.22, 0.22) * S, u(0, 0.04, 0), ORANGE, PROPS)
		end
	elseif crop == "strawberry" then
		Build.blob(Vector3.new(0.7, 0.35, 0.6) * S, u(0, 0.15, 0), C.leaf, PROPS)
		local random = Random.new(n)
		for _ = 1, 3 do
			local x, z = random:NextNumber(-0.25, 0.25), random:NextNumber(-0.2, 0.2)
			if ripe then
				Build.blob(Vector3.new(0.14, 0.17, 0.14) * S, u(x, 0.22, z), Color3.fromHex("#e8484a"), PROPS)
			else
				Build.ball(0.1 * S, u(x, 0.33, z), C.white, PROPS)
			end
		end
	elseif crop == "pumpkin" then
		for i = 0, 1 do
			local a = i * math.pi + 0.4
			Build.blob(Vector3.new(0.9, 0.07, 0.55) * S, u(math.cos(a) * 0.9, 0.07, math.sin(a) * 0.7) * CFrame.Angles(0, -a, 0), C.leaf, PROPS)
		end
		local size = if ripe then 1.4 else 0.6
		Build.blob(Vector3.new(size, size * 0.8, size) * S, u(0, size * 0.4, 0), if ripe then Color3.fromHex("#f0922e") else Color3.fromHex("#9cc06a"), PROPS)
		Build.cylinder(0.07 * S, 0.3 * S, u(0, size * 0.8 + 0.1, 0) * CFrame.Angles(0.2, 0, 0.2), C.woodDark, PROPS)
	end
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
			Text = `Ready in {howLong(info.stage * G.STAGES)}`,
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
		local sun = player:GetAttribute("Sun")
		local have = if typeof(sun) == "number" then sun else 0
		signText.Text = `The Garden opens with {G.SUN} sunshine. You have {have}!`
		barrier.Parent = if hasSun() then nil else Workspace
	end
	player:GetAttributeChangedSignal("Sun"):Connect(gateUpdate)
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
		local open = hasSun()
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
			local prompt = bed.prompt
			prompt.Enabled = open
			prompt.ObjectText = name
			if not crop then
				prompt.ActionText = "Plant seeds"
			elseif stage >= G.STAGES then
				prompt.ActionText = "Harvest"
			elseif thirsty then
				prompt.ActionText = "Water"
			else
				prompt.ActionText = `Growing · {clock((readyAt or now) - now)}`
			end
			local badge = bed.badge
			badge.Visible = open and crop ~= nil and (thirsty or stage >= G.STAGES)
			badge.Text = if stage >= G.STAGES then "Ready!" else "Needs water"
			badge.BackgroundColor3 = if stage >= G.STAGES then Ui.colors.yellow else Color3.fromHex("#9cd3f0")
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
			local ok, why = Remotes.GardenAction:InvokeServer("water", i)
			if ok then
				Hud.announce("Watered!", `It'll grow for {howLong(info.stage)}.`)
			else
				Hud.announce("Oh!", why or "Something went wrong.")
			end
		else
			Hud.announce("Growing nicely!", `Come back in {howLong(math.max(60, (readyAt or now) - now))}.`)
		end
		busy = false
	end)
end

function Garden.isOpen(): boolean
	return screen ~= nil
end

return Garden
