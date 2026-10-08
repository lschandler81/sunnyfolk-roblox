-- The Garden Book: one page of stickers (Config.GARDEN_BOOK), one for your first pick and one
-- for each crop, each a picture so it works for children who don't read yet. A sticker is
-- greyed out until you've earned it, and each says how many you've picked. Filling the book
-- unlocks the sunflower front garden in the house designer (Houses.GARDENS).
--
-- Opened from the HUD's round book button, and from the "Garden Book" button at Fern's shed.
-- The server counts your picks (server/places/Garden) and saves them in your GardenBook
-- attribute; when a new sticker arrives, the book opens by itself (in turn, Hud.inTurn) with
-- the new sticker popping in and a little burst of stars. With a controller, B closes it.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Build = require(Shared.Build)
local Config = require(Shared.Config)
local Controls = require(script.Parent.Controls)
local Garden = require(script.Parent.Garden)
local Hud = require(script.Parent.Hud)
local Ui = require(script.Parent.Ui)

local player = Players.LocalPlayer

local G = Config.GARDEN
local S = Config.STUDS
local NEW_WAIT = 0.4 -- seconds before a new sticker's book opens, so "Sunflowers! +4 coins" goes first
local STARS = 8 -- in the burst round a new sticker
local GREY = Color3.fromRGB(70, 70, 70) -- a sticker not earned yet: a grey shape of it
local NOT_YET = Color3.fromHex("#7d7366") -- its words: soft, but easy to read on cream
local STICKER_ROOM = 1.12 -- how much room round a sticker's picture (1 would just touch the edge)

local GardenBook = {}

local screen: ScreenGui? = nil

-- Your book, as saved (see PlayerData), or nil before it's arrived.
local function myBook(): any
	local saved = player:GetAttribute("GardenBook")
	if typeof(saved) ~= "string" then
		return nil
	end
	local ok, book = pcall(function()
		return HttpService:JSONDecode(saved)
	end)
	return if ok and typeof(book) == "table" then book else nil
end

-- A basket with something you grew in it, for the first-pick sticker.
local function basket(): Model
	local model = Instance.new("Model")
	Build.into(model)
	local C = Build.C
	local wicker = Color3.fromHex("#c9935a")
	Build.cylinder(0.7 * S, 0.6 * S, CFrame.new(0, 0.3 * S, 0), wicker)
	Build.cylinder(0.76 * S, 0.1 * S, CFrame.new(0, 0.6 * S, 0), C.woodDark)
	-- a carrot, a strawberry and a sunflower head peeping over the rim
	Build.blob(Vector3.new(0.3, 0.3, 0.3) * S, CFrame.new(-0.3 * S, 0.7 * S, 0), Color3.fromHex("#f08c3a"))
	Build.blob(Vector3.new(0.3, 0.3, 0.3) * S, CFrame.new(0.3 * S, 0.7 * S, 0.1 * S), Color3.fromHex("#e8484a"))
	Build.disc(0.28 * S, 0.06 * S, CFrame.new(0, 0.85 * S, -0.2 * S) * CFrame.Angles(-0.35, 0, 0), C.yellow)
	Build.disc(0.13 * S, 0.08 * S, CFrame.new(0, 0.85 * S, -0.18 * S) * CFrame.Angles(-0.35, 0, 0), Color3.fromHex("#7a4a26"))
	-- the handle: two bars meeting over the middle
	for _, side in { -1, 1 } do
		Build.cylinder(0.04 * S, 0.8 * S, CFrame.new(side * 0.36 * S, 0.95 * S, 0) * CFrame.Angles(0, 0, side * 0.6), C.woodDark)
	end
	return model
end

-- A sticker's picture, and its name.
local function sticker(id: string): (Model?, string)
	if id == "first" then
		return basket(), "First pick"
	end
	local info = G.CROPS[id]
	if not info then
		return nil, id
	end
	return Garden.ripeModel(id), info.name
end

-- Points a picture's camera at a model, from the front and a little above, far enough back
-- that a ball round the whole model fits the camera's view: so the picture always stays
-- inside the round sticker, whatever its shape, with a little room to spare.
local function aim(camera: Camera, model: Model)
	local box, size = model:GetBoundingBox()
	local radius = size.Magnitude / 2
	local reach = radius / math.sin(math.rad(camera.FieldOfView / 2)) * STICKER_ROOM
	camera.CFrame = CFrame.lookAt(box.Position + Vector3.new(0.35, 0.45, 1).Unit * reach, box.Position)
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

function GardenBook.isOpen(): boolean
	return screen ~= nil
end

-- Opens the book. `fresh` lists stickers just earned, which pop in with a celebration.
function GardenBook.open(fresh: { string }?)
	if screen or Ui.openScreens > 0 then
		return
	end
	local book = myBook()
	local got = Config.bookStickers(book)
	local picked = if book and typeof(book.picked) == "table" then book.picked else {}
	local new = fresh or {}

	Controls.set(false, "gardenbook")
	local gui = Ui.screen("GardenBook", 15)
	screen = gui
	-- Laid out for a landscape phone (620 x 290), and grows on bigger screens.
	local card = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(620, 290),
		BackgroundColor3 = Ui.colors.paper,
		Parent = gui,
	}, { Ui.corner(22), Ui.stroke(3) })
	Ui.fitToScreen(card, 620, 290)

	local function close()
		gui:Destroy()
		screen = nil
		Controls.set(true, "gardenbook")
	end

	local have = 0
	for _, id in Config.GARDEN_BOOK do
		have += if got[id] then 1 else 0
	end
	Ui.text({
		Text = if #new > 0 then "New sticker!" else "Garden Book",
		TextSize = 22,
		TextColor3 = Ui.colors.coral,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.fromOffset(240, Ui.TOUCH),
		Parent = card,
	})
	Ui.text({
		Text = `{have} of {#Config.GARDEN_BOOK}`,
		TextSize = 18,
		TextColor3 = Ui.colors.teal,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -100, 0, 8),
		Size = UDim2.fromOffset(80, Ui.TOUCH),
		Parent = card,
	})
	local closeButton = Ui.button("Close", Ui.colors.cream, close, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(84, Ui.TOUCH),
		TextSize = 20,
		Parent = card,
	})

	-- the stickers, in a row
	local row = Ui.new("Frame", {
		Position = UDim2.fromOffset(14, 58),
		Size = UDim2.fromOffset(592, 170),
		BackgroundTransparency = 1,
		Parent = card,
	}, {
		Ui.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	for i, id in Config.GARDEN_BOOK do
		local earned = got[id] == true
		local tile = Ui.new("Frame", {
			Size = UDim2.fromOffset(112, 170),
			BackgroundColor3 = if earned then Ui.colors.yellowLight else Ui.colors.cream,
			LayoutOrder = i,
			Parent = row,
		}, { Ui.corner(16), Ui.stroke(3, if earned then Ui.colors.ink else Ui.colors.grey) })
		-- the sticker: a round picture with a thick white edge
		local disc = Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 8),
			Size = UDim2.fromOffset(96, 96),
			BackgroundColor3 = if earned then Ui.colors.mint else Ui.colors.paper,
			Parent = tile,
		}, { Ui.round(), Ui.stroke(4, if earned then Ui.colors.paper else Ui.colors.grey) })
		local view, camera = Ui.viewport({
			Size = UDim2.fromScale(1, 1),
			ImageColor3 = if earned then Color3.new(1, 1, 1) else GREY,
			ImageTransparency = if earned then 0 else 0.45,
			Parent = disc,
		})
		local ok, model, name = pcall(sticker, id)
		if ok and model then
			model.Parent = view
			aim(camera, model)
		end
		Ui.text({
			Text = if ok then name else id,
			TextSize = 15,
			TextColor3 = if earned then Ui.colors.ink else NOT_YET,
			Position = UDim2.fromOffset(4, 108),
			Size = UDim2.new(1, -8, 0, 22),
			Parent = tile,
		})
		local count = if id == "first" then nil else picked[id]
		Ui.text({
			Text = if not earned then "Not yet"
				elseif count then `Picked {count}`
				else "Well done!",
			TextSize = 14,
			TextColor3 = if earned then Ui.colors.teal else NOT_YET,
			Position = UDim2.fromOffset(4, 132),
			Size = UDim2.new(1, -8, 0, 30),
			Parent = tile,
		})
		-- just earned: pop in, with stars
		if table.find(new, id) then
			local pop = Ui.new("UIScale", { Scale = 0.2, Parent = tile })
			task.delay(0.15, function()
				TweenService:Create(pop, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
				burst(tile)
			end)
		end
	end

	-- what a full book gives
	Ui.text({
		Text = if Config.bookFull(book)
			then "Your book is full! Your home designer has a sunflower garden now."
			else "Fill the book to grow a sunflower garden at your home!",
		TextSize = 16,
		TextColor3 = Ui.colors.leaf,
		Position = UDim2.fromOffset(14, 236),
		Size = UDim2.fromOffset(592, 46),
		Parent = card,
	})

	Ui.controller(gui, card, closeButton, close)
end

function GardenBook.start()
	-- the button at Fern's shed
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name == "GardenBook" then
			GardenBook.open()
		end
	end)

	-- A new sticker: open the book to show it off (in turn, so it never covers another
	-- screen). The stickers you have when your book first arrives aren't new.
	local known: { [string]: boolean }? = nil
	local function look()
		local book = myBook()
		if not book then
			return
		end
		local got = Config.bookStickers(book)
		local fresh = {}
		if known then
			for _, id in Config.GARDEN_BOOK do
				if got[id] and not known[id] then
					table.insert(fresh, id)
				end
			end
		end
		known = got
		if #fresh > 0 then
			task.delay(NEW_WAIT, function()
				Hud.inTurn(function()
					GardenBook.open(fresh)
				end)
			end)
		end
	end
	player:GetAttributeChangedSignal("GardenBook"):Connect(look)
	look()
end

return GardenBook
