-- What's always on screen while you play: your coins (top right), a button to change your
-- animal, a nudge to find a home until you've got one, and friendly pop-up messages.
-- With a controller, D-pad right puts the ring on the buttons here (A presses, B goes back
-- to walking), like the web game's buttons at the top.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Sunnyfolk").Config)
local Controls = require(script.Parent.Controls)
local Ui = require(script.Parent.Ui)

local player = Players.LocalPlayer

local Hud = {}

local screen: ScreenGui? = nil
local toastLabel: TextLabel? = nil
local toastScale: UIScale? = nil
local toastUntil = 0

function Hud.create(onChangeAnimal: () -> ())
	local gui = Ui.screen("Hud", 5)
	screen = gui
	gui.Enabled = false

	local edge = Config.UI.TV_SAFE
	local corner = Ui.new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = if Ui.CONSOLE then UDim2.fromScale(1 - edge, edge) else UDim2.new(1, -16, 0, 12),
		Size = UDim2.fromOffset(220, 200),
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
		Size = UDim2.fromOffset(0, Ui.TOUCH),
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
	Ui.coin(30, { Parent = pill })
	local count = Ui.text({
		Text = "0",
		TextSize = 26,
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

	Ui.consoleSize(corner)
	Ui.keepRingInside(corner)

	-- the controller's ring on these buttons: on with D-pad right, off with B (Roblox takes
	-- the ring off) or by pressing a button
	local ringHere = false
	local function ringOff()
		if ringHere then
			ringHere = false
			Controls.set(true, "hud")
			if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(corner) then
				GuiService.SelectedObject = nil
			end
		end
	end

	local changeAnimal = Ui.button("Change animal", Ui.colors.cream, function()
		ringOff()
		onChangeAnimal()
	end, {
		Size = UDim2.fromOffset(160, Ui.TOUCH),
		TextSize = 17,
		LayoutOrder = 2,
		Parent = corner,
	})
	-- with a controller, the D-pad picture beside it says how to get there
	local padHint = Ui.new("ImageLabel", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(0, -6, 0.5, 0),
		Size = UDim2.fromOffset(32, 32),
		BackgroundTransparency = 1,
		Image = Ui.padImage(Enum.KeyCode.DPadRight),
		Parent = changeAnimal,
	})
	local function showPadHint()
		padHint.Visible = Ui.usingController() and padHint.Image ~= ""
	end
	UserInputService.LastInputTypeChanged:Connect(function()
		showPadHint()
		if not Ui.usingController() then
			ringOff() -- they've gone back to the mouse, keyboard or touch screen
		end
	end)
	showPadHint()

	UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode == Enum.KeyCode.ButtonB then
			ringOff()
			return
		end
		if input.KeyCode ~= Enum.KeyCode.DPadRight or processed or ringHere then
			return
		end
		if not gui.Enabled or Ui.openScreens > 0 or GuiService.MenuIsOpen then
			return
		end
		ringHere = true
		Controls.set(false, "hud")
		GuiService.SelectedObject = changeAnimal
	end)
	GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
		local now = GuiService.SelectedObject
		if ringHere and not (now and now:IsDescendantOf(corner)) then
			ringOff()
		end
	end)
	gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if not gui.Enabled then
			ringOff()
		end
	end)

	-- a nudge to find a home, until you've got one (under "Change animal", clear of Roblox's
	-- chat window on the left and the jump button below)
	local hint = Ui.new("Frame", {
		Size = UDim2.fromOffset(220, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Ui.colors.paper,
		LayoutOrder = 3,
		Parent = corner,
	}, {
		Ui.corner(14),
		Ui.stroke(2.5),
		Ui.new("UIPadding", {
			PaddingLeft = UDim.new(0, 10),
			PaddingRight = UDim.new(0, 10),
			PaddingTop = UDim.new(0, 6),
			PaddingBottom = UDim.new(0, 6),
		}),
		Ui.text({
			Text = "Pick a free plot at Home Pond or Lily Pond to make your home!",
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Right,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
		}),
	})
	local function updateHint()
		hint.Visible = player:GetAttribute("HomePlot") == nil
	end
	player:GetAttributeChangedSignal("HomePlot"):Connect(updateHint)
	updateHint()

	-- big friendly messages ("Welcome home!")
	toastScale = Ui.new("UIScale")
	toastLabel = Ui.text({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(0, 70),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 0,
		BackgroundColor3 = Ui.colors.yellow,
		TextSize = 30,
		TextWrapped = false,
		Visible = false,
		Parent = gui,
	})
	for _, child in { Ui.round(), Ui.stroke(3.5), toastScale, Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 28), PaddingRight = UDim.new(0, 28) }) } do
		child.Parent = toastLabel
	end
	-- bigger on a TV (its UIScale is used for the pop-in, so the sizes change instead)
	if Ui.CONSOLE and toastLabel then
		toastLabel.TextSize = math.round(30 * Config.UI.CONSOLE_SCALE)
		toastLabel.Size = UDim2.fromOffset(0, math.round(70 * Config.UI.CONSOLE_SCALE))
	end

	-- a reminder for whoever's making the game, when coins won't be kept
	if RunService:IsStudio() and player:GetAttribute("Saving") == false then
		Ui.text({
			Text = "Saving is off in this test",
			TextSize = 14,
			TextColor3 = Ui.colors.coral,
			TextXAlignment = Enum.TextXAlignment.Right,
			Size = UDim2.fromOffset(200, 18),
			LayoutOrder = 4,
			Parent = corner,
		})
	end
end

-- Shows a big friendly message for a few seconds.
function Hud.toast(text: string)
	local label, scale = toastLabel, toastScale
	if not (label and scale) then
		return
	end
	label.Text = text
	label.Visible = true
	scale.Scale = 0.6
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	toastUntil = os.clock() + 3
	task.delay(3, function()
		if os.clock() >= toastUntil then
			label.Visible = false
		end
	end)
end

function Hud.show(visible: boolean)
	if screen then
		screen.Enabled = visible
	end
end

return Hud
