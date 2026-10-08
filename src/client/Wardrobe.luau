-- "My things": you and everything you own, opened from the HUD's "My things" button. Its
-- "Change animal" button closes it and opens the welcome screen to pick your animal again.
-- Your hats, then your clothes by where they go (round your neck, on your
-- body, on your back). Tap a thing to put it on, and tap it again to take it off. The
-- picture of you turns round to show a backpack. It asks the server with the same Wear remote
-- as the shops (server/HatShop checks you own it, and how often you ask), so nothing new is
-- saved here. With a controller, the ring starts on the first thing; A wears it, B closes.
--
-- The picture and the shelves are the shop screen's own (HatShop.preview, HatShop.thing).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Config = require(Shared.Config)
local Looks = require(Shared.Looks)
local Controls = require(script.Parent.Controls)
local HatShop = require(script.Parent.HatShop)
local Ui = require(script.Parent.Ui)

local Remotes = Shared:WaitForChild("Remotes")
local player = Players.LocalPlayer

local Wardrobe = {}

-- The headings on the shelves, for each place clothes go (Looks.SLOTS).
local SLOT_NAMES = { neck = "Round your neck", body = "On your body", back = "On your back" }

local screen: ScreenGui? = nil

function Wardrobe.isOpen(): boolean
	return screen ~= nil
end

-- `changeAnimal()` opens the welcome screen (once this has closed).
function Wardrobe.open(changeAnimal: () -> ())
	if screen or Ui.openScreens > 0 then
		return -- not on top of another screen
	end
	local listAttribute = HatShop.listAttribute
	local choice = HatShop.myChoice()
	local hats, clothes = HatShop.SHOPS.hats, HatShop.SHOPS.clothes

	Controls.set(false, "wardrobe")
	local gui = Ui.screen("Wardrobe", 15)
	screen = gui
	-- Laid out for a landscape phone (620 x 290), and grows on bigger screens: you on the left,
	-- your things on the right.
	local card = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(620, 290),
		BackgroundColor3 = Ui.colors.paper,
		Parent = gui,
	}, { Ui.corner(22), Ui.stroke(3) })
	Ui.fitToScreen(card, 620, 290)

	local connections: { RBXScriptConnection } = {}
	local preview = HatShop.preview(card, UDim2.fromOffset(12, 58), UDim2.fromOffset(190, 184), clothes.camera)
	local function close()
		for _, c in connections do
			c:Disconnect()
		end
		preview.stop()
		gui:Destroy()
		screen = nil
		Controls.set(true, "wardrobe")
	end

	Ui.text({
		Text = "My things",
		TextSize = 22,
		TextColor3 = Ui.colors.coral,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.fromOffset(240, Ui.TOUCH),
		Parent = card,
	})
	local closeButton = Ui.button("Close", Ui.colors.cream, close, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(84, Ui.TOUCH),
		TextSize = 20,
		Parent = card,
	})
	local animalButton = Ui.button("Change animal", Ui.colors.yellow, function()
		close()
		changeAnimal()
	end, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -100, 0, 8),
		Size = UDim2.fromOffset(150, Ui.TOUCH),
		TextSize = 17,
		Parent = card,
	})
	local note = Ui.text({
		Text = "Tap something to wear it",
		TextSize = 14,
		TextColor3 = Ui.colors.teal,
		Position = UDim2.fromOffset(8, 246),
		Size = UDim2.fromOffset(198, 38),
		Parent = card,
	})

	-- the shelves: a heading and a row of things for each kind you own
	local shelves = HatShop.shelf(card, UDim2.fromOffset(212, 58), UDim2.fromOffset(398, 224),
		Ui.new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }))
	local order = 0
	local function section(title: string): Frame
		order += 1
		Ui.text({
			Text = title,
			TextSize = 16,
			TextColor3 = Ui.colors.coral,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -8, 0, 22),
			LayoutOrder = order,
			Parent = shelves,
		})
		order += 1
		return Ui.new("Frame", {
			Size = UDim2.new(1, -8, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = order,
			Parent = shelves,
		}, { HatShop.grid() })
	end

	-- What's on each shelf: a hat (`slot` nil) or a piece of clothing (with its slot).
	type Entry = { id: string, slot: string?, thing: HatShop.Thing }
	local entries: { Entry } = {}
	local first: GuiObject? = nil
	local lastTapped: Entry? = nil -- the picture turns round to show it, if it's on your back
	local busy = false

	local refresh: () -> ()
	local function wearing(entry: Entry): boolean
		if entry.slot then
			return table.find(listAttribute("Wearing"), entry.id) ~= nil
		end
		return player:GetAttribute("Hat") == entry.id
	end
	local function tapped(entry: Entry)
		if busy then
			return
		end
		local on = wearing(entry)
		lastTapped = entry
		if entry.slot then
			Remotes.Wear:FireServer("clothes", if on then nil else entry.id, entry.slot)
			-- clothes rebuild your animal: wait a moment before the next change
			busy = true
			task.delay(Config.CLOTHES_REBUILD_SECONDS, function()
				busy = false
			end)
		else
			Remotes.Wear:FireServer("hats", if on then nil else entry.id)
		end
		note.Text = if on then "Taken off! Pop it back on any time." else "Looking lovely!"
	end
	local function add(shelf: Frame, n: number, id: string, slot: string?, name: string, model: Model?, from: Vector3)
		local entry: Entry = { id = id, slot = slot, thing = HatShop.thing(shelf, n, model, from, name) }
		entry.thing.coin.Visible = false
		entry.thing.status.TextSize = 13 -- so "Tap to wear" fits the little card
		entry.thing.button.Activated:Connect(function()
			tapped(entry)
		end)
		table.insert(entries, entry)
		first = first or entry.thing.button
	end

	-- hats in the shop's order (cheapest first), so the shelf stays the same; any others after
	local owned = listAttribute("OwnedHats")
	local myHats = {}
	for _, hat in Looks.shopHats() do
		if table.find(owned, hat.id) then
			table.insert(myHats, hat)
		end
	end
	for _, id in owned do
		local hat = Looks.hat(id)
		if hat and not table.find(myHats, hat) then
			table.insert(myHats, hat)
		end
	end
	if #myHats > 0 then
		local shelf = section("Hats")
		for n, hat in myHats do
			add(shelf, n, hat.id, nil, hat.name, hats.thumb(choice.species, hat.id), hats.thumbFrom)
		end
	end
	local myClothes = listAttribute("OwnedClothes")
	for _, slot in Looks.SLOTS do
		local here = {}
		for _, id in myClothes do
			local item = Looks.shopItem(id)
			if item and item.slot == slot then
				table.insert(here, item)
			end
		end
		if #here > 0 then
			local shelf = section(SLOT_NAMES[slot] or slot)
			for n, item in here do
				add(shelf, n, item.id, slot, item.name, clothes.thumb(choice.species, item.id), clothes.thumbFrom)
			end
		end
	end

	-- nothing yet: where to find things, kindly
	if #entries == 0 then
		Ui.text({
			Text = "Nothing here yet! Clover's Hat Shop and the Clothes Shop are round the square,"
				.. " and you can try things on there.",
			TextSize = 17,
			Size = UDim2.new(1, -12, 0, 200),
			Parent = shelves,
		})
		note.Text = ""
	end

	refresh = function()
		for _, entry in entries do
			local on = wearing(entry)
			entry.thing.status.Text = if on then "Wearing" else "Tap to wear"
			HatShop.mark(entry.thing, on)
		end
		-- turned round to show the last thing tapped, if it's on your back and on
		local last = lastTapped
		local showBack = last ~= nil and last.slot == "back" and wearing(last)
		local facing = if showBack then math.rad(Config.UI.SHOW_BACK_TURN) else 0
		preview.show(choice, Looks.playerLook(choice, player:GetAttribute("Hat"), listAttribute("Wearing")), facing)
	end
	for _, attribute in { "Hat", "Wearing" } do
		table.insert(connections, player:GetAttributeChangedSignal(attribute):Connect(refresh))
	end
	refresh()

	Ui.controller(gui, card, first or animalButton, close)
end

return Wardrobe
