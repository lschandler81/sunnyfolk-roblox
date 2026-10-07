-- The shop screen, for Clover's Hat Shop and the Clothes Shop. Tap something to try it on (the
-- picture shows you wearing it), then buy it with coins, put it on, or take it off. The
-- server checks every purchase (server/HatShop). With a controller, the ring starts on what
-- you're wearing (or the first thing), and B says bye.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Builder = require(Shared.CharacterBuilder)
local Looks = require(Shared.Looks)
local Controls = require(script.Parent.Controls)
local Ui = require(script.Parent.Ui)

local Remotes = Shared:WaitForChild("Remotes")
local player = Players.LocalPlayer

local HatShop = {}

-- What's different about each shop.
type Shop = {
	title: string,
	says: { string }, -- a friendly line when you come in
	items: () -> { any }, -- what it sells, cheapest first
	thumb: (string, string) -> Model?, -- (species, id): one thing on its own, for a shelf
	thumbFrom: Vector3, -- which way the shelf's little camera looks at it
	camera: CFrame, -- the try-on picture's camera
	owned: string, -- the attribute listing what you own
}

local SHOPS: { [string]: Shop } = {
	hats = {
		title = "Clover's Hat Shop",
		says = {
			"A good hat makes any day better.",
			"Try on as many as you like!",
			"Every hat here fits every animal.",
		},
		items = Looks.shopHats,
		thumb = Builder.hatModel,
		thumbFrom = Vector3.new(0.3, 0.55, -1),
		-- close up on the head and the hat (the picture is wider than it is tall)
		camera = CFrame.lookAt(Vector3.new(0, 5.4, -10), Vector3.new(0, 4.6, 0)),
		owned = "OwnedHats",
	},
	clothes = {
		title = "The Clothes Shop",
		says = {
			"Something cosy for every animal!",
			"Try on as many as you like!",
			"One for your neck, your body and your back.",
		},
		items = Looks.shopClothes,
		thumb = Builder.clothesModel,
		thumbFrom = Vector3.new(0.35, 0.25, -1),
		-- the whole animal
		camera = CFrame.lookAt(Vector3.new(0, 3.6, -15), Vector3.new(0, 2.7, 0)),
		owned = "OwnedClothes",
	},
}

local screen: ScreenGui? = nil

local function listAttribute(name: string): { string }
	local list = player:GetAttribute(name)
	return if typeof(list) == "string" and list ~= "" then string.split(list, ",") else {}
end

local function coins(): number
	return player:GetAttribute("Coins") or 0
end

local function myChoice()
	local look = player:GetAttribute("Look")
	if typeof(look) == "string" then
		local ok, choice = pcall(function()
			return HttpService:JSONDecode(look)
		end)
		if ok then
			return choice
		end
	end
	return { species = "capybara", coat = "toffee", scarf = 1 }
end

-- Points a ViewportFrame's camera at a model so all of it fits.
local function frame(camera: Camera, model: Model, from: Vector3)
	local size = model:GetExtentsSize()
	local biggest = math.max(size.X, size.Y, size.Z)
	local centre = model:GetBoundingBox().Position
	camera.CFrame = CFrame.lookAt(centre + from.Unit * (biggest * 2.3 + 1), centre)
end

-- Opens a shop: "hats" or "clothes".
function HatShop.open(shopId: string?)
	if screen or Ui.openScreens > 0 then
		return -- not on top of another screen
	end
	local id = shopId or "hats"
	local shop = SHOPS[id]
	if not shop then
		return
	end
	local isHats = id == "hats"
	local choice = myChoice()
	local items = shop.items()
	local function find(itemId: string?): any
		for _, item in items do
			if item.id == itemId then
				return item
			end
		end
		return nil
	end
	-- start on what you're wearing, if anything, or else the first thing
	local wornNow = if isHats then player:GetAttribute("Hat") else listAttribute("Wearing")[1]
	local selected: string? = if find(wornNow) then wornNow else items[1].id
	local message = shop.says[math.random(#shop.says)]
	local busy = false

	Controls.set(false, "hatshop")
	local gui = Ui.screen("HatShop", 15)
	screen = gui
	-- Laid out for a landscape phone (620 x 290), and grows on bigger screens: you trying the
	-- hat on, on the left; the shelves of hats on the right.
	local card = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(620, 290),
		BackgroundColor3 = Ui.colors.paper,
		Parent = gui,
	}, { Ui.corner(22), Ui.stroke(3) })
	Ui.fitToScreen(card, 620, 290)

	local connections: { RBXScriptConnection } = {}
	local function close()
		for _, c in connections do
			c:Disconnect()
		end
		gui:Destroy()
		screen = nil
		Controls.set(true, "hatshop")
	end

	Ui.text({
		Text = shop.title,
		TextSize = 22,
		TextColor3 = Ui.colors.coral,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.fromOffset(240, Ui.TOUCH),
		Parent = card,
	})
	Ui.button("Bye!", Ui.colors.cream, close, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(76, Ui.TOUCH),
		TextSize = 20,
		Parent = card,
	})

	-- your coins
	local wallet = Ui.new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -92, 0, 8),
		Size = UDim2.fromOffset(0, Ui.TOUCH),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Ui.colors.cream,
		Parent = card,
	}, {
		Ui.round(),
		Ui.stroke(3),
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 14) }),
		Ui.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
		}),
	})
	Ui.coin(28, { Parent = wallet })
	local walletText = Ui.text({ TextSize = 20, Size = UDim2.fromOffset(0, 36), AutomaticSize = Enum.AutomaticSize.X, Parent = wallet })

	-- the try-on picture
	local stage = Ui.new("Frame", {
		Position = UDim2.fromOffset(12, 58),
		Size = UDim2.fromOffset(190, 120),
		BackgroundColor3 = Ui.colors.mint,
		Parent = card,
	}, { Ui.corner(16), Ui.stroke(3) })
	local view, camera = Ui.viewport({ Size = UDim2.fromScale(1, 1), Parent = stage })
	camera.CFrame = shop.camera
	local you: Model? = nil
	-- which way you face in the picture: the front, or turned round to show a backpack
	local facing, turnedTo = 0, 0
	table.insert(connections, RunService.RenderStepped:Connect(function()
		if you then
			-- turn smoothly towards the way you should face, swaying gently from side to side
			turnedTo += (facing - turnedTo) * 0.12
			you:PivotTo(CFrame.new(0, Builder.ROOT_HEIGHT, 0) * CFrame.Angles(0, turnedTo + math.sin(os.clock() * 0.8) * 0.5, 0))
		end
	end))

	local hatName = Ui.text({
		TextSize = 15,
		Position = UDim2.fromOffset(12, 180),
		Size = UDim2.fromOffset(190, 19),
		Parent = card,
	})
	local note = Ui.text({
		TextSize = 14,
		Position = UDim2.fromOffset(8, 200),
		Size = UDim2.fromOffset(198, 36),
		Parent = card,
	})
	local action = Ui.button("", Ui.colors.yellow, function() end, {
		Position = UDim2.fromOffset(12, 239),
		Size = UDim2.fromOffset(190, Ui.TOUCH),
		TextSize = 20,
		Parent = card,
	})

	-- the shelves
	local shelves = Ui.new("ScrollingFrame", {
		Position = UDim2.fromOffset(212, 58),
		Size = UDim2.fromOffset(398, 224),
		BackgroundColor3 = Ui.colors.cream,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Ui.colors.ink,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Selectable = false, -- a controller's ring goes straight to the things on the shelves
		Parent = card,
	}, {
		Ui.corner(16),
		Ui.stroke(3),
		Ui.padding(6),
		Ui.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(88, 104),
			CellPadding = UDim2.fromOffset(6, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	local refresh: () -> ()
	local cards: { [string]: { button: TextButton, price: TextLabel, stroke: UIStroke } } = {}

	for i, hat in items do
		local stroke = Ui.stroke(2.5)
		local button = Ui.new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Ui.colors.paper,
			LayoutOrder = i,
			Parent = shelves,
		}, { Ui.corner(12), stroke })
		local thumb, thumbCamera = Ui.viewport({
			Position = UDim2.fromOffset(14, 2),
			Size = UDim2.fromOffset(60, 52),
			Parent = button,
		})
		local model = shop.thumb(choice.species, hat.id)
		if model then
			model:PivotTo(CFrame.Angles(0, 0.5, 0))
			model.Parent = thumb
			frame(thumbCamera, model, shop.thumbFrom)
		end
		Ui.text({
			Text = hat.name,
			TextSize = 13,
			Position = UDim2.fromOffset(2, 54),
			Size = UDim2.new(1, -4, 0, 32),
			Parent = button,
		})
		local priceRow = Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 86),
			Size = UDim2.fromOffset(0, 18),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Parent = button,
		}, {
			Ui.new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 4),
			}),
		})
		local coin = Ui.coin(15, { Parent = priceRow })
		local price = Ui.text({
			TextSize = 14,
			TextWrapped = false, -- so "Wearing" is never cut short
			Size = UDim2.fromOffset(0, 18),
			AutomaticSize = Enum.AutomaticSize.X,
			Parent = priceRow,
		})
		price:SetAttribute("Price", hat.price)
		coin.Name = "Coin"
		button.Activated:Connect(function()
			selected = hat.id
			message = ""
			refresh()
		end)
		cards[hat.id] = { button = button, price = price, stroke = stroke }
	end

	local shownLook = ""
	refresh = function()
		local mine = listAttribute(shop.owned)
		local wearing = if isHats then { player:GetAttribute("Hat") } else listAttribute("Wearing")
		walletText.Text = tostring(coins())

		for itemId, c in cards do
			local have = table.find(mine, itemId) ~= nil
			c.price.Text = if table.find(wearing, itemId) then "Wearing"
				elseif have then "Yours!"
				else tostring(c.price:GetAttribute("Price"))
			local coin = c.price.Parent and c.price.Parent:FindFirstChild("Coin")
			if coin and coin:IsA("GuiObject") then
				coin.Visible = not have
			end
			c.stroke.Color = if itemId == selected then Ui.colors.coral else Ui.colors.ink
			c.stroke.Thickness = if itemId == selected then 4.5 else 2.5
			c.button.BackgroundColor3 = if itemId == selected then Ui.colors.yellowLight else Ui.colors.paper
		end

		-- you, trying on the selected thing: a hat on its own, or clothes with the rest of what
		-- you're wearing (the selected one taking the place of whatever's in its slot)
		local hatOn = player:GetAttribute("Hat")
		local clothesOn = listAttribute("Wearing")
		local look
		if isHats then
			look = Looks.playerLook(choice, selected, clothesOn)
		else
			local picked = Looks.shopItem(selected)
			-- show your back for something worn on it (a three-quarter turn, so you see your face too)
			facing = if picked and picked.slot == "back" then math.rad(150) else 0
			local outfit = {}
			for _, worn in clothesOn do
				local item = Looks.shopItem(worn)
				if item and not (picked and item.slot == picked.slot) then
					table.insert(outfit, worn)
				end
			end
			if picked then
				table.insert(outfit, picked.id)
			end
			look = Looks.playerLook(choice, hatOn, outfit)
		end
		local lookKey = `{choice.species}/{choice.coat}/{choice.scarf}/{look.hat}/{table.concat(look.clothes, ",")}`
		if lookKey ~= shownLook then
			shownLook = lookKey
			if you then
				you:Destroy()
			end
			you = Builder.build(look, { viewport = true })
			;(you :: Model).Parent = view
		end

		local hat = find(selected)
		hatName.Text = if hat then hat.name else ""
		local have = selected ~= nil and table.find(mine, selected) ~= nil
		local canAfford = hat ~= nil and coins() >= hat.price
		local stroke = action:FindFirstChildOfClass("UIStroke")
		if hat and table.find(wearing, selected) then
			action.Text = "Take it off"
			action.BackgroundColor3 = Ui.colors.cream
		elseif have then
			action.Text = "Wear it"
			action.BackgroundColor3 = Ui.colors.yellow
		elseif hat then
			action.Text = `Buy for {hat.price}`
			action.BackgroundColor3 = if canAfford then Ui.colors.yellow else Ui.colors.creamDeep
			if not canAfford and message == "" then
				message = `You need {hat.price - coins()} more coins. Look around the square!`
			end
		end
		action.TextColor3 = if hat and not have and not canAfford then Ui.colors.grey else Ui.colors.ink
		if stroke then
			stroke.Color = if hat and not have and not canAfford then Ui.colors.grey else Ui.colors.ink
		end
		note.Text = message
	end

	action.Activated:Connect(function()
		local item = find(selected)
		if busy or not item then
			return
		end
		local have = table.find(listAttribute(shop.owned), item.id) ~= nil
		local wearingIt = if isHats then item.id == player:GetAttribute("Hat") else table.find(listAttribute("Wearing"), item.id) ~= nil
		if wearingIt or have then
			Remotes.Wear:FireServer(id, if wearingIt then nil else item.id, item.slot)
			message = if not wearingIt then "Looking lovely!"
				elseif isHats then "Hat off! Pop it back on any time."
				else "Taken off! Pop it back on any time."
			if not isHats then
				-- clothes rebuild your animal: wait a moment before the next change
				busy = true
				task.delay(1, function()
					busy = false
				end)
			end
		elseif coins() >= item.price then
			busy = true
			local ok, why = Remotes.Buy:InvokeServer(id, item.id)
			busy = false
			message = if ok then `The {item.name} is yours! On it goes.` else (why or "")
		end
		refresh()
	end)

	for _, attribute in { "Coins", "Hat", "Wearing", shop.owned } do
		table.insert(connections, player:GetAttributeChangedSignal(attribute):Connect(refresh))
	end
	refresh()

	local start = (selected and cards[selected]) or cards[items[1].id]
	Ui.controller(gui, card, start.button, close)
end

function HatShop.isOpen(): boolean
	return screen ~= nil
end

return HatShop
