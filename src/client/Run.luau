-- Running: hold Shift on a keyboard, press the left stick in on a controller, or tap the Run
-- button on a phone or tablet (tap again to walk). The button sits just left of Roblox's jump
-- button, so it's easy to reach with the same thumb.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Sunnyfolk").Config)
local Ui = require(script.Parent.Ui)

local player = Players.LocalPlayer

local Run = {}

local screen: ScreenGui? = nil
local toggled = false -- the Run button or the controller turned running on
local shiftHeld = false

local function running(): boolean
	return toggled or shiftHeld
end

-- Sets the animal's speed to match.
local function apply()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = if running() then Config.PLAYER_RUN_SPEED else Config.PLAYER_WALK_SPEED
	end
end

function Run.start()
	local gui = Ui.screen("Run", 5)
	screen = gui
	gui.Enabled = false

	local button = Ui.button("Run", Ui.colors.paper, function() end, {
		AnchorPoint = Vector2.new(1, 0.5),
		Size = UDim2.fromOffset(72, 72),
		TextSize = 22,
		Visible = UserInputService.TouchEnabled,
		Parent = gui,
	})
	local corner = button:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(1, 0) -- round
	end

	local function show()
		button.BackgroundColor3 = if toggled then Ui.colors.yellow else Ui.colors.paper
		apply()
	end
	button.Activated:Connect(function()
		toggled = not toggled
		show()
	end)

	-- Keep the button just left of Roblox's jump button, which is smaller on phones than on
	-- tablets (these match where Roblox puts it).
	local function place()
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local view = camera.ViewportSize
		local small = math.min(view.X, view.Y) <= 500
		if small then
			button.Position = UDim2.new(1, -106, 1, -55)
		else
			button.Position = UDim2.new(1, -184, 1, -150)
		end
	end
	place()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(place)
	end

	UserInputService.InputBegan:Connect(function(input)
		if UserInputService:GetFocusedTextBox() then
			return -- typing in the chat
		end
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
			shiftHeld = true
			apply()
		elseif input.KeyCode == Enum.KeyCode.ButtonL3 then
			toggled = not toggled
			show()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
			shiftHeld = false
			apply()
		end
	end)
	-- The button appears if a touch screen is used later (some laptops have one).
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(function()
		button.Visible = UserInputService.TouchEnabled
	end)

	-- A new animal (after changing animal) walks or runs as you were.
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Humanoid", 10)
		apply()
	end)
end

-- Hidden while a screen like the welcome screen is open.
function Run.show(visible: boolean)
	if screen then
		screen.Enabled = visible
	end
end

return Run
