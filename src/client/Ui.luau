-- The look of Sunnyfolk's screens, shared by all of them: rounded cream cards with dark
-- outlines and a friendly round font, like the web game.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Ui = {}

Ui.FONT = Enum.Font.FredokaOne
Ui.colors = {
	ink = Color3.fromHex("#2b2622"),
	paper = Color3.fromHex("#fffaf0"),
	cream = Color3.fromHex("#f7e8c8"),
	creamDeep = Color3.fromHex("#e6d0a4"),
	coral = Color3.fromHex("#f07055"),
	yellow = Color3.fromHex("#f6c64a"),
	yellowLight = Color3.fromHex("#fde08a"),
	teal = Color3.fromHex("#2f8a7c"),
	mint = Color3.fromHex("#cdeee3"),
	leaf = Color3.fromHex("#6fa057"),
	grey = Color3.fromHex("#b9b0a2"),
}

-- Makes an instance with some properties set, and puts children in it.
function Ui.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className)
	local parent = nil
	for key, value in pairs(props or {}) do
		if key == "Parent" then
			parent = value
		else
			(instance :: any)[key] = value
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = instance
	end
	instance.Parent = parent
	return instance
end

function Ui.corner(radius: number): UICorner
	return Ui.new("UICorner", { CornerRadius = UDim.new(0, radius) })
end

function Ui.round(): UICorner
	return Ui.new("UICorner", { CornerRadius = UDim.new(1, 0) })
end

function Ui.stroke(thickness: number, color: Color3?): UIStroke
	return Ui.new("UIStroke", {
		Thickness = thickness,
		Color = color or Ui.colors.ink,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Ui.padding(pixels: number): UIPadding
	local p = UDim.new(0, pixels)
	return Ui.new("UIPadding", { PaddingLeft = p, PaddingRight = p, PaddingTop = p, PaddingBottom = p })
end

function Ui.text(props: { [string]: any }): TextLabel
	local defaults = {
		BackgroundTransparency = 1,
		Font = Ui.FONT,
		TextColor3 = Ui.colors.ink,
		TextSize = 22,
		TextWrapped = true,
	}
	for key, value in pairs(props) do
		defaults[key] = value
	end
	return Ui.new("TextLabel", defaults)
end

-- A chunky button that squashes a little when pressed.
function Ui.button(text: string, color: Color3, onClick: () -> (), props: { [string]: any }?): TextButton
	local scale = Ui.new("UIScale")
	local button = Ui.new("TextButton", {
		Text = text,
		Font = Ui.FONT,
		TextSize = 24,
		TextColor3 = Ui.colors.ink,
		BackgroundColor3 = color,
		AutoButtonColor = false,
	}, { Ui.corner(16), Ui.stroke(3), scale })
	for key, value in pairs(props or {}) do
		(button :: any)[key] = value
	end
	local function squash(to: number)
		TweenService:Create(scale, TweenInfo.new(0.08), { Scale = to }):Play()
	end
	button.MouseButton1Down:Connect(function()
		squash(0.94)
	end)
	button.MouseButton1Up:Connect(function()
		squash(1)
	end)
	button.MouseLeave:Connect(function()
		squash(1)
	end)
	button.Activated:Connect(onClick)
	return button
end

-- A little yellow coin.
function Ui.coin(size: number, props: { [string]: any }?): Frame
	local coin = Ui.new("Frame", {
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = Ui.colors.yellow,
	}, {
		Ui.round(),
		Ui.stroke(math.max(2, size / 14)),
		Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.55, 0.55),
			BackgroundTransparency = 1,
		}, { Ui.round(), Ui.stroke(math.max(1.5, size / 16), Ui.colors.yellowLight) }),
	})
	for key, value in pairs(props or {}) do
		(coin :: any)[key] = value
	end
	return coin
end

-- Every button should be at least this big (in pixels) on the smallest phone, so a child's
-- finger can hit it. Screens are designed for a phone first and grow on bigger screens.
Ui.TOUCH = 44
Ui.MAX_SCALE = 1.6 -- how much a screen may grow on a tablet or computer

-- A screen for the local player. It keeps clear of Roblox's top bar and of phone notches and
-- rounded corners.
function Ui.screen(name: string, order: number): ScreenGui
	return Ui.new("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		DisplayOrder = order,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
end

-- Fits a card designed at `width` x `height` pixels (for a landscape phone) to the space on
-- the screen: a little smaller on the tiniest phones, bigger on tablets and computers (up to
-- Ui.MAX_SCALE). The card must already be in its ScreenGui.
function Ui.fitToScreen(card: GuiObject, width: number, height: number)
	local scale = Ui.new("UIScale", { Parent = card })
	local screen = card:FindFirstAncestorOfClass("ScreenGui")
	local function fit()
		local space = if screen then screen.AbsoluteSize else Vector2.new(width, height)
		if space.X > 0 and space.Y > 0 then
			-- a small fixed margin, so a phone that just fits gets the card at full size
			scale.Scale = math.min(Ui.MAX_SCALE, (space.X - 16) / width, (space.Y - 12) / height)
		end
	end
	fit()
	if screen then
		screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	end
end

-- A ViewportFrame with a camera, for showing a 3D model in a screen.
function Ui.viewport(props: { [string]: any }): (ViewportFrame, Camera)
	local camera = Ui.new("Camera", { FieldOfView = 30 })
	local defaults = {
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(200, 196, 190),
		LightColor = Color3.new(1, 1, 1),
		LightDirection = Vector3.new(-0.4, -1, 0.7),
	}
	for key, value in pairs(props) do
		defaults[key] = value
	end
	local view = Ui.new("ViewportFrame", defaults, { camera })
	view.CurrentCamera = camera
	return view, camera
end

return Ui
