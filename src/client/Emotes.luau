-- Emotes on the player's screen: a round button on the right edge (above Run and the jump
-- button, clear of the thumbstick) opens a row of picture buttons to its left, one for each
-- of Config.EMOTES: wave, cheer, dance and sit. Pressing one plays it on your animal straight
-- away (client/Animator) and tells the server, which passes it on to players nearby
-- (server/Emotes); their screens play it on your animal too.
--
-- With a controller, D-pad left opens the row with the ring on the first emote: A plays it,
-- B closes. The buttons live in the HUD's screen, so they hide with it.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Config = require(Shared.Config)
local Animator = require(script.Parent.Animator)
local Controls = require(script.Parent.Controls)
local Ui = require(script.Parent.Ui)

local Remotes = Shared:WaitForChild("Remotes")
local player = Players.LocalPlayer

local MAIN = 56 -- the round button, pixels
local CHOICE = 52 -- each emote's button, pixels (both over Config.UI.TOUCH)

local Emotes = {}

local function round(button: GuiObject)
	local corner = button:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(1, 0)
	end
end

-- `gui` is the HUD's screen (Hud.gui).
function Emotes.start(gui: ScreenGui)
	-- Other players' emotes, passed on by the server: play them on their animal.
	Remotes.Emote.OnClientEvent:Connect(function(who, id)
		if typeof(who) ~= "Instance" or not who:IsA("Player") or not Config.emote(id) then
			return
		end
		local model = (who :: Player).Character
		if model then
			Animator.emote(model, id)
		end
	end)

	-- the row: the emotes (hidden until opened), then the round button on the right
	local row = Ui.new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = if Ui.CONSOLE
			then UDim2.fromScale(1 - Config.UI.TV_SAFE, 0.55)
			else UDim2.new(1, -16, 0.55, 0),
		Size = UDim2.fromOffset(0, MAIN),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		Ui.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	Ui.consoleSize(row)
	Ui.keepRingInside(row) -- the controller's ring can't wander off onto the HUD's buttons

	local choices: { GuiButton } = {}
	local open = false
	local ringHere = false -- the controller's ring is on the emotes
	local last = 0

	local function close()
		open = false
		for _, button in choices do
			button.Visible = false
		end
		if ringHere then
			ringHere = false
			Controls.set(true, "emotes")
			if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(row) then
				GuiService.SelectedObject = nil
			end
		end
	end

	local function play(id: string)
		close()
		local model = player.Character
		if not model or os.clock() - last < Config.EMOTE_WAIT or Ui.openScreens > 0 then
			return
		end
		last = os.clock()
		Animator.emote(model, id)
		Remotes.Emote:FireServer(id)
	end

	for i, emote in Config.EMOTES do
		local button = Ui.button(emote.icon, Ui.colors.paper, function()
			play(emote.id)
		end, {
			Size = UDim2.fromOffset(CHOICE, CHOICE),
			TextSize = 28,
			LayoutOrder = i,
			Visible = false,
			Parent = row,
		})
		round(button)
		table.insert(choices, button)
	end

	local function openRow(withRing: boolean)
		if Ui.openScreens > 0 then
			return
		end
		open = true
		for _, button in choices do
			button.Visible = true
		end
		if withRing then
			ringHere = true
			Controls.set(false, "emotes")
			GuiService.SelectedObject = choices[1]
		end
	end

	local main = Ui.button(Config.EMOTE_BUTTON, Ui.colors.yellow, function()
		if open then
			close()
		else
			openRow(false)
		end
	end, {
		Size = UDim2.fromOffset(MAIN, MAIN),
		TextSize = 30,
		LayoutOrder = #Config.EMOTES + 1,
		Selectable = false, -- a controller opens the emotes with D-pad left instead
		Parent = row,
	})
	round(main)

	-- with a controller, the D-pad picture beside the button says how to open it
	local padHint = Ui.new("ImageLabel", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(0, -6, 0.5, 0),
		Size = UDim2.fromOffset(32, 32),
		BackgroundTransparency = 1,
		Image = Ui.padImage(Enum.KeyCode.DPadLeft),
		Parent = main,
	})
	local function showPadHint()
		padHint.Visible = not open and Ui.usingController() and padHint.Image ~= ""
	end
	UserInputService.LastInputTypeChanged:Connect(function()
		-- back to the mouse, keyboard or touch screen: put the ring away, so walking works again
		if ringHere and not Ui.usingController() then
			close()
		end
		showPadHint()
	end)
	showPadHint()

	UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode == Enum.KeyCode.ButtonB and open then
			close()
		elseif input.KeyCode == Enum.KeyCode.DPadLeft and not processed and not open then
			-- (not while the ring is on something else, like the HUD's buttons)
			if gui.Enabled and not GuiService.MenuIsOpen and GuiService.SelectedObject == nil then
				openRow(true)
			end
		end
		showPadHint()
	end)
	-- the ring left the emotes (Roblox's B, or another screen took it): put them away
	GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
		local now = GuiService.SelectedObject
		if ringHere and not (now and now:IsDescendantOf(row)) then
			close()
			showPadHint()
		end
	end)
	-- and when the HUD hides (the welcome screen)
	gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if not gui.Enabled then
			close()
			showPadHint()
		end
	end)
end

return Emotes
