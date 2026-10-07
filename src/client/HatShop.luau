-- Clover's Hat Shop screen. Tap a hat to try it on (the picture shows you wearing it), then
-- buy it with coins, put it on, or take it off. The server checks every purchase
-- (server/HatShop).

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

local CLOVER_SAYS = {
	"A good hat makes any day better.",
	"Try on as many as you like!",
	"Every hat here fits every animal.",
}

local screen: ScreenGui? = nil

local function owned(): { string }
	local list = player:GetAttribute("OwnedHats")
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

function HatShop.open()
	if screen then
		return
	end
	local choice = myChoice()
	local hats = Looks.shopHats()
	local selected: string? = player:GetAttribute("Hat") or hats[1].id
	local message = CLOVER_SAYS[math.random(#CLOVER_SAYS)]
	local busy = false

	Controls.set(false)
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
		Controls.set(true)
	end

	Ui.text({
		Text = "Clover's Hat Shop",
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
	-- close up on the head and the hat (the picture is wider than it is tall)
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 5.4, -10), Vector3.new(0, 4.6, 0))
	local you: Model? = nil
	table.insert(connections, RunService.RenderStepped:Connect(function()
		if you then
			you:PivotTo(CFrame.new(0, Builder.ROOT_HEIGHT, 0) * CFrame.Angles(0, math.sin(os.clock() * 0.8) * 0.5, 0))
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

	for i, hat in hats do
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
		local model = Builder.hatModel(choice.species, hat.id)
		if model then
			model:PivotTo(CFrame.Angles(0, 0.5, 0))
			model.Parent = thumb
			frame(thumbCamera, model, Vector3.new(0.3, 0.55, -1))
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
		local price = Ui.text({ TextSize = 14, Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, Parent = priceRow })
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
		local mine = owned()
		local wearing = player:GetAttribute("Hat")
		walletText.Text = tostring(coins())

		for id, c in cards do
			local have = table.find(mine, id) ~= nil
			c.price.Text = if id == wearing then "Wearing" elseif have then "Yours!" else tostring(c.price:GetAttribute("Price"))
			local coin = c.price.Parent and c.price.Parent:FindFirstChild("Coin")
			if coin and coin:IsA("GuiObject") then
				coin.Visible = not have
			end
			c.stroke.Color = if id == selected then Ui.colors.coral else Ui.colors.ink
			c.stroke.Thickness = if id == selected then 4.5 else 2.5
			c.button.BackgroundColor3 = if id == selected then Ui.colors.yellowLight else Ui.colors.paper
		end

		-- you, trying on the selected hat
		local lookKey = `{choice.species}/{choice.coat}/{choice.scarf}/{selected}`
		if lookKey ~= shownLook then
			shownLook = lookKey
			if you then
				you:Destroy()
			end
			you = Builder.build(Looks.playerLook(choice, selected), { viewport = true })
			;(you :: Model).Parent = view
		end

		local hat = Looks.hat(selected)
		hatName.Text = if hat then hat.name else "No hat"
		local have = selected ~= nil and table.find(mine, selected) ~= nil
		local canAfford = hat ~= nil and coins() >= hat.price
		local stroke = action:FindFirstChildOfClass("UIStroke")
		if hat and selected == wearing then
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
		local hat = Looks.hat(selected)
		if busy or not hat then
			return
		end
		local have = table.find(owned(), hat.id) ~= nil
		if hat.id == player:GetAttribute("Hat") then
			Remotes.WearHat:FireServer(nil)
			message = "Hat off! Pop it back on any time."
		elseif have then
			Remotes.WearHat:FireServer(hat.id)
			message = "Looking lovely!"
		elseif coins() >= hat.price then
			busy = true
			local ok, why = Remotes.BuyHat:InvokeServer(hat.id)
			busy = false
			message = if ok then `The {hat.name} is yours! Clover pops it on your head.` else (why or "")
		end
		refresh()
	end)

	for _, attribute in { "Coins", "OwnedHats", "Hat" } do
		table.insert(connections, player:GetAttributeChangedSignal(attribute):Connect(refresh))
	end
	refresh()
end

function HatShop.isOpen(): boolean
	return screen ~= nil
end

return HatShop
