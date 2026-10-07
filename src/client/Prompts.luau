-- Shows the game's buttons ("Talk", "Hat Shop", "Make this my home"...) at the bottom middle
-- of the screen, like the web game's talk hint, instead of floating over the person you're
-- talking to (where they'd cover them up). Each one shows its key (E, F, or a picture of the
-- controller button: an Xbox letter or a PlayStation shape) and can also be tapped or clicked.
-- On a TV they're bigger and keep in from the bottom edge. A button that has to be held
-- (like "Make this my home") says "hold" by its key, and fills up with yellow while held.
--
-- It handles every ProximityPrompt whose Style is Custom; the game's prompts all are.

local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

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
	Ui.consoleSize(list)
	-- On a touch screen, sit higher and a little to the right: clear of the thumbstick (the
	-- left part of the screen) and above the Run and jump buttons (bottom right). On a TV,
	-- keep in from the bottom edge.
	local function place()
		list.Position = if Ui.CONSOLE
			then UDim2.fromScale(0.5, 1 - Config.UI.TV_SAFE)
			elseif UserInputService.TouchEnabled then UDim2.new(0.6, 0, 1, -100)
			else UDim2.new(0.5, 0, 1, -24)
	end
	place()
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(place)

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
		-- clear of the thumbstick on the left.
		local touch = inputType == Enum.ProximityPromptInputType.Touch
		local words = if prompt.ObjectText ~= "" and not touch
			then `{prompt.ActionText}  ·  {prompt.ObjectText}`
			else prompt.ActionText

		local button = Ui.new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			Selectable = false, -- a controller presses the button shown on it instead
			Size = UDim2.fromOffset(0, 54),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = Color3.new(1, 1, 1), -- the colours come from `fill` below
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
			Ui.new("Frame", { Size = UDim2.fromOffset(4, 40), BackgroundTransparency = 1, Parent = button })
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
		Ui.text({
			Text = words,
			TextSize = if touch then 18 else 22,
			Size = UDim2.fromOffset(0, 40),
			AutomaticSize = Enum.AutomaticSize.X,
			TextWrapped = false,
			LayoutOrder = 3,
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
