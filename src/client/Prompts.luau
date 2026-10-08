-- Shows the game's buttons ("Talk", "Hat Shop", "Make this my home"...) at the bottom middle
-- of the screen, like the web game's talk hint, instead of floating over the person you're
-- talking to (where they'd cover them up). Each one shows its key (E, F, or a picture of the
-- controller button: an Xbox letter or a PlayStation shape) and can also be tapped or clicked.
-- On a TV they're bigger and keep in from the bottom edge. On a phone or tablet they're
-- smaller, side by side in one row along the bottom, between the thumbstick and the Run and
-- jump buttons, so they never cover your animal. A button that has to be held (like "Make
-- this my home") says "hold" by its key, and fills up with yellow while held.
--
-- It handles every ProximityPrompt whose Style is Custom; the game's prompts all are.

local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Sunnyfolk").Config)
local Ui = require(script.Parent.Ui)

local Prompts = {}

local PAD_NAMES = {
	[Enum.KeyCode.ButtonA] = "A",
	[Enum.KeyCode.ButtonB] = "B",
	[Enum.KeyCode.ButtonX] = "X",
	[Enum.KeyCode.ButtonY] = "Y",
}

function Prompts.start()
	local gui = Ui.screen("Prompts", 6) -- above the HUD, so nothing covers these buttons
	local list = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(420, 200),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		Ui.new("UIListLayout", {
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local layout = list:FindFirstChildOfClass("UIListLayout") :: UIListLayout
	Ui.consoleSize(list)

	-- A phone: a phone-sized touch screen, or any screen as short as a phone on its side. Its
	-- buttons are always the small kind, even if the last thing pressed was a key (Studio's
	-- phone emulator counts the mouse as a keyboard).
	local function phoneSized(): boolean
		local camera = Workspace.CurrentCamera
		local view = if camera then camera.ViewportSize else gui.AbsoluteSize
		return Ui.shortScreen() or (UserInputService.TouchEnabled and math.min(view.X, view.Y) <= Config.UI.PHONE_SIZE)
	end
	-- On a touch screen, sit along the bottom in the middle of the free space: right of the
	-- thumbstick (the left part of the screen) and left of the Run and jump buttons (bottom
	-- right, which are bigger on a tablet, like in client/Run). On a TV, keep in from the
	-- bottom edge.
	local function place()
		if Ui.CONSOLE then
			list.Position = UDim2.fromScale(0.5, 1 - Config.UI.TV_SAFE)
		elseif UserInputService.TouchEnabled then
			-- side by side, onto a second row only if they don't fit
			layout.FillDirection = Enum.FillDirection.Horizontal
			layout.Wraps = true
			local wide = gui.AbsoluteSize.X
			local camera = Workspace.CurrentCamera
			local view = if camera then camera.ViewportSize else gui.AbsoluteSize
			local phone = math.min(view.X, view.Y) <= Config.UI.PHONE_SIZE
			local left = wide * Config.UI.THUMBSTICK
			local right = wide - (if phone then Config.UI.RUN_CLEAR_PHONE else Config.UI.RUN_CLEAR_TABLET)
			list.Position = UDim2.new(0, (left + right) / 2, 1, -Config.UI.PROMPT_BOTTOM)
			list.Size = UDim2.fromOffset(math.max(0, right - left), 200)
		else
			layout.FillDirection = Enum.FillDirection.Vertical
			layout.Wraps = false
			list.Position = UDim2.new(0.5, 0, 1, -24)
			list.Size = UDim2.fromOffset(420, 200)
		end
	end
	place()
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(place)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)

	local shown: { [ProximityPrompt]: GuiObject } = {}
	local holding: { [ProximityPrompt]: { RBXScriptConnection } } = {}

	ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
		if prompt.Style ~= Enum.ProximityPromptStyle.Custom or shown[prompt] then
			return
		end
		-- the key to press: E or F on a keyboard, X or Y on a controller, nothing on a touch screen
		local key = if inputType == Enum.ProximityPromptInputType.Gamepad
			then PAD_NAMES[prompt.GamepadKeyCode] or "A"
			elseif inputType == Enum.ProximityPromptInputType.Touch then nil
			else UserInputService:GetStringForKeyCode(prompt.KeyboardKeyCode)
		-- On a touch screen, just the action ("Make this my home"), so the button stays short and
		-- clear of the thumbstick on the left. (A phone with a controller keeps the button
		-- pictures.)
		local gamepad = inputType == Enum.ProximityPromptInputType.Gamepad
		local touch = inputType == Enum.ProximityPromptInputType.Touch or (phoneSized() and not gamepad)
		if touch then
			key = nil
		end
		-- smaller on a phone or tablet, so it fits beside the thumbstick and Run
		local tall = if touch then Config.UI.PROMPT_HEIGHT else 54
		local inner = tall - 14 -- the key, or the space where it would be
		local function wordsFor(): string
			return if prompt.ObjectText ~= "" and not touch
				then `{prompt.ActionText}  ·  {prompt.ObjectText}`
				else prompt.ActionText
		end

		local button = Ui.new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			Selectable = false, -- a controller presses the button shown on it instead
			Size = UDim2.fromOffset(0, tall),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = Color3.new(1, 1, 1), -- the colours come from `fill` below
			LayoutOrder = if prompt.KeyboardKeyCode == Enum.KeyCode.E then 2 else 1,
			Parent = list,
		}, {
			Ui.round(),
			Ui.stroke(3),
			Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, if touch then 14 else 20) }),
			Ui.new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		-- Yellow fills the button from the left while it's held. The edge between yellow and
		-- cream sits off the left end at first, and slides across to the right end.
		local EMPTY, FULL = Vector2.new(-0.5, 0), Vector2.new(0.5, 0)
		local fill = Ui.new("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Ui.colors.yellow),
				ColorSequenceKeypoint.new(0.5, Ui.colors.yellow),
				ColorSequenceKeypoint.new(0.501, Ui.colors.paper),
				ColorSequenceKeypoint.new(1, Ui.colors.paper),
			}),
			Offset = EMPTY,
			Parent = button,
		})
		local filling: Tween? = nil
		local function stopFilling()
			if filling then
				filling:Cancel()
				filling = nil
			end
			fill.Offset = EMPTY
		end
		holding[prompt] = {
			prompt.PromptButtonHoldBegan:Connect(function()
				stopFilling()
				filling = TweenService:Create(fill, TweenInfo.new(prompt.HoldDuration, Enum.EasingStyle.Linear), { Offset = FULL })
				;(filling :: Tween):Play()
			end),
			prompt.PromptButtonHoldEnded:Connect(stopFilling),
		}

		local padImage = if inputType == Enum.ProximityPromptInputType.Gamepad
			then Ui.padImage(prompt.GamepadKeyCode)
			else ""
		if padImage ~= "" then
			Ui.new("ImageLabel", {
				Image = padImage,
				Size = UDim2.fromOffset(40, 40),
				BackgroundTransparency = 1,
				LayoutOrder = 1,
				Parent = button,
			})
		elseif key then
			local badge = Ui.text({
				Text = key,
				TextSize = 22,
				Size = UDim2.fromOffset(40, 40),
				BackgroundTransparency = 0,
				BackgroundColor3 = Ui.colors.yellow,
				LayoutOrder = 1,
				Parent = button,
			})
			Ui.round().Parent = badge
			Ui.stroke(2.5).Parent = badge
		else
			Ui.new("Frame", { Size = UDim2.fromOffset(4, inner), BackgroundTransparency = 1, Parent = button })
		end
		-- "hold" by the key, for buttons that need holding (tapping one holds it for you)
		if prompt.HoldDuration > 0 and not touch then
			Ui.text({
				Text = "hold",
				TextSize = 16,
				TextColor3 = Ui.colors.teal,
				Size = UDim2.fromOffset(0, 40),
				AutomaticSize = Enum.AutomaticSize.X,
				TextWrapped = false,
				LayoutOrder = 2,
				Parent = button,
			})
		end
		local label = Ui.text({
			Text = wordsFor(),
			TextSize = if touch then Config.UI.PROMPT_TEXT else 22,
			Size = UDim2.fromOffset(0, inner),
			AutomaticSize = Enum.AutomaticSize.X,
			TextWrapped = false,
			LayoutOrder = 3,
			Parent = button,
		})
		-- On a phone, long words shrink a little until the button fits the space between the
		-- thumbstick and Run.
		local function shrink()
			if touch and button.AbsoluteSize.X > list.AbsoluteSize.X and label.TextSize > Config.UI.PROMPT_MIN_TEXT then
				label.TextSize -= 1
			end
		end
		table.insert(holding[prompt], button:GetPropertyChangedSignal("AbsoluteSize"):Connect(shrink))
		shrink()
		-- the words can change while it's showing (a garden bed counting down)
		local function rewrite()
			label.Text = wordsFor()
			if touch then
				label.TextSize = Config.UI.PROMPT_TEXT
				shrink()
			end
		end
		table.insert(holding[prompt], prompt:GetPropertyChangedSignal("ActionText"):Connect(rewrite))
		table.insert(holding[prompt], prompt:GetPropertyChangedSignal("ObjectText"):Connect(rewrite))

		-- tapping or clicking it works like pressing the key
		button.Activated:Connect(function()
			prompt:InputHoldBegin()
			task.delay(prompt.HoldDuration + 0.05, function()
				prompt:InputHoldEnd()
			end)
		end)
		shown[prompt] = button
	end)

	ProximityPromptService.PromptHidden:Connect(function(prompt)
		local button = shown[prompt]
		if button then
			button:Destroy()
			shown[prompt] = nil
		end
		local connections = holding[prompt]
		if connections then
			for _, connection in connections do
				connection:Disconnect()
			end
			holding[prompt] = nil
		end
	end)
end

return Prompts
