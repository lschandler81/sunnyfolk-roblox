-- The Fish Book, made like the Garden Book (client/GardenBook): a page for each fish in
-- Config.FISHING.FISH, each a picture so it works for children who don't read yet. A fish
-- you've caught shows in its colours with how many you've caught; one you haven't is a dark
-- shape of itself, with where it lives. The next one to find has a coral edge and a "Next!"
-- tag. A full book gives a badge (server/Badges).
--
-- Opened from the "Fish book" button while fishing (client/Fishing). The server counts your
-- catches (server/Fishing) and saves them in your FishBook attribute; when a new fish arrives,
-- the book opens by itself (in turn, Hud.inTurn) with the new page popping in and a little
-- burst of stars. With a controller, B closes it.
--
-- FishBook.model(id) builds a fish from simple parts (from the web game's makeFish), for the
-- book, the fish that leaps out of the water when you catch one, and the fishing Adventure's card.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Build = require(Shared.Build)
local Config = require(Shared.Config)
local Controls = require(script.Parent.Controls)
local Hud = require(script.Parent.Hud)
local Ui = require(script.Parent.Ui)

local player = Players.LocalPlayer

local F = Config.FISHING
local S = Config.STUDS
local NEW_WAIT = 1.6 -- seconds before a new fish's book opens, so its leap out of the water goes first
local STARS = 8 -- in the burst round a new page
local SHAPE = Color3.fromHex("#33475b") -- a fish not caught yet: a dark shape of it
local NOT_YET = Color3.fromHex("#7d7366") -- its words: soft, but easy to read on cream
local PICTURE_ROOM = 1.1 -- how much room round a fish in its round picture (1 would just touch the edge)
local PROPS = { CanCollide = false, CanTouch = false, CanQuery = false, CastShadow = false }
-- where each kind of fish lives, under one you haven't caught yet
local WHERE = { any = "Any pond", pond = "Home Pond or Puddles' pond", lake = "Lily Pond" }

local FishBook = {}

local screen: ScreenGui? = nil

-- Your book, as saved (see PlayerData), or nil before it's arrived.
local function myBook(): any
	local saved = player:GetAttribute("FishBook")
	if typeof(saved) ~= "string" then
		return nil
	end
	local ok, book = pcall(function()
		return HttpService:JSONDecode(saved)
	end)
	return if ok and typeof(book) == "table" then book else nil
end

-- A fish, nose towards +Z, from simple parts in its colours: a body, a tail, fins on its back
-- and sides, eyes, and stripes or spots for the fish that have them. About one web unit long
-- at size 1, times `scale`.
function FishBook.model(id: string, scale: number?): Model
	local fish = Config.fish(id) or F.FISH[1]
	local s = fish.size * (scale or 1) * S
	local body = Color3.fromHex(fish.body)
	local fin = Color3.fromHex(fish.fin)
	local long = if fish.round then 0.6 else 1.0
	local model = Instance.new("Model")
	Build.into(model)
	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(x * s, y * s, z * s)
	end
	local main = Build.blob(Vector3.new(0.42, 0.4 * (if fish.round then 1.3 else 1), long) * s, at(0, 0, 0), body, PROPS)
	if fish.glow then
		main.Material = Enum.Material.Neon
	end
	-- the tail: a flat diamond, half of it tucked into the body
	Build.block(Vector3.new(0.05, 0.3, 0.3) * s, at(0, 0, -long * 0.55) * CFrame.Angles(math.pi / 4, 0, 0), fin, PROPS)
	Build.blob(Vector3.new(0.05, 0.22, 0.3) * s, at(0, 0.2, -0.05) * CFrame.Angles(-0.3, 0, 0), fin, PROPS)
	for _, x in { -1, 1 } do
		Build.ball(0.1 * s, at(x * 0.16, 0.06, long * 0.33), Build.C.ink, PROPS)
		Build.blob(Vector3.new(0.04, 0.12, 0.16) * s, at(x * 0.2, -0.08, 0.05) * CFrame.Angles(0.3, 0, x * 0.6), fin, PROPS)
	end
	if fish.stripes then
		for _, z in { -0.2, 0, 0.2 } do
			Build.blob(Vector3.new(0.43, 0.32, 0.07) * s, at(0, 0, z), Color3.fromHex(fish.stripes), PROPS)
		end
	end
	if fish.spots then
		for _, spot in { { 0.18, 0.08, 0.1 }, { -0.16, 0.1, -0.12 }, { 0.15, -0.02, -0.25 }, { -0.17, -0.04, 0.2 }, { 0, 0.17, 0 } } do
			Build.ball(0.12 * s, at(spot[1], spot[2], spot[3]), Color3.fromHex(fish.spots), PROPS)
		end
	end
	model.PrimaryPart = main
	return model
end

-- Points a picture's camera at a fish from its side, a little in front and above, far enough
-- back that a ball round the whole fish fits the view (like the Garden Book's stickers).
local function aim(camera: Camera, model: Model)
	local box, size = model:GetBoundingBox()
	local radius = size.Magnitude / 2
	local reach = radius / math.sin(math.rad(camera.FieldOfView / 2)) * PICTURE_ROOM
	camera.CFrame = CFrame.lookAt(box.Position + Vector3.new(1, 0.35, 0.3).Unit * reach, box.Position)
end

-- Little yellow stars flying out from the middle of `tile`, fading as they go.
local function burst(tile: GuiObject)
	for i = 1, STARS do
		local a = i / STARS * math.pi * 2
		local star = Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.35),
			Size = UDim2.fromOffset(14, 14),
			Rotation = 45,
			BackgroundColor3 = Ui.colors.yellow,
			ZIndex = 5,
			Parent = tile,
		}, { Ui.stroke(2, Ui.colors.coral) })
		TweenService:Create(star, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, math.cos(a) * 70, 0.35, math.sin(a) * 70),
			Rotation = 225,
			BackgroundTransparency = 1,
		}):Play()
		task.delay(0.9, function()
			star:Destroy()
		end)
	end
end

function FishBook.isOpen(): boolean
	return screen ~= nil
end

-- Opens the book. `fresh` lists fish just caught for the first time, which pop in with a
-- celebration.
function FishBook.open(fresh: { string }?)
	if screen or Ui.openScreens > 0 then
		return
	end
	local caught = Config.fishCaught(myBook())
	local new = fresh or {}

	Controls.set(false, "fishbook")
	local gui = Ui.screen("FishBook", 15)
	screen = gui
	-- Laid out for a landscape phone (600 x 320): two rows of pages. Grows on bigger screens.
	local card = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(600, 320),
		BackgroundColor3 = Ui.colors.paper,
		Parent = gui,
	}, { Ui.corner(22), Ui.stroke(3) })
	Ui.fitToScreen(card, 600, 320)

	local function close()
		gui:Destroy()
		screen = nil
		Controls.set(true, "fishbook")
	end

	local have, nextOne = 0, nil
	for _, fish in F.FISH do
		if caught[fish.id] then
			have += 1
		elseif not nextOne then
			nextOne = fish.id
		end
	end
	Ui.text({
		Text = if #new > 0 then "New fish!" else "Fish Book",
		TextSize = 22,
		TextColor3 = Ui.colors.coral,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(16, 6),
		Size = UDim2.fromOffset(200, Ui.TOUCH),
		Parent = card,
	})
	Ui.text({
		Text = if nextOne then `{have} of {#F.FISH}` else `All {#F.FISH} found!`,
		TextSize = 18,
		TextColor3 = Ui.colors.teal,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -100, 0, 6),
		Size = UDim2.fromOffset(180, Ui.TOUCH),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = card,
	})
	local closeButton = Ui.button("Close", Ui.colors.cream, close, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 6),
		Size = UDim2.fromOffset(84, Ui.TOUCH),
		TextSize = 20,
		Parent = card,
	})

	-- the pages: five in a row, then the rest
	local grid = Ui.new("Frame", {
		Position = UDim2.fromOffset(10, 56),
		Size = UDim2.fromOffset(580, 256),
		BackgroundTransparency = 1,
		Parent = card,
	}, {
		Ui.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(108, 124),
			CellPadding = UDim2.fromOffset(8, 8),
			FillDirectionMaxCells = 5,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	for i, fish in F.FISH do
		local count = caught[fish.id]
		local isNext = fish.id == nextOne
		local tile = Ui.new("Frame", {
			BackgroundColor3 = if count then Ui.colors.yellowLight else Ui.colors.cream,
			LayoutOrder = i,
			Parent = grid,
		}, {
			Ui.corner(16),
			Ui.stroke(3, if count then Ui.colors.ink elseif isNext then Ui.colors.coral else Ui.colors.grey),
		})
		-- the picture: a round window onto the water
		local disc = Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 6),
			Size = UDim2.fromOffset(70, 70),
			BackgroundColor3 = if count then Color3.fromHex("#bfe6ee") else Ui.colors.paper,
			Parent = tile,
		}, { Ui.round(), Ui.stroke(4, if count then Ui.colors.paper else Ui.colors.grey) })
		local view, camera = Ui.viewport({
			Size = UDim2.fromScale(1, 1),
			ImageColor3 = if count then Color3.new(1, 1, 1) else SHAPE,
			Parent = disc,
		})
		local ok, model = pcall(FishBook.model, fish.id)
		if ok and model then
			model.Parent = view
			aim(camera, model)
		end
		Ui.text({
			Text = if count then fish.name else "Not yet",
			TextSize = 14,
			TextColor3 = if count then Ui.colors.ink else NOT_YET,
			Position = UDim2.fromOffset(4, 80),
			Size = UDim2.new(1, -8, 0, 18),
			Parent = tile,
		})
		Ui.text({
			Text = if count then `Caught {count}` else WHERE[fish.where] or "",
			TextSize = 13,
			TextColor3 = if count then Ui.colors.teal else NOT_YET,
			Position = UDim2.fromOffset(4, 98),
			Size = UDim2.new(1, -8, 0, 24),
			Parent = tile,
		})
		if isNext then
			local tag = Ui.text({
				Text = "Next!",
				TextSize = 13,
				TextColor3 = Ui.colors.paper,
				BackgroundTransparency = 0,
				BackgroundColor3 = Ui.colors.coral,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -4, 0, 4),
				Size = UDim2.fromOffset(42, 20),
				ZIndex = 2,
				Parent = tile,
			})
			Ui.corner(10).Parent = tag
		end
		-- just caught for the first time: pop in, with stars
		if table.find(new, fish.id) then
			local pop = Ui.new("UIScale", { Scale = 0.2, Parent = tile })
			task.delay(0.15, function()
				TweenService:Create(pop, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
				burst(tile)
			end)
		end
	end

	Ui.controller(gui, card, closeButton, close)
end

function FishBook.start()
	-- A new fish: open the book to show it off (in turn, so it never covers another screen).
	-- The fish you have when your book first arrives aren't new.
	local known: { [string]: number }? = nil
	local function look()
		local book = myBook()
		if not book then
			return
		end
		local caught = Config.fishCaught(book)
		local fresh = {}
		if known then
			for _, fish in F.FISH do
				if caught[fish.id] and not known[fish.id] then
					table.insert(fresh, fish.id)
				end
			end
		end
		known = caught
		if #fresh > 0 then
			task.delay(NEW_WAIT, function()
				Hud.inTurn(function()
					FishBook.open(fresh)
				end)
			end)
		end
	end
	player:GetAttributeChangedSignal("FishBook"):Connect(look)
	look()
end

return FishBook
