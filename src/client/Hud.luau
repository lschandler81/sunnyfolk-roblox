-- What's always on screen while you play: a row along the top right (the Goals and "My
-- things" buttons, the Garden Book's round button, and your coins in the corner), room under
-- it for the goal you're on
-- (client/GoalsPanel), a nudge to find a home once the goals are done, and friendly pop-up
-- messages.
-- With a controller, D-pad right puts the ring on the buttons here (A presses, B goes back
-- to walking), like the web game's buttons at the top.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Sunnyfolk").Config)
local GoalList = require(ReplicatedStorage:WaitForChild("Sunnyfolk").Goals)
local Controls = require(script.Parent.Controls)
local Ui = require(script.Parent.Ui)

local player = Players.LocalPlayer

local Hud = {}

local screen: ScreenGui? = nil
local cornerFrame: Frame? = nil
local toastLabel: TextLabel? = nil
local toastScale: UIScale? = nil
local toastHome: Instance? = nil -- the HUD's screen, where the message sits on bigger screens
local toastPadding: UIPadding? = nil
local toastUntil = 0

function Hud.create(onGoals: () -> (), onMyThings: () -> (), onBook: () -> ())
	local gui = Ui.screen("Hud", 5)
	-- Roblox's own buttons are only at the top left, so the HUD can sit right up in the top
	-- right corner, level with them (still clear of a phone's notch and rounded corners).
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	screen = gui
	gui.Enabled = false

	local edge = Config.UI.TV_SAFE
	local corner = Ui.new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = if Ui.CONSOLE then UDim2.fromScale(1 - edge, edge) else UDim2.new(1, -16, 0, 12),
		Size = UDim2.fromOffset(470, 260), -- (room for the row of buttons and the coins)
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		Ui.new("UIListLayout", {
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	-- one row along the top: the Goals and "My things" buttons and the Garden Book's round
	-- button, then your coins in the corner
	local top = Ui.new("Frame", {
		Size = UDim2.fromOffset(0, Ui.TOUCH),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = corner,
	}, {
		Ui.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
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
		LayoutOrder = 4,
		Parent = top,
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

	cornerFrame = corner
	Ui.hudSize(corner)
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

	-- the Goals and "My things" buttons, along the top beside the coins (each just wide enough
	-- for its words, so the row stays clear of Roblox's buttons). "Change animal" is inside
	-- My things.
	local buttons = top
	local goals = Ui.button("Goals", Ui.colors.yellow, function()
		ringOff()
		onGoals()
	end, {
		Size = UDim2.fromOffset(84, Ui.TOUCH),
		TextSize = 17,
		LayoutOrder = 1,
		Parent = buttons,
	})
	Ui.button("My things", Ui.colors.cream, function()
		ringOff()
		onMyThings()
	end, {
		Size = UDim2.fromOffset(112, Ui.TOUCH),
		TextSize = 17,
		LayoutOrder = 2,
		Parent = buttons,
	})
	-- the Garden Book: a round button with a little green book on it (a sunflower on its
	-- cover), so it needs no words. It shows once the Garden is open.
	local bookButton = Ui.button("", Ui.colors.cream, function()
		ringOff()
		onBook()
	end, {
		Size = UDim2.fromOffset(Ui.TOUCH, Ui.TOUCH),
		LayoutOrder = 3,
		Visible = false,
		Parent = buttons,
	})
	local round = bookButton:FindFirstChildOfClass("UICorner")
	if round then
		round.CornerRadius = UDim.new(1, 0)
	end
	local cover = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(22, 26),
		BackgroundColor3 = Ui.colors.leaf,
		Parent = bookButton,
	}, { Ui.corner(4), Ui.stroke(2) })
	Ui.new("Frame", { -- the pages, peeping out down the side
		Position = UDim2.new(1, -5, 0, 3),
		Size = UDim2.new(0, 3, 1, -6),
		BackgroundColor3 = Ui.colors.paper,
		BorderSizePixel = 0,
		Parent = cover,
	})
	Ui.new("Frame", { -- the sunflower on the cover
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.42, 0.5),
		Size = UDim2.fromOffset(11, 11),
		BackgroundColor3 = Ui.colors.yellow,
		Parent = cover,
	}, { Ui.round(), Ui.stroke(1.5, Color3.fromHex("#7a4a26")) })
	local function showBook()
		bookButton.Visible = GoalList.gardenOpen(GoalList.fromAttribute(player:GetAttribute("GoalsDone")))
	end
	player:GetAttributeChangedSignal("GoalsDone"):Connect(showBook)
	showBook()
	-- with a controller, the D-pad picture beside them says how to get there
	local padHint = Ui.new("ImageLabel", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(0, -6, 0.5, 0),
		Size = UDim2.fromOffset(32, 32),
		BackgroundTransparency = 1,
		Image = Ui.padImage(Enum.KeyCode.DPadRight),
		Parent = goals,
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
		GuiService.SelectedObject = goals
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

	-- a nudge to find a home, once the goals are done if they still haven't got one (under the
	-- buttons, clear of Roblox's chat window on the left and the jump button below; while
	-- they're doing the goals, the goal card sits here, at LayoutOrder 3)
	local hint = Ui.new("Frame", {
		Size = UDim2.fromOffset(250, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Ui.colors.paper,
		LayoutOrder = 4,
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
		local goalsDone = GoalList.allDone(GoalList.fromAttribute(player:GetAttribute("GoalsDone")))
		hint.Visible = goalsDone and player:GetAttribute("HomePlot") == nil
	end
	player:GetAttributeChangedSignal("HomePlot"):Connect(updateHint)
	player:GetAttributeChangedSignal("GoalsDone"):Connect(updateHint)
	updateHint()

	-- big friendly messages ("Welcome home!")
	toastHome = gui
	toastScale = Ui.new("UIScale")
	toastLabel = Ui.text({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 0,
		BackgroundColor3 = Ui.colors.yellow,
		TextSize = 30,
		TextWrapped = false,
		RichText = true,
		Visible = false,
		Parent = gui,
	})
	toastPadding = Ui.new("UIPadding", {
		PaddingLeft = UDim.new(0, 28),
		PaddingRight = UDim.new(0, 28),
		PaddingTop = UDim.new(0, 16),
		PaddingBottom = UDim.new(0, 16),
	})
	for _, child in { Ui.corner(30), Ui.stroke(3.5), toastScale, toastPadding } do
		child.Parent = toastLabel
	end
	-- bigger on a TV (its UIScale is used for the pop-in, so the sizes change instead)
	if Ui.CONSOLE and toastLabel and toastPadding then
		toastLabel.TextSize = math.round(30 * Config.UI.CONSOLE_SCALE)
		toastPadding.PaddingTop = UDim.new(0, math.round(16 * Config.UI.CONSOLE_SCALE))
		toastPadding.PaddingBottom = UDim.new(0, math.round(16 * Config.UI.CONSOLE_SCALE))
	end

	-- a reminder for whoever's making the game, when coins won't be kept
	if RunService:IsStudio() and player:GetAttribute("Saving") == false then
		Ui.text({
			Text = "Saving is off in this test",
			TextSize = 14,
			TextColor3 = Ui.colors.coral,
			TextXAlignment = Enum.TextXAlignment.Right,
			Size = UDim2.fromOffset(200, 18),
			LayoutOrder = 5,
			Parent = corner,
		})
	end
end

-- Shows a big friendly message, with a smaller line under it if `small` is given. It stays
-- longer the more there is to read (Config.UI.MESSAGE_...). On a phone on its side it sits at
-- the top left (Ui.messages), clear of your animal; elsewhere in the middle of the screen.
-- (Only the game's own words go here: it's shown as rich text.)
function Hud.toast(text: string, small: string?)
	local label, scale = toastLabel, toastScale
	if not (label and scale) then
		return
	end
	local phone = Ui.shortScreen() and not Ui.CONSOLE
	-- (slimmer sides on a phone, so the words have room in the narrow column)
	local side = if phone then 14 else 28
	if toastPadding then
		toastPadding.PaddingLeft = UDim.new(0, side)
		toastPadding.PaddingRight = UDim.new(0, side)
	end
	if phone then
		label.AnchorPoint = Vector2.zero
		label.Position = UDim2.new()
		label.Size = UDim2.fromScale(1, 0)
		label.AutomaticSize = Enum.AutomaticSize.Y
		label.TextWrapped = true
		label.TextSize = 20
		label.LayoutOrder = 2 -- under anything a resident is saying
		label.Parent = Ui.messages()
	else
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.42)
		label.Size = UDim2.fromOffset(0, 0)
		label.AutomaticSize = Enum.AutomaticSize.XY
		label.TextWrapped = false
		label.TextSize = if Ui.CONSOLE then math.round(30 * Config.UI.CONSOLE_SCALE) else 30
		label.Parent = toastHome
	end
	label.Text = if small then `{text}\n<font size="{math.round(label.TextSize * 0.65)}">{small}</font>` else text
	label.Visible = true
	scale.Scale = 0.6
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	local letters = utf8.len(text .. (small or "")) or #text
	local seconds = math.min(Config.UI.MESSAGE_SECONDS + letters * Config.UI.MESSAGE_LETTER, Config.UI.MESSAGE_MAX)
	toastUntil = os.clock() + seconds
	task.delay(seconds, function()
		if os.clock() >= toastUntil then
			label.Visible = false
		end
	end)
end

-- Whether the big message has finished, so another can be shown without cutting it short.
function Hud.toastFree(): boolean
	return os.clock() >= toastUntil
end

-- Things waiting their turn to be shown (see Hud.inTurn).
local waiting: { () -> () } = {}
local running = false

-- Runs `show` once you're playing (the HUD is up), no screen is open (the Hat Shop, the house
-- designer...) and no big message is showing, so it's never hidden or cut short. Things wait
-- in the order they came.
function Hud.inTurn(show: () -> ())
	table.insert(waiting, show)
	if running then
		return
	end
	running = true
	task.spawn(function()
		while #waiting > 0 do
			local clearSince = os.clock()
			repeat
				task.wait(0.25)
				local playing = screen ~= nil and screen.Enabled
				if not playing or Ui.openScreens > 0 or not Hud.toastFree() then
					clearSince = os.clock()
				end
			until os.clock() - clearSince >= 0.5
			local nextOne = table.remove(waiting, 1)
			-- in its own thread, so one going wrong never stops the rest
			task.spawn(nextOne)
		end
		running = false
	end)
end

-- A big friendly message, in turn (see Hud.inTurn).
function Hud.announce(text: string, small: string?)
	Hud.inTurn(function()
		Hud.toast(text, small)
	end)
end

-- The frame in the top right, for the goal card to go in (client/GoalsPanel).
function Hud.corner(): Frame?
	return cornerFrame
end

function Hud.show(visible: boolean)
	if screen then
		screen.Enabled = visible
	end
	-- a message showing goes too, so it doesn't pop back up afterwards (on a phone it sits
	-- outside the HUD's screen)
	if not visible and toastLabel then
		toastLabel.Visible = false
		toastUntil = 0
	end
end

return Hud
