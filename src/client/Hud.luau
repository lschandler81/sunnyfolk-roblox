-- What's always on screen while you play: your coins (top right) and a button to change
-- your animal.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Ui = require(script.Parent.Ui)

local player = Players.LocalPlayer

local Hud = {}

local screen: ScreenGui? = nil

function Hud.create(onChangeAnimal: () -> ())
	local gui = Ui.screen("Hud", 5)
	screen = gui
	gui.Enabled = false

	local corner = Ui.new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 12),
		Size = UDim2.fromOffset(200, 140),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		Ui.new("UIListLayout", {
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	-- the coin counter
	local pop = Ui.new("UIScale")
	local pill = Ui.new("Frame", {
		Size = UDim2.fromOffset(0, 50),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Ui.colors.paper,
		LayoutOrder = 1,
		Parent = corner,
	}, {
		Ui.round(),
		Ui.stroke(3),
		pop,
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 18) }),
		Ui.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 8),
		}),
	})
	Ui.coin(34, { Parent = pill })
	local count = Ui.text({
		Text = "0",
		TextSize = 30,
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = pill,
	})

	local shown = player:GetAttribute("Coins") or 0
	local function update()
		local coins = player:GetAttribute("Coins") or 0
		count.Text = tostring(coins)
		if coins > shown then
			pop.Scale = 1.2
			TweenService:Create(pop, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end
		shown = coins
	end
	player:GetAttributeChangedSignal("Coins"):Connect(update)
	update()

	Ui.button("Change animal", Ui.colors.cream, onChangeAnimal, {
		Size = UDim2.fromOffset(170, 40),
		TextSize = 19,
		LayoutOrder = 2,
		Parent = corner,
	})

	-- a reminder for whoever's making the game, when coins won't be kept
	if RunService:IsStudio() and player:GetAttribute("Saving") == false then
		Ui.text({
			Text = "Saving is off in this test",
			TextSize = 14,
			TextColor3 = Ui.colors.coral,
			TextXAlignment = Enum.TextXAlignment.Right,
			Size = UDim2.fromOffset(200, 18),
			LayoutOrder = 3,
			Parent = corner,
		})
	end
end

function Hud.show(visible: boolean)
	if screen then
		screen.Enabled = visible
	end
end

return Hud
