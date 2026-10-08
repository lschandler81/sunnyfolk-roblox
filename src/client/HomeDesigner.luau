-- The screen for designing your house: pick its shape, colours, garden and whether it has a
-- sign with your name, and see it change as you go. Opens when you move into a free plot,
-- or from "Change my home" at your own house. With a controller, the ring starts on the
-- build button, and B is "Not now". Choices you have to unlock (the sunflower garden, for a
-- full Garden Book) only show once you have; the server checks that too.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Build = require(Shared.Build)
local Config = require(Shared.Config)
local Houses = require(Shared.Houses)
local Controls = require(script.Parent.Controls)
local Ui = require(script.Parent.Ui)

local Remotes = Shared:WaitForChild("Remotes")
local player = Players.LocalPlayer

local HomeDesigner = {}

local screen: ScreenGui? = nil

-- What you've unlocked for your house (as the server works it out, PlayerData.unlocks).
local function myUnlocks(): Houses.Unlocks
	local book = nil
	local saved = player:GetAttribute("GardenBook")
	if typeof(saved) == "string" then
		local ok, decoded = pcall(function()
			return HttpService:JSONDecode(saved)
		end)
		book = if ok then decoded else nil
	end
	return { gardenBook = Config.bookFull(book) }
end

-- The design they saved last time, or the starting one.
local function savedDesign(): Houses.Design
	local saved = player:GetAttribute("HomeDesign")
	if typeof(saved) == "string" then
		local ok, design = pcall(function()
			return HttpService:JSONDecode(saved)
		end)
		local checked = ok and Houses.check(design, myUnlocks())
		if checked then
			return checked
		end
	end
	return table.clone(Houses.DEFAULT)
end

-- Opens the designer. `plotIndex` is the free plot they're moving into, or nil to change
-- the house they've got. `onDone(message)` runs when it's built.
function HomeDesigner.open(plotIndex: number?, onDone: (string) -> ())
	if screen or Ui.openScreens > 0 then
		return -- not on top of another screen
	end
	local design = savedDesign()
	local moving = plotIndex ~= nil
	local movingHouse = moving and player:GetAttribute("HomePlot") ~= nil -- they've a home already
	local busy = false

	Controls.set(false, "home")
	local gui = Ui.screen("HomeDesigner", 16)
	screen = gui
	-- Laid out for a landscape phone (620 x 290), and grows on bigger screens: the house and the
	-- buttons on the left, the choices on the right.
	local card = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(620, 290),
		BackgroundColor3 = Ui.colors.paper,
		Parent = gui,
	}, { Ui.corner(22), Ui.stroke(3) })
	Ui.fitToScreen(card, 620, 290)

	local turning: RBXScriptConnection? = nil
	local function close()
		if turning then
			turning:Disconnect()
		end
		gui:Destroy()
		screen = nil
		Controls.set(true, "home")
	end
	-- "Not now" (or B) waits while the house is being built
	local function notNow()
		if not busy then
			close()
		end
	end

	Ui.text({
		Text = if movingHouse then "Move house?" elseif moving then "Your new home!" else "Change your home",
		TextSize = 20,
		TextColor3 = Ui.colors.coral,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.fromOffset(212, 26),
		Parent = card,
	})

	-- the picture of the house, turning gently
	local stage = Ui.new("Frame", {
		Position = UDim2.fromOffset(12, 38),
		Size = UDim2.fromOffset(214, 150),
		BackgroundColor3 = Ui.colors.mint,
		Parent = card,
	}, { Ui.corner(16), Ui.stroke(3) })
	local view, camera = Ui.viewport({ Size = UDim2.fromScale(1, 1), Parent = stage })
	local shown: Model? = nil
	local function redraw()
		if shown then
			shown:Destroy()
		end
		local model = Instance.new("Model")
		Build.into(model)
		Houses.build(design, CFrame.identity, if design.sign then player.DisplayName else nil)
		model.WorldPivot = CFrame.identity
		model.Parent = view
		shown = model
		local size = model:GetExtentsSize()
		local centre = model:GetBoundingBox().Position
		local reach = math.max(size.X, size.Y, size.Z) * 1.7
		camera.CFrame = CFrame.lookAt(centre + Vector3.new(0.45, 0.5, 1).Unit * reach, centre)
	end
	turning = RunService.RenderStepped:Connect(function()
		if shown then
			shown:PivotTo(CFrame.Angles(0, math.sin(os.clock() * 0.6) * 0.35, 0))
		end
	end)

	-- the choices
	local right = Ui.new("Frame", {
		Position = UDim2.fromOffset(234, 6),
		Size = UDim2.fromOffset(376, 278),
		BackgroundTransparency = 1,
		Parent = card,
	}, { Ui.new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }) })

	local refresh: () -> ()
	local function row(name: string, order: number): Frame
		local line = Ui.new("Frame", {
			Size = UDim2.new(1, 0, 0, Ui.TOUCH),
			BackgroundTransparency = 1,
			LayoutOrder = order,
			Parent = right,
		})
		Ui.text({ Text = name, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.fromOffset(62, Ui.TOUCH), Parent = line })
		return Ui.new("Frame", {
			Position = UDim2.fromOffset(64, 0),
			Size = UDim2.new(1, -64, 1, 0),
			BackgroundTransparency = 1,
			Parent = line,
		}, {
			Ui.new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 6),
			}),
		})
	end

	local updaters: { () -> () } = {}

	-- a row of word buttons, one of which is picked
	local function words(name: string, order: number, options: { { label: string, pick: () -> (), picked: () -> boolean } })
		local holder = row(name, order)
		-- (four choices are a tight fit, so their buttons have slimmer sides and smaller words)
		local side = if #options > 3 then 6 else 8
		local size = if #options > 3 then 14 else 15
		for _, option in options do
			local button = Ui.button(option.label, Ui.colors.cream, function()
				option.pick()
				refresh()
			end, {
				Size = UDim2.fromOffset(0, Ui.TOUCH),
				AutomaticSize = Enum.AutomaticSize.X,
				TextSize = size,
				Parent = holder,
			})
			Ui.new("UIPadding", { PaddingLeft = UDim.new(0, side), PaddingRight = UDim.new(0, side), Parent = button })
			table.insert(updaters, function()
				button.BackgroundColor3 = if option.picked() then Ui.colors.yellow else Ui.colors.cream
			end)
		end
	end

	-- a row of colour swatches
	local function swatches(name: string, order: number, list: { Houses.Option }, key: string)
		local holder = row(name, order)
		for _, option in list do
			local stroke = Ui.stroke(2.5)
			local button = Ui.new("TextButton", {
				Text = "",
				Size = UDim2.fromOffset(Ui.TOUCH, Ui.TOUCH),
				BackgroundColor3 = Color3.fromHex(option.color or "#ffffff"),
				AutoButtonColor = false,
				Parent = holder,
			}, { Ui.round(), stroke })
			button.Activated:Connect(function()
				(design :: any)[key] = option.id
				refresh()
			end)
			table.insert(updaters, function()
				local picked = (design :: any)[key] == option.id
				stroke.Thickness = if picked then 5 else 2.5
				stroke.Color = if picked then Ui.colors.coral else Ui.colors.ink
			end)
		end
	end

	local shapes = {}
	for _, option in Houses.SHAPES do
		table.insert(shapes, {
			label = option.name,
			pick = function()
				design.shape = option.id
			end,
			picked = function()
				return design.shape == option.id
			end,
		})
	end
	words("Shape", 1, shapes)
	swatches("Walls", 2, Houses.WALLS, "wall")
	swatches("Roof", 3, Houses.ROOFS, "roof")
	swatches("Door", 4, Houses.DOORS, "door")
	local gardens = {}
	local unlocks = myUnlocks()
	for _, option in Houses.GARDENS do
		if not Houses.allowed(option, unlocks) then
			continue
		end
		table.insert(gardens, {
			label = option.name,
			pick = function()
				design.garden = option.id
			end,
			picked = function()
				return design.garden == option.id
			end,
		})
	end
	words("Garden", 5, gardens)
	words("Sign", 6, {
		{
			label = "With my name",
			pick = function()
				design.sign = true
			end,
			picked = function()
				return design.sign
			end,
		},
		{
			label = "No sign",
			pick = function()
				design.sign = false
			end,
			picked = function()
				return not design.sign
			end,
		},
	})

	local note = Ui.text({
		Text = if movingHouse then "Your home will move to this plot." else "More styles coming soon!",
		TextSize = 14,
		TextColor3 = Ui.colors.teal,
		Position = UDim2.fromOffset(12, 190),
		Size = UDim2.fromOffset(214, 40),
		Parent = card,
	})

	Ui.button("Not now", Ui.colors.cream, notNow, {
		Position = UDim2.fromOffset(12, 234),
		Size = UDim2.fromOffset(84, 48),
		TextSize = 17,
		Parent = card,
	})
	local build = Ui.button(if movingHouse then "Move here!" elseif moving then "Build it!" else "Save", Ui.colors.yellow, function()
		if busy then
			return
		end
		busy = true
		note.Text = "Building..."
		local ok, why = Remotes.SetHome:InvokeServer(plotIndex, design)
		busy = false
		if ok then
			close()
			onDone(if moving then "Welcome home!" else "Your home looks lovely!")
		else
			note.Text = why or "Something went wrong. Please try again."
		end
	end, {
		Position = UDim2.fromOffset(102, 234),
		Size = UDim2.fromOffset(124, 48),
		TextSize = 20,
		Parent = card,
	})

	refresh = function()
		for _, update in updaters do
			update()
		end
		redraw()
	end
	refresh()
	Ui.controller(gui, card, build, notNow)
end

function HomeDesigner.isOpen(): boolean
	return screen ~= nil
end

return HomeDesigner
