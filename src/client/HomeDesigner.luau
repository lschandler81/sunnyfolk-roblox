-- The screen for designing your house: pick its shape, colours, garden and whether it has a
-- sign with your name, and see it change as you go. Opens when you move into a free plot,
-- or from "Change my home" at your own house.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Build = require(Shared.Build)
local Houses = require(Shared.Houses)
local Controls = require(script.Parent.Controls)
local Ui = require(script.Parent.Ui)

local Remotes = Shared:WaitForChild("Remotes")
local player = Players.LocalPlayer

local HomeDesigner = {}

local screen: ScreenGui? = nil

-- The design they saved last time, or the starting one.
local function savedDesign(): Houses.Design
	local saved = player:GetAttribute("HomeDesign")
	if typeof(saved) == "string" then
		local ok, design = pcall(function()
			return HttpService:JSONDecode(saved)
		end)
		local checked = ok and Houses.check(design)
		if checked then
			return checked
		end
	end
	return table.clone(Houses.DEFAULT)
end

-- Opens the designer. `plotIndex` is the free plot they're moving into, or nil to change
-- the house they've got. `onDone(message)` runs when it's built.
function HomeDesigner.open(plotIndex: number?, onDone: (string) -> ())
	if screen then
		return
	end
	local design = savedDesign()
	local moving = plotIndex ~= nil
	local movingHouse = moving and player:GetAttribute("HomePlot") ~= nil -- they've a home already
	local busy = false

	Controls.set(false)
	local gui = Ui.screen("HomeDesigner", 16)
	screen = gui
	local card = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(900, 520),
		BackgroundColor3 = Ui.colors.paper,
		Parent = gui,
	}, { Ui.corner(28), Ui.stroke(4) })
	Ui.fitToScreen(card, 900, 540)

	local turning: RBXScriptConnection? = nil
	local function close()
		if turning then
			turning:Disconnect()
		end
		gui:Destroy()
		screen = nil
		Controls.set(true)
	end

	Ui.text({
		Text = if movingHouse then "Move house?" elseif moving then "Your new home!" else "Change your home",
		TextSize = 36,
		TextColor3 = Ui.colors.coral,
		Position = UDim2.fromOffset(0, 18),
		Size = UDim2.new(1, 0, 0, 44),
		Parent = card,
	})

	-- the picture of the house, turning gently
	local stage = Ui.new("Frame", {
		Position = UDim2.fromOffset(30, 80),
		Size = UDim2.fromOffset(380, 340),
		BackgroundColor3 = Ui.colors.mint,
		Parent = card,
	}, { Ui.corner(22), Ui.stroke(3) })
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
		Position = UDim2.fromOffset(436, 80),
		Size = UDim2.fromOffset(440, 340),
		BackgroundTransparency = 1,
		Parent = card,
	}, { Ui.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })

	local refresh: () -> ()
	local function row(name: string, order: number): Frame
		local line = Ui.new("Frame", {
			Size = UDim2.new(1, 0, 0, 48),
			BackgroundTransparency = 1,
			LayoutOrder = order,
			Parent = right,
		})
		Ui.text({ Text = name, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.fromOffset(90, 48), Parent = line })
		return Ui.new("Frame", {
			Position = UDim2.fromOffset(92, 0),
			Size = UDim2.new(1, -92, 1, 0),
			BackgroundTransparency = 1,
			Parent = line,
		}, {
			Ui.new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 8),
			}),
		})
	end

	local updaters: { () -> () } = {}

	-- a row of word buttons, one of which is picked
	local function words(name: string, order: number, options: { { label: string, pick: () -> (), picked: () -> boolean } })
		local holder = row(name, order)
		for _, option in options do
			local button = Ui.button(option.label, Ui.colors.cream, function()
				option.pick()
				refresh()
			end, {
				Size = UDim2.fromOffset(0, 40),
				AutomaticSize = Enum.AutomaticSize.X,
				TextSize = 18,
				Parent = holder,
			})
			Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), Parent = button })
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
				Size = UDim2.fromOffset(40, 40),
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
	for _, option in Houses.GARDENS do
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
		TextSize = 17,
		TextColor3 = Ui.colors.teal,
		Position = UDim2.fromOffset(30, 432),
		Size = UDim2.fromOffset(380, 60),
		Parent = card,
	})

	Ui.button("Not now", Ui.colors.cream, close, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -290, 1, -26),
		Size = UDim2.fromOffset(150, 60),
		TextSize = 24,
		Parent = card,
	})
	Ui.button(if movingHouse then "Move here!" elseif moving then "Build it!" else "Save", Ui.colors.yellow, function()
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
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -30, 1, -26),
		Size = UDim2.fromOffset(240, 60),
		TextSize = 30,
		Parent = card,
	})

	refresh = function()
		for _, update in updaters do
			update()
		end
		redraw()
	end
	refresh()
end

function HomeDesigner.isOpen(): boolean
	return screen ~= nil
end

return HomeDesigner
