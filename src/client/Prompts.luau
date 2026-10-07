-- Shows the game's buttons ("Talk", "Hat Shop", "Make this my home"...) at the bottom middle
-- of the screen, like the web game's talk hint, instead of floating over the person you're
-- talking to (where they'd cover them up). Each one shows its key (E, F, or the controller
-- button) and can also be tapped or clicked.
--
-- It handles every ProximityPrompt whose Style is Custom; the game's prompts all are.

local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")

local Ui = require(script.Parent.Ui)

local Prompts = {}

local PAD_NAMES = {
	[Enum.KeyCode.ButtonA] = "A",
	[Enum.KeyCode.ButtonB] = "B",
	[Enum.KeyCode.ButtonX] = "X",
	[Enum.KeyCode.ButtonY] = "Y",
}

function Prompts.start()
	local gui = Ui.screen("Prompts", 4)
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
	-- On a touch screen, sit higher and a little to the right: clear of the thumbstick (the
	-- left part of the screen) and above the Run and jump buttons (bottom right).
	local function place()
		list.Position = if UserInputService.TouchEnabled then UDim2.new(0.6, 0, 1, -100) else UDim2.new(0.5, 0, 1, -24)
	end
	place()
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(place)

	local shown: { [ProximityPrompt]: GuiObject } = {}

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
		-- clear of the thumbstick on the left.
		local touch = inputType == Enum.ProximityPromptInputType.Touch
		local words = if prompt.ObjectText ~= "" and not touch
			then `{prompt.ActionText}  ·  {prompt.ObjectText}`
			else prompt.ActionText

		local button = Ui.new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			Size = UDim2.fromOffset(0, 54),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = Ui.colors.paper,
			LayoutOrder = if prompt.KeyboardKeyCode == Enum.KeyCode.E then 2 else 1,
			Parent = list,
		}, {
			Ui.round(),
			Ui.stroke(3),
			Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 20) }),
			Ui.new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		if key then
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
			Ui.new("Frame", { Size = UDim2.fromOffset(4, 40), BackgroundTransparency = 1, Parent = button })
		end
		Ui.text({
			Text = words,
			TextSize = if touch then 18 else 22,
			Size = UDim2.fromOffset(0, 40),
			AutomaticSize = Enum.AutomaticSize.X,
			TextWrapped = false,
			LayoutOrder = 2,
			Parent = button,
		})

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
	end)
end

return Prompts
