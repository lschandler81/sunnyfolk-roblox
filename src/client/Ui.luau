-- The look of Sunnyfolk's screens, shared by all of them: rounded cream cards with dark
-- outlines and a friendly round font, like the web game. Also how the screens work with a
-- controller (Ui.controller).

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Sunnyfolk").Config)

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
Ui.TOUCH = Config.UI.TOUCH

-- Playing on a TV, sitting across the room (an Xbox or PlayStation). Everything is bigger.
Ui.CONSOLE = GuiService:IsTenFootInterface()
Ui.MAX_SCALE = Config.UI.MAX_SCALE * (if Ui.CONSOLE then Config.UI.CONSOLE_SCALE else 1)

-- On a TV, makes `object` bigger (Config.UI.CONSOLE_SCALE), keeping it where it is.
function Ui.consoleSize(object: GuiObject)
	if Ui.CONSOLE then
		Ui.new("UIScale", { Scale = Config.UI.CONSOLE_SCALE, Parent = object })
	end
end

-- Is this a phone on its side (a short screen)? Some things are smaller there.
function Ui.shortScreen(): boolean
	local camera = workspace.CurrentCamera
	return camera ~= nil and camera.ViewportSize.Y > 0 and camera.ViewportSize.Y < Config.UI.SHORT_SCREEN
end

-- For the HUD: phone size on a phone, a little bigger on taller screens (a tablet or
-- computer, up to Config.UI.HUD_MAX_SCALE), and Config.UI.CONSOLE_SCALE on a TV. `object`
-- must already be in its ScreenGui.
function Ui.hudSize(object: GuiObject)
	if Ui.CONSOLE then
		Ui.consoleSize(object)
		return
	end
	local scale = Ui.new("UIScale", { Parent = object })
	local screen = object:FindFirstAncestorOfClass("ScreenGui")
	local function fit()
		local tall = if screen then screen.AbsoluteSize.Y else 0
		scale.Scale = math.clamp(tall / Config.UI.HUD_HEIGHT, 1, Config.UI.HUD_MAX_SCALE)
	end
	fit()
	if screen then
		screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	end
end

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
		if Ui.CONSOLE then
			space *= 1 - 2 * Config.UI.TV_SAFE -- keep in from the TV's edges
		end
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

---------------------------------------------------------------- controllers

local PADS = {
	[Enum.UserInputType.Gamepad1] = true,
	[Enum.UserInputType.Gamepad2] = true,
	[Enum.UserInputType.Gamepad3] = true,
	[Enum.UserInputType.Gamepad4] = true,
}

-- Is the player using a controller right now (rather than a mouse, keyboard or touch)? On a
-- TV it's always yes, even before the first button press.
function Ui.usingController(): boolean
	return Ui.CONSOLE or PADS[UserInputService:GetLastInputType()] == true
end

-- The picture of a controller button (A, B, X, Y, the D-pad...) that matches the player's
-- controller: Xbox letters or PlayStation shapes. "" if Roblox hasn't one.
function Ui.padImage(key: Enum.KeyCode): string
	local ok, image = pcall(function()
		return UserInputService:GetImageForKeyCode(key)
	end)
	return if ok and typeof(image) == "string" then image else ""
end

-- How many screens with controller support are open (the HUD leaves the controller alone
-- while one is).
Ui.openScreens = 0

-- The ring that shows which button a controller is on: thick yellow with a dark edge, so it
-- shows on yellow buttons too, like the web game's.
do
	local ring = Ui.new("Frame", {
		Name = "SelectionRing",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(-5, -5),
		Size = UDim2.new(1, 10, 1, 10),
	}, { Ui.corner(20), Ui.stroke(5, Ui.colors.yellow) })
	Ui.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(-5, -5),
		Size = UDim2.new(1, 10, 1, 10),
		Parent = ring,
	}, { Ui.corner(24), Ui.stroke(2.5) })
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	playerGui.SelectionImageObject = ring
end

-- Keeps the controller's ring inside `area`: the D-pad and left stick stop at its edges.
function Ui.keepRingInside(area: GuiObject)
	area.SelectionGroup = true
	area.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	area.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	area.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	area.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
end

-- Makes a screen work with a controller. When it opens with a controller in use, the ring
-- sits on `first` (its main button); the D-pad or left stick moves it between the card's
-- buttons (Roblox finds the nearest one that way, and scrolls lists to show it); A presses;
-- B runs `back` (closing the screen), if there is one. If the ring is lost (B with nothing
-- to close, or its button was rebuilt), it comes back to the last button, or `first`.
-- Everything is tidied away when the screen is destroyed.
function Ui.controller(gui: ScreenGui, card: GuiObject, first: GuiObject, back: (() -> ())?)
	Ui.keepRingInside(card)
	Ui.openScreens += 1
	local last: GuiObject? = nil

	local function inside(object: GuiObject?): boolean
		return object ~= nil and object:IsDescendantOf(card)
	end
	local function putRing()
		if not gui.Parent or not Ui.usingController() or inside(GuiService.SelectedObject) then
			return
		end
		local target = if last and inside(last) and last.Visible then last else first
		if inside(target) then
			GuiService.SelectedObject = target
		end
	end

	local connections = {
		GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
			local now = GuiService.SelectedObject
			if inside(now) then
				last = now
			elseif now == nil then
				task.defer(putRing)
			end
		end),
		-- picking up the controller part way through
		UserInputService.LastInputTypeChanged:Connect(putRing),
		UserInputService.InputBegan:Connect(function(input)
			if input.KeyCode == Enum.KeyCode.ButtonB and back and gui.Parent and not GuiService.MenuIsOpen then
				back()
			end
		end),
	}
	gui.Destroying:Connect(function()
		for _, connection in connections do
			connection:Disconnect()
		end
		Ui.openScreens -= 1
		if inside(GuiService.SelectedObject) then
			GuiService.SelectedObject = nil
		end
	end)
	task.defer(putRing)
end

-- The message area on a phone on its side: a column at the top left, under Roblox's buttons
-- (Config.UI.MESSAGE_...). What a resident says (client/Talk) and the big messages
-- (client/Hud) go in it, one under the other, so they never cover each other. On a TV the big
-- messages go here too, kept in from the edges (Config.UI.TV_SAFE) and wider, for bigger words.
local messageColumn: Frame? = nil
function Ui.messages(): Frame
	if messageColumn and messageColumn.Parent then
		return messageColumn
	end
	local gui = Ui.screen("Messages", 4) -- under the HUD and the buttons, if ever they meet
	local column = Ui.new("Frame", {
		Position = if Ui.CONSOLE
			then UDim2.fromScale(Config.UI.TV_SAFE, Config.UI.TV_SAFE)
			else UDim2.fromOffset(Config.UI.MESSAGE_LEFT, Config.UI.MESSAGE_TOP),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		Ui.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local function fit()
		local across = gui.AbsoluteSize.X
		if across <= 0 and workspace.CurrentCamera then
			across = workspace.CurrentCamera.ViewportSize.X
		end
		local most = Config.UI.MESSAGE_MAX_WIDTH * (if Ui.CONSOLE then 2 * Config.UI.CONSOLE_SCALE else 1)
		column.Size = UDim2.fromOffset(math.min(across * Config.UI.MESSAGE_WIDTH, most), 0)
	end
	fit()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	messageColumn = column
	return column
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
