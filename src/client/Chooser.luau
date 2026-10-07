-- The welcome screen: pick your animal (capybara, bunny or guinea pig), its colours and a
-- scarf, see yourself turning round, then press Play. It opens again from the
-- "Change animal" button.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Builder = require(Shared.CharacterBuilder)
local Config = require(Shared.Config)
local Looks = require(Shared.Looks)
local Ui = require(script.Parent.Ui)

export type Choice = { species: string, coat: string, scarf: number }

local Chooser = {}

local NAMES = { capybara = "Capybara", bunny = "Bunny", guineapig = "Guinea pig" }

-- The coat's main colour and the one that goes with it, for its swatch.
local function swatchColors(coat): (Color3, Color3)
	local c = coat.colors
	local second = c.snout or c.ear or c.patch or c.belly or c.dark or c.fur
	return Looks.color(c.fur), Looks.color(second)
end

-- Opens the screen. `onPlay(choice)` runs when they press Play. `hat` is the hat they're
-- wearing, so the picture shows it.
function Chooser.open(start: Choice?, hat: string?, onPlay: (Choice) -> ())
	local choice: Choice = start and table.clone(start) or {
		species = Config.START_ANIMALS[math.random(#Config.START_ANIMALS)],
		coat = "",
		scarf = math.random(#Looks.scarves()),
	}
	if choice.coat == "" then
		choice.coat = Looks.coats(choice.species)[1].id
	end

	-- Laid out for a landscape phone (620 x 290), and grows on bigger screens: the picture and
	-- the Play button on the left, the choices on the right.
	local screen = Ui.screen("Chooser", 20)
	local card = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(620, 290),
		BackgroundColor3 = Ui.colors.paper,
		Parent = screen,
	}, { Ui.corner(22), Ui.stroke(3) })
	Ui.fitToScreen(card, 620, 290)

	-- the picture of you, turning gently from side to side
	local stage = Ui.new("Frame", {
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(190, 206),
		BackgroundColor3 = Ui.colors.mint,
		Parent = card,
	}, { Ui.corner(18), Ui.stroke(3) })
	local view, camera = Ui.viewport({ Size = UDim2.fromScale(1, 1), Parent = stage })
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 3.3, -15), Vector3.new(0, 2.8, 0))
	local shown: Model? = nil
	local function redraw()
		if shown then
			shown:Destroy()
		end
		local look = Looks.playerLook(choice, hat)
		local model = Builder.build(look, { viewport = true })
		model.Parent = view
		shown = model
	end
	local turning = RunService.RenderStepped:Connect(function()
		if shown then
			-- the model's pivot is its root, which sits ROOT_HEIGHT above the feet
			shown:PivotTo(CFrame.new(0, Builder.ROOT_HEIGHT, 0) * CFrame.Angles(0, math.sin(os.clock() * 0.8) * 0.6, 0))
		end
	end)

	-- the choices, on the right
	local right = Ui.new("Frame", {
		Position = UDim2.fromOffset(214, 8),
		Size = UDim2.fromOffset(396, 274),
		BackgroundTransparency = 1,
		Parent = card,
	}, {
		Ui.new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	Ui.text({
		Text = "Welcome to Sunnyfolk!",
		TextSize = 24,
		TextColor3 = Ui.colors.coral,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = 0,
		Parent = right,
	})
	local function heading(text: string, order: number)
		Ui.text({ Text = text, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = order, Parent = right })
	end
	local function row(order: number, height: number, gap: number): Frame
		return Ui.new("Frame", {
			Size = UDim2.new(1, 0, 0, height),
			BackgroundTransparency = 1,
			LayoutOrder = order,
			Parent = right,
		}, { Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, gap) }) })
	end

	local refresh: () -> ()

	heading("Who would you like to be?", 1)
	local animalRow = row(2, 48, 8)
	local animalButtons = {}
	for _, species in Config.START_ANIMALS do
		local button = Ui.button(NAMES[species], Ui.colors.cream, function()
			if choice.species ~= species then
				choice.species = species
				choice.coat = Looks.coats(species)[1].id
				refresh()
			end
		end, { Size = UDim2.fromOffset(124, 48), TextSize = 18, Parent = animalRow })
		animalButtons[species] = button
	end

	heading("Colour", 3)
	local coatRow = row(4, 48, 8)
	heading("Scarf", 5)
	local scarfRow = row(6, Ui.TOUCH, 5)

	local function swatch(parent: Instance, size: number, a: Color3, b: Color3, chosen: boolean, onClick: () -> ())
		local button = Ui.new("TextButton", {
			Text = "",
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = Color3.new(1, 1, 1),
			AutoButtonColor = false,
			Parent = parent,
		}, {
			Ui.round(),
			Ui.stroke(if chosen then 5 else 2.5, if chosen then Ui.colors.coral else Ui.colors.ink),
			Ui.new("UIGradient", {
				Rotation = 45,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, a),
					ColorSequenceKeypoint.new(0.55, a),
					ColorSequenceKeypoint.new(0.551, b),
					ColorSequenceKeypoint.new(1, b),
				}),
			}),
		})
		button.Activated:Connect(onClick)
	end

	refresh = function()
		for species, button in animalButtons do
			local chosen = species == choice.species
			button.BackgroundColor3 = if chosen then Ui.colors.yellow else Ui.colors.cream
			local stroke = button:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Thickness = if chosen then 4 else 3
			end
		end
		for _, child in coatRow:GetChildren() do
			if child:IsA("GuiButton") then
				child:Destroy()
			end
		end
		for _, coat in Looks.coats(choice.species) do
			local a, b = swatchColors(coat)
			swatch(coatRow, 48, a, b, coat.id == choice.coat, function()
				choice.coat = coat.id
				refresh()
			end)
		end
		for _, child in scarfRow:GetChildren() do
			if child:IsA("GuiButton") then
				child:Destroy()
			end
		end
		for i, hex in Looks.scarves() do
			local color = Looks.color(hex)
			swatch(scarfRow, Ui.TOUCH, color, color, i == choice.scarf, function()
				choice.scarf = i
				refresh()
			end)
		end
		redraw()
	end
	refresh()

	Ui.button("Play!", Ui.colors.yellow, function()
		turning:Disconnect()
		screen:Destroy()
		onPlay(choice)
	end, {
		Position = UDim2.fromOffset(12, 226),
		Size = UDim2.fromOffset(190, 54),
		TextSize = 28,
		Parent = card,
	})
end

return Chooser
