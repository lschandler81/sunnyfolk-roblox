-- The Pet Shop screen (Config.PETS). Before you've a pet: pick a puppy, kitten or duckling, a
-- colour and a name (from a list: "New name" picks another), and adopt it. After: change any
-- of those for free, and buy and put on collars and things for its head. The picture shows
-- your pet as it'll look. The server checks everything (server/Pets). With a controller, the
-- ring starts on the main button, and B says bye.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Config = require(Shared.Config)
local PetBuilder = require(Shared.PetBuilder)
local Controls = require(script.Parent.Controls)
local Ui = require(script.Parent.Ui)

local Remotes = Shared:WaitForChild("Remotes")
local player = Players.LocalPlayer
local PETS = Config.PETS

local PetShop = {}

local screen: ScreenGui? = nil

type Look = { kind: string, color: number, name: number, collar: string?, top: string? }

-- The pet you've got, as the server says, or nil.
local function myPet(): Look?
	local saved = player:GetAttribute("Pet")
	if typeof(saved) ~= "string" then
		return nil
	end
	local ok, look = pcall(function()
		return HttpService:JSONDecode(saved)
	end)
	return if ok and typeof(look) == "table" and PETS.KINDS[look.kind] then look else nil
end

local function owned(): { string }
	local list = player:GetAttribute("PetGear")
	return if typeof(list) == "string" and list ~= "" then string.split(list, ",") else {}
end

local function coins(): number
	return player:GetAttribute("Coins") or 0
end

function PetShop.open()
	if screen or Ui.openScreens > 0 then
		return -- not on top of another screen
	end
	local current = myPet()
	local preview: Look = if current
		then table.clone(current)
		else { kind = PETS.ORDER[1], color = 1, name = math.random(#PETS.NAMES) }
	local trying: string? = nil -- a piece of gear you haven't got, being tried on
	local message = if current then "Hello again! Something new to wear?" else "Who would you like to take home?"
	local busy = false

	Controls.set(false, "petshop")
	local gui = Ui.screen("PetShop", 15)
	screen = gui
	-- Laid out for a landscape phone (620 x 290), and grows on bigger screens.
	local card = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(620, 290),
		BackgroundColor3 = Ui.colors.paper,
		Parent = gui,
	}, { Ui.corner(22), Ui.stroke(3) })
	Ui.fitToScreen(card, 620, 290)

	local connections: { RBXScriptConnection } = {}
	local function close()
		for _, c in connections do
			c:Disconnect()
		end
		gui:Destroy()
		screen = nil
		Controls.set(true, "petshop")
	end

	Ui.text({
		Text = "The Pet Shop",
		TextSize = 22,
		TextColor3 = Ui.colors.coral,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.fromOffset(160, Ui.TOUCH),
		Parent = card,
	})
	local note = Ui.text({
		TextSize = 14,
		TextColor3 = Ui.colors.teal,
		Position = UDim2.fromOffset(176, 6),
		Size = UDim2.fromOffset(250, 48),
		Parent = card,
	})
	Ui.button("Bye!", Ui.colors.cream, close, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(76, Ui.TOUCH),
		TextSize = 20,
		Parent = card,
	})
	local wallet = Ui.new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -92, 0, 8),
		Size = UDim2.fromOffset(0, Ui.TOUCH),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Ui.colors.cream,
		Parent = card,
	}, {
		Ui.round(),
		Ui.stroke(3),
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 14) }),
		Ui.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
		}),
	})
	Ui.coin(28, { Parent = wallet })
	local walletText = Ui.text({ TextSize = 20, TextWrapped = false, Size = UDim2.fromOffset(0, 36), AutomaticSize = Enum.AutomaticSize.X, Parent = wallet })

	-- the picture of your pet, turning gently
	local stage = Ui.new("Frame", {
		Position = UDim2.fromOffset(12, 58),
		Size = UDim2.fromOffset(190, 110),
		BackgroundColor3 = Ui.colors.mint,
		Parent = card,
	}, { Ui.corner(16), Ui.stroke(3) })
	local view, camera = Ui.viewport({ Size = UDim2.fromScale(1, 1), Parent = stage })
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 2.6, -9), Vector3.new(0, 1.1, 0))
	local shown: PetBuilder.Pet? = nil
	local shownKey = ""
	table.insert(connections, RunService.RenderStepped:Connect(function()
		if shown then
			local pose = table.clone(PetBuilder.STANDING)
			pose.wag = math.sin(os.clock() * 8) * 0.5
			PetBuilder.place(shown, CFrame.Angles(0, math.sin(os.clock() * 0.8) * 0.6, 0), pose) -- facing the camera
		end
	end))

	-- its name, and a button for another one
	local nameLabel = Ui.text({
		TextSize = 18,
		Position = UDim2.fromOffset(12, 172),
		Size = UDim2.fromOffset(96, Ui.TOUCH),
		Parent = card,
	})
	local refresh: () -> ()
	Ui.button("New name", Ui.colors.cream, function()
		local before = preview.name
		repeat
			preview.name = math.random(#PETS.NAMES)
		until preview.name ~= before or #PETS.NAMES < 2
		refresh()
	end, {
		Position = UDim2.fromOffset(110, 172),
		Size = UDim2.fromOffset(92, Ui.TOUCH),
		TextSize = 15,
		Parent = card,
	})
	local action = Ui.button("", Ui.colors.yellow, function() end, {
		Position = UDim2.fromOffset(12, 228),
		Size = UDim2.fromOffset(190, 48),
		TextSize = 20,
		Parent = card,
	})

	-- the choices, in rows on the right
	local function row(name: string, y: number): (Frame, TextLabel)
		local label = Ui.text({
			Text = name,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(214, y),
			Size = UDim2.fromOffset(62, Ui.TOUCH),
			Parent = card,
		})
		return Ui.new("Frame", {
			Position = UDim2.fromOffset(278, y),
			Size = UDim2.fromOffset(332, Ui.TOUCH),
			BackgroundTransparency = 1,
			Parent = card,
		}, {
			Ui.new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		}), label
	end
	local updaters: { () -> () } = {}
	local function wordButton(parent: Instance, text: string, order: number, onClick: () -> (), picked: () -> boolean, width: number?): TextButton
		local button = Ui.button(text, Ui.colors.cream, onClick, {
			Size = UDim2.fromOffset(width or 0, Ui.TOUCH),
			AutomaticSize = if width then Enum.AutomaticSize.None else Enum.AutomaticSize.X,
			TextSize = 15,
			LayoutOrder = order,
			Parent = parent,
		})
		if not width then
			Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = button })
			-- never narrower than a finger
			Ui.new("UISizeConstraint", { MinSize = Vector2.new(Ui.TOUCH + 8, Ui.TOUCH), Parent = button })
		end
		table.insert(updaters, function()
			button.BackgroundColor3 = if picked() then Ui.colors.yellow else Ui.colors.cream
		end)
		return button
	end
	local function swatch(parent: Instance, color: Color3, order: number, onClick: () -> (), picked: () -> boolean, price: () -> string): TextButton
		local stroke = Ui.stroke(2.5)
		local button = Ui.new("TextButton", {
			Text = "",
			Font = Ui.FONT,
			TextSize = 14,
			TextColor3 = Ui.colors.ink,
			Size = UDim2.fromOffset(Ui.TOUCH, Ui.TOUCH),
			BackgroundColor3 = color,
			AutoButtonColor = false,
			LayoutOrder = order,
			Parent = parent,
		}, { Ui.round(), stroke })
		button.Activated:Connect(onClick)
		table.insert(updaters, function()
			local on = picked()
			stroke.Thickness = if on then 5 else 2.5
			stroke.Color = if on then Ui.colors.coral else Ui.colors.ink
			button.Text = price()
		end)
		return button
	end

	-- kind
	local kinds = row("Pet", 58)
	for i, kind in PETS.ORDER do
		wordButton(kinds, PETS.KINDS[kind].name, i, function()
			if preview.kind ~= kind then
				preview.kind = kind
				preview.color = 1
				refresh()
			end
		end, function()
			return preview.kind == kind
		end, 104)
	end
	-- colour (the kind's three)
	local colours = row("Colour", 108)
	local colourButtons: { TextButton } = {}
	for i = 1, 3 do
		colourButtons[i] = swatch(colours, Color3.new(1, 1, 1), i, function()
			preview.color = i
			refresh()
		end, function()
			return preview.color == i
		end, function()
			return ""
		end)
	end
	table.insert(updaters, function()
		for i, button in colourButtons do
			button.BackgroundColor3 = Color3.fromHex(PETS.KINDS[preview.kind].colors[i])
		end
	end)

	-- gear: tapping something you own puts it on; something you haven't, tries it on first
	-- Stops trying something on: its place goes back to what the pet really wears.
	local function stopTrying()
		local tried = trying and Config.petGear(trying)
		trying = nil
		if tried and current then
			(preview :: any)[tried.slot] = (current :: any)[tried.slot]
		end
	end
	-- Asks the server to put something on or take it off; says how it went.
	local function ask(what: string, detail: string, done: string)
		if busy then
			return
		end
		busy = true
		local ok, why = Remotes.PetAction:InvokeServer(what, detail)
		busy = false
		message = if ok then done else (why or "Something went wrong. Please try again.")
	end

	-- gear: tapping something you own puts it on; something you haven't, tries it on first
	local function tapGear(gear: any)
		if not current then
			return
		end
		stopTrying() -- only one thing tried on at a time
		if table.find(owned(), gear.id) then
			if (current :: any)[gear.slot] ~= gear.id then
				ask("wear", gear.id, "Looking lovely!")
			end
		else
			trying = gear.id
			message = `{gear.name}: {gear.price} coins`
		end
		;(preview :: any)[gear.slot] = gear.id
		refresh()
	end
	local function takeOff(slot: string)
		if not current then
			return
		end
		local tried = trying and Config.petGear(trying)
		if tried and tried.slot == slot then
			trying = nil
		end
		;(preview :: any)[slot] = nil
		if (current :: any)[slot] then
			ask("off", slot, "Taken off! Pop it back on any time.")
		end
		refresh()
	end
	local function priceOf(gear: any): string
		return if table.find(owned(), gear.id) then "" else tostring(gear.price)
	end

	local collarRow, collarLabel = row("Collar", 158)
	local topRow, topLabel = row("Head", 208)
	-- fixed widths, so each row fits the card: "None" and four more (56 + 4 x 62, with gaps)
	wordButton(collarRow, "None", 0, function()
		takeOff("collar")
	end, function()
		return preview.collar == nil
	end, 56)
	wordButton(topRow, "None", 0, function()
		takeOff("top")
	end, function()
		return preview.top == nil
	end, 56)
	for i, gear in PETS.GEAR do
		if gear.slot == "collar" then
			swatch(collarRow, Color3.fromHex(gear.color), i, function()
				tapGear(gear)
			end, function()
				return preview.collar == gear.id
			end, function()
				return priceOf(gear)
			end)
		else
			wordButton(topRow, gear.short or gear.name, i, function()
				tapGear(gear)
			end, function()
				return preview.top == gear.id
			end, 62)
		end
	end
	-- before adopting, collars and hats wait
	local later = Ui.text({
		Text = "Adopt a pet, then you can buy it collars and things for its head!",
		TextSize = 16,
		TextColor3 = Ui.colors.teal,
		Position = UDim2.fromOffset(214, 162),
		Size = UDim2.fromOffset(396, 80),
		Parent = card,
	})

	local function lookChanged(): boolean
		return current ~= nil
			and (current.kind ~= preview.kind or current.color ~= preview.color or current.name ~= preview.name)
	end

	refresh = function()
		walletText.Text = tostring(coins())
		nameLabel.Text = PETS.NAMES[preview.name] or ""
		for _, thing in { collarRow, collarLabel, topRow, topLabel } :: { GuiObject } do
			thing.Visible = current ~= nil
		end
		later.Visible = current == nil
		for _, update in updaters do
			update()
		end

		-- the picture
		local key = `{preview.kind}/{preview.color}/{preview.collar}/{preview.top}`
		if key ~= shownKey then
			shownKey = key
			if shown then
				shown.model:Destroy()
			end
			shown = PetBuilder.build(preview)
			;(shown :: PetBuilder.Pet).model.Parent = view
		end

		-- the main button
		local stroke = action:FindFirstChildOfClass("UIStroke")
		local gear = trying and Config.petGear(trying)
		local cost = if not current then PETS.ADOPT_PRICE elseif gear then gear.price else 0
		local canAfford = coins() >= cost
		if not current then
			action.Text = `Adopt for {cost}`
		elseif gear then
			action.Text = `Buy for {cost}`
		elseif lookChanged() then
			action.Text = "Save changes"
		else
			action.Text = "All set!"
		end
		local ready = (not current or gear ~= nil or lookChanged()) and canAfford
		action.BackgroundColor3 = if ready then Ui.colors.yellow else Ui.colors.creamDeep
		action.TextColor3 = if ready then Ui.colors.ink else Ui.colors.grey
		if stroke then
			stroke.Color = if ready then Ui.colors.ink else Ui.colors.grey
		end
		if cost > 0 and not canAfford then
			note.Text = `You need {cost - coins()} more coins. Look around the square!`
		else
			note.Text = message
		end
	end

	action.Activated:Connect(function()
		if busy then
			return
		end
		local gear = trying and Config.petGear(trying)
		local ok, why
		busy = true
		if not current then
			ok, why = Remotes.PetAction:InvokeServer("adopt", preview.kind, preview.color, preview.name)
			if ok then
				message = `Welcome home, {PETS.NAMES[preview.name]}! Off you go together.`
			end
		elseif gear then
			ok, why = Remotes.PetAction:InvokeServer("buy", gear.id)
			if ok then
				trying = nil
				message = `The {gear.name} is yours! On it goes.`
			end
		elseif lookChanged() then
			ok, why = Remotes.PetAction:InvokeServer("change", preview.kind, preview.color, preview.name)
			if ok then
				message = "All changed!"
			end
		end
		busy = false
		if why then
			message = why
		end
		refresh()
	end)

	-- the server's word on your pet and coins keeps the screen right
	table.insert(connections, player:GetAttributeChangedSignal("Pet"):Connect(function()
		current = myPet()
		if current then
			-- keep any changes you're still trying, but take what's actually worn from the server
			local tried = trying and Config.petGear(trying)
			preview.collar = if tried and tried.slot == "collar" then tried.id else current.collar
			preview.top = if tried and tried.slot == "top" then tried.id else current.top
		end
		refresh()
	end))
	for _, attribute in { "Coins", "PetGear" } do
		table.insert(connections, player:GetAttributeChangedSignal(attribute):Connect(refresh))
	end
	refresh()

	Ui.controller(gui, card, action, close)
end

function PetShop.isOpen(): boolean
	return screen ~= nil
end

return PetShop
