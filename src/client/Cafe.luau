-- Biscuit's Cafe on this player's own screen (Config.CAFE; the server runs the shift and checks
-- everything in server/places/Cafe):
--   * a ribbon across the Cafe road's arch until you've Config.CAFE.SUN sunshine, which you
--     can't walk through (the server still refuses anyone without it)
--   * Biscuit's "Cafe shift" card: four pictures of what to do, and Start (or Join, or Stop)
--   * the visitors: each walks in from the way in, sits at their table with a bubble showing a
--     picture of what they'd like, eats once it's served, and walks off, leaving their dirty
--     plates on the table. They're drawn only on
--     screens near the Cafe, from the shift the server shares (Workspace.CafeShift), so the
--     server makes no models for them.
--   * while you're helping: a button at each station ("Pick up"), at each table that's waiting
--     ("Serve") or has dirty plates ("Clear"), and at the wash-up tub ("Wash up") while you've
--     plates; and what you're carrying, over your head. Everyone sees what every helper carries.
--   * a row of dots over the counter that fills up as orders are served, and the card at the
--     end of a shift
--   * while you're helping: an "End shift" button above the emote button, and Biscuit's and
--     Chef Pepper's own buttons step aside, so only the counter's buttons show there
-- Nobody has to read: every order is a picture, there's no timer, and the wrong food just makes
-- the bubble give a little shake.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Build = require(Shared.Build)
local Builder = require(Shared.CharacterBuilder)
local CafeFood = require(Shared.CafeFood)
local Config = require(Shared.Config)
local Looks = require(Shared.Looks)
local Animator = require(script.Parent.Animator)
local Controls = require(script.Parent.Controls)
local Hud = require(script.Parent.Hud)
local Ui = require(script.Parent.Ui)

local Remotes = Shared:WaitForChild("Remotes")
local player = Players.LocalPlayer

local K = Config.CAFE
local C = Build.C
local S = Config.STUDS
local LEAVE_SPEED = 12 -- how fast a visitor walks off (studs a second)
local SEAT_HEIGHT = 0.5 -- web units: a sitting visitor's feet, up on the chair
local LANE = 2.2 -- web units in front of a table's row, where visitors walk across
local APPROACH = 2.4 -- web units from a table's middle, beside its chair
local BUBBLE_HEIGHT = 2.6 -- web units over a table
local CARRY_HEIGHT = 4.4 -- studs over a helper's middle, for the food they carry
local FIT = 2.2 -- how far a picture's camera stands back, times the model's size
local LOOK = 0.5 -- seconds between looks at whether you're near enough to draw the visitors
local PROPS = { CanCollide = false, CanTouch = false, CanQuery = false, CastShadow = false }
local RESIDENT_TAG = "SunnyfolkResident" -- server/Residents tags each resident with this
local BEHIND_COUNTER = { biscuit = true, pepper = true } -- their buttons step aside while you help
local EMOTE_BUTTON = 56 -- the emote button's size (client/Emotes), so End shift sits just above it

local Cafe = {}

local screen: ScreenGui? = nil
local folder: Folder
local state: Instance

local function sunshine(): number
	local sun = player:GetAttribute("Sun")
	return if typeof(sun) == "number" then sun else 0
end

local function helping(): boolean
	return player:GetAttribute("CafeHelper") == true
end

-- A spot on the ground in the Cafe (web units from its middle).
local function ground(x: number, z: number): Vector3
	return Config.cafeAt(x, z).Position
end

---------------------------------------------------------------- pictures

-- A ViewportFrame showing `model`, all of it, looking from `from`. `back` is how far the camera
-- stands back, times the model's size (FIT unless it's given); less fills more of the picture.
local function picture(model: Model, from: Vector3, props: { [string]: any }, back: number?): ViewportFrame
	local view, camera = Ui.viewport(props)
	model.Parent = view
	local box, size = model:GetBoundingBox()
	local reach = math.max(size.X, size.Y, size.Z)
	camera.CFrame = CFrame.lookAt(box.Position + from.Unit * reach * (back or FIT), box.Position)
	return view
end

-- The little table on the card: a white top on a teal stem, with a mug of cocoa on it.
local function littleTable(): Model
	local model = Instance.new("Model")
	for _, p in {
		Build.cylinder(0.95 * S, 0.1 * S, CFrame.new(0, 0.95 * S, 0), C.white, PROPS),
		Build.cylinder(0.12 * S, 0.9 * S, CFrame.new(0, 0.45 * S, 0), C.tealDeep, PROPS),
		Build.cylinder(0.48 * S, 0.08 * S, CFrame.new(0, 0.04 * S, 0), C.tealDeep, PROPS),
	} do
		p.Parent = model
	end
	local cocoa = CafeFood.model("cocoa", 1.4)
	cocoa:PivotTo(CFrame.new(0, 1.0 * S, 0))
	cocoa.Parent = model
	return model
end

-- The wash-up station on the card, as it looks in the Cafe: the blue stand, the tub of bubbly
-- water with its tap, and a little dirty plate standing in the water, facing you.
local function tubWithPlate(): Model
	local model = Instance.new("Model")
	for _, p in {
		Build.block(Vector3.new(1.4, 1.05, 1.1) * S, CFrame.new(0, 0.52 * S, 0), C.skyBlue, PROPS),
		Build.block(Vector3.new(1.5, 0.12, 1.2) * S, CFrame.new(0, 1.1 * S, 0), C.wood, PROPS),
	} do
		p.Parent = model
	end
	local tub = CafeFood.tub()
	tub:PivotTo(CFrame.new(0, 1.16 * S, 0))
	tub.Parent = model
	local plate = CafeFood.model("dirty", 0.7)
	plate:PivotTo(CFrame.new(0.12 * S, 1.38 * S, -0.05 * S) * CFrame.Angles(1.15, 0, 0))
	plate.Parent = model
	model.WorldPivot = CFrame.identity
	return model
end

-- All four dishes in a row, like the counter.
local function allDishes(): Model
	local model = Instance.new("Model")
	for i, id in K.STATIONS do
		local dish = CafeFood.model(id)
		dish:PivotTo(CFrame.new((i - 2.5) * 0.8 * S, 0, 0))
		dish.Parent = model
	end
	return model
end

---------------------------------------------------------------- Biscuit's card

local function closeScreen(gui: ScreenGui)
	if gui.Parent then
		gui:Destroy()
		screen = nil
		Controls.set(true, "cafe")
	end
end

local function ask(what: string)
	local ok, result = Remotes.CafeAction:InvokeServer(what)
	if not ok then
		Hud.announce("Oh!", if typeof(result) == "string" then result else "Something went wrong.")
	elseif result == "started" then
		Hud.announce("Shift started!", "Look for visitors at the tables.")
	elseif result == "joined" then
		Hud.announce("You're helping too!", "Look for visitors at the tables.")
	end
end

local function openCard()
	if screen or Ui.openScreens > 0 then
		return
	end
	Controls.set(false, "cafe")
	local gui = Ui.screen("Cafe", 17)
	screen = gui
	local card = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(560, 260),
		BackgroundColor3 = Ui.colors.paper,
		Parent = gui,
	}, { Ui.corner(22), Ui.stroke(3) })
	Ui.fitToScreen(card, 560, 260)
	local function close()
		closeScreen(gui)
	end
	local mine = helping()
	local running = state:GetAttribute("Active") == true
	Ui.text({
		Text = if mine then "You're helping Biscuit!" else "Help Biscuit at the Cafe?",
		TextSize = 22,
		TextColor3 = Ui.colors.coral,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.fromOffset(400, Ui.TOUCH),
		Parent = card,
	})
	Ui.button("Not now", Ui.colors.cream, close, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(100, Ui.TOUCH),
		TextSize = 18,
		Parent = card,
	})

	-- what to do, in four pictures
	local steps = {
		{ words = "See what they'd like", model = CafeFood.model("cocoa"), from = Vector3.new(0.3, 0.5, 1), bubble = true },
		{ words = "Pick it up", model = allDishes(), from = Vector3.new(0, 0.6, 1), back = 1.15 },
		{ words = "Take it to the table", model = littleTable(), from = Vector3.new(0.3, 0.6, 1) },
		{ words = "Wash the plates", model = tubWithPlate(), from = Vector3.new(0.45, 0.6, 1), back = 1.7 },
	}
	for i, step in steps do
		local x = 16 + (i - 1) * 135
		local tile = Ui.new("Frame", {
			Position = UDim2.fromOffset(x, 58),
			Size = UDim2.fromOffset(123, 128),
			BackgroundColor3 = Ui.colors.cream,
			Parent = card,
		}, { Ui.corner(16), Ui.stroke(2.5) })
		local holder = Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 6),
			Size = UDim2.fromOffset(if step.bubble then 76 else 113, 76),
			BackgroundColor3 = Ui.colors.paper,
			BackgroundTransparency = if step.bubble then 0 else 1,
			Parent = tile,
		}, if step.bubble then { Ui.round(), Ui.stroke(3) } else {})
		picture(step.model, step.from, { Size = UDim2.fromScale(1, 1), Parent = holder }, step.back)
		Ui.text({
			Text = step.words,
			TextSize = 14,
			Position = UDim2.fromOffset(6, 84),
			Size = UDim2.new(1, -12, 0, 40),
			Parent = tile,
		})
		if i < #steps then
			Ui.text({ Text = "→", TextSize = 16, Position = UDim2.fromOffset(x + 123, 108), Size = UDim2.fromOffset(12, 24), Parent = card })
		end
	end

	-- the main button, and what each order pays
	local first: GuiObject
	if mine then
		first = Ui.button("Keep helping", Ui.colors.yellow, close, {
			Position = UDim2.fromOffset(16, 200),
			Size = UDim2.fromOffset(200, Ui.TOUCH),
			TextSize = 20,
			Parent = card,
		})
		Ui.button("Stop for now", Ui.colors.cream, function()
			close()
			Remotes.CafeAction:InvokeServer("stop")
			Hud.announce("Thank you for helping!", "Ask Biscuit if you'd like another shift.")
		end, {
			Position = UDim2.fromOffset(228, 200),
			Size = UDim2.fromOffset(160, Ui.TOUCH),
			TextSize = 18,
			Parent = card,
		})
	else
		first = Ui.button(if running then "Join the shift" else "Start a shift", Ui.colors.yellow, function()
			close()
			ask("start")
		end, {
			Position = UDim2.fromOffset(16, 200),
			Size = UDim2.fromOffset(200, Ui.TOUCH),
			TextSize = 20,
			Parent = card,
		})
	end
	local pay = Ui.new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 208),
		Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Parent = card,
	}, {
		Ui.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	Ui.coin(22, { LayoutOrder = 1, Parent = pay })
	Ui.text({
		Text = `+{K.ORDER_COINS} each order`,
		TextSize = 16,
		TextWrapped = false,
		Size = UDim2.fromOffset(0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2,
		Parent = pay,
	})
	Ui.controller(gui, card, first, close)
end

-- The card at the end of a shift: what you earned, and another shift if you'd like.
local function shiftDone(coins: number, served: number)
	Hud.inTurn(function()
		if screen or Ui.openScreens > 0 then
			Hud.announce("Great shift!", if coins > 0 then `+{coins} coins` else "Thank you for helping!")
			return
		end
		Controls.set(false, "cafe")
		local gui = Ui.screen("CafeDone", 17)
		screen = gui
		local card = Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(420, 220),
			BackgroundColor3 = Ui.colors.paper,
			Parent = gui,
		}, { Ui.corner(22), Ui.stroke(3) })
		Ui.fitToScreen(card, 420, 220)
		local function close()
			closeScreen(gui)
		end
		Ui.text({
			Text = "Great shift!",
			TextSize = 26,
			TextColor3 = Ui.colors.coral,
			Position = UDim2.fromOffset(16, 10),
			Size = UDim2.new(1, -32, 0, 36),
			Parent = card,
		})
		-- a full row of served orders
		local dots = Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 52),
			Size = UDim2.fromOffset(0, 24),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Parent = card,
		}, {
			Ui.new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		for i = 1, served do
			Ui.new("Frame", { Size = UDim2.fromOffset(22, 22), BackgroundColor3 = Ui.colors.yellow, LayoutOrder = i, Parent = dots },
				{ Ui.round(), Ui.stroke(2) })
		end
		local row = Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 88),
			Size = UDim2.fromOffset(0, 50),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Parent = card,
		}, {
			Ui.new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		if coins > 0 then
			Ui.coin(34, { LayoutOrder = 1, Parent = row })
			Ui.text({ Text = `+{coins} coins`, TextSize = 26, TextWrapped = false, Size = UDim2.fromOffset(0, 40),
				AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2, Parent = row })
		else
			-- (after Config.CAFE.COINS_PER_HOUR in an hour)
			Ui.text({ Text = "Biscuit says thank you! Coins for shifts come back a bit later.", TextSize = 16,
				Size = UDim2.fromOffset(380, 50), LayoutOrder = 1, Parent = row })
		end
		local first = Ui.button("Another shift", Ui.colors.yellow, function()
			close()
			ask("start")
		end, {
			Position = UDim2.fromOffset(16, 160),
			Size = UDim2.fromOffset(200, Ui.TOUCH),
			TextSize = 20,
			Parent = card,
		})
		Ui.button("Done", Ui.colors.cream, close, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -16, 0, 160),
			Size = UDim2.fromOffset(160, Ui.TOUCH),
			TextSize = 20,
			Parent = card,
		})
		Ui.controller(gui, card, first, close)
	end)
end

---------------------------------------------------------------- visitors

type Walk = { model: Model, root: BasePart, points: { Vector3 }, speed: number, travelled: number, length: number, finish: (() -> ())? }
type Seat = {
	i: number,
	visitor: number?,
	food: string?,
	state: string?,
	model: Model?,
	walk: Walk?,
	plate: Model?,
	plateKind: string?, -- what's on the table: their food while they eat, then "dirty"
	button: ProximityPrompt,
	bubble: BillboardGui,
	circle: Frame,
	view: ViewportFrame?,
	spot: BasePart,
}

local walkers: { Walk } = {}
local seats: { Seat } = {}
local near = false

-- Where a visitor at table `i` walks: in from the way in, down the middle, across in front of
-- the table's row, and round to its chair.
local function pathIn(i: number): { Vector3 }
	local tx, tz = K.TABLES[i][1], K.TABLES[i][2]
	local side = if tx > 0 then 1 else -1
	local ax, lane = tx + side * APPROACH, tz - LANE
	return { ground(0, K.ENTRANCE), ground(0, lane), ground(ax, lane), ground(ax, tz), ground(tx + side * K.CHAIR, tz) }
end

-- Sitting on table `i`'s chair (feet up on the seat), facing the table.
local function seatFeet(i: number): CFrame
	local tx, tz = K.TABLES[i][1], K.TABLES[i][2]
	local side = if tx > 0 then 1 else -1
	return Config.cafeAt(tx + side * K.CHAIR, tz, -side * math.pi / 2) * CFrame.Angles(0, math.pi, 0) * CFrame.new(0, SEAT_HEIGHT * S, 0)
end

-- How a visitor looks, picked from their number (the same on every screen).
local function visitorLook(seed: number)
	local random = Random.new(seed)
	local species = Config.START_ANIMALS[random:NextInteger(1, #Config.START_ANIMALS)]
	local coats = Looks.coats(species)
	local coat = if #coats > 0 then coats[random:NextInteger(1, #coats)].id else nil
	local hats = Looks.shopHats()
	local hat = if #hats > 0 and random:NextNumber() < 0.4 then hats[random:NextInteger(1, #hats)].id else nil
	return Looks.playerLook({ species = species, coat = coat, scarf = random:NextInteger(1, #Looks.scarves()) }, hat, {})
end

local function placeAt(model: Model, feet: CFrame)
	local root = model.PrimaryPart
	if root then
		root.CFrame = feet * CFrame.new(0, Builder.ROOT_HEIGHT, 0)
	end
end

local function walk(model: Model, points: { Vector3 }, speed: number, finish: (() -> ())?): Walk?
	local root = model.PrimaryPart
	if not root or #points < 2 then
		if finish then
			finish()
		end
		return nil
	end
	local length = 0
	for k = 2, #points do
		length += (points[k] - points[k - 1]).Magnitude
	end
	local w: Walk = { model = model, root = root, points = points, speed = speed, travelled = 0, length = length, finish = finish }
	model:SetAttribute("Pace", speed / Animator.WALK_SPEED)
	table.insert(walkers, w)
	return w
end

local function stopWalk(w: Walk?)
	local index = w and table.find(walkers, w)
	if index then
		table.remove(walkers, index)
	end
end

local function sitDown(seat: Seat)
	local model = seat.model
	if not model then
		return
	end
	seat.walk = nil
	model:SetAttribute("Pace", 0)
	placeAt(model, seatFeet(seat.i))
	-- (the Animator finds a new animal a moment after it appears)
	task.delay(0.2, function()
		if seat.model == model then
			Animator.emote(model, "sit")
		end
	end)
end

-- The visitor (if any) at this seat gets up and walks off.
local function sendAway(seat: Seat)
	local model = seat.model
	seat.model = nil
	if not model then
		return
	end
	local walking = seat.walk ~= nil
	stopWalk(seat.walk)
	seat.walk = nil
	local root = model.PrimaryPart
	if not root then
		model:Destroy()
		return
	end
	local from = Vector3.new(root.Position.X, ground(0, 0).Y, root.Position.Z)
	local points = { from }
	if not walking then
		-- the way they came, backwards
		local path = pathIn(seat.i)
		for k = #path - 1, 2, -1 do
			table.insert(points, path[k])
		end
	end
	table.insert(points, ground(0, K.ENTRANCE))
	walk(model, points, LEAVE_SPEED, function()
		model:Destroy()
	end)
end

local function arrive(seat: Seat, walkIn: boolean)
	if not seat.visitor then
		return
	end
	local model = Builder.build(visitorLook(seat.visitor), { name = "Visitor", cframe = CFrame.new(ground(0, K.ENTRANCE)) })
	local root = model.PrimaryPart :: BasePart
	-- moved by this screen, not by physics, and nothing to bump into
	root.Anchored = true
	root.CanCollide = false
	model.Parent = folder
	seat.model = model
	if walkIn then
		local path = pathIn(seat.i)
		local length = 0
		for k = 2, #path do
			length += (path[k] - path[k - 1]).Magnitude
		end
		local speed = math.max(8, length / math.max(1, K.ARRIVE_SECONDS - 0.5))
		seat.walk = walk(model, path, speed, function()
			sitDown(seat)
		end)
	else
		sitDown(seat)
	end
end

-- Shows a seat as the shift says: the bubble while they wait, their food on the table while
-- they eat, then their dirty plates until a helper clears them.
local function refresh(seat: Seat)
	local waiting = seat.state == "wait"
	local dirty = seat.state == "dirty"
	seat.bubble.Enabled = waiting
	-- (Clear only with empty paws: the server won't let anyone drop what they're carrying)
	local empty = player:GetAttribute("CafeCarry") == nil
	seat.button.Enabled = helping() and (waiting or (dirty and empty))
	seat.button.ActionText = if dirty then "Clear" else "Serve"
	seat.button.ObjectText = if dirty then "Dirty plates" elseif seat.food then K.MENU[seat.food].name else ""
	local kind = if seat.state == "eat" then seat.food elseif dirty then "dirty" else nil
	if kind ~= seat.plateKind or (kind ~= nil and seat.plate == nil) then
		if seat.plate then
			seat.plate:Destroy()
			seat.plate = nil
		end
		seat.plateKind = kind
		if kind and near then
			local tx, tz = K.TABLES[seat.i][1], K.TABLES[seat.i][2]
			local side = if tx > 0 then 1 else -1
			local plate = CafeFood.model(kind)
			plate:PivotTo(Config.cafeAt(tx + side * 0.4, tz) * CFrame.new(0, 1.0 * S, 0))
			plate.Parent = folder
			seat.plate = plate
			if kind ~= "dirty" and seat.model then
				Animator.wave(seat.model)
			end
		end
	end
end

-- The order at table `i` changed (or the shift did).
local function update(i: number)
	local seat = seats[i]
	local raw = state:GetAttribute(`Table{i}`)
	local food, visitor, now = nil, nil, nil
	if typeof(raw) == "string" then
		local parts = string.split(raw, "|")
		food, visitor, now = parts[1], tonumber(parts[2]), parts[3]
		if not K.MENU[food] then
			food, visitor, now = nil, nil, nil
		end
	end
	if visitor ~= seat.visitor then
		sendAway(seat)
		seat.visitor = visitor
		if visitor and near and now ~= "dirty" then
			arrive(seat, now == "come")
		end
	elseif now == "dirty" and seat.model then
		-- they've eaten and gone, leaving their plates
		sendAway(seat)
	end
	if food ~= seat.food and food then
		-- the picture in the bubble
		if seat.view then
			seat.view:Destroy()
		end
		seat.view = picture(CafeFood.model(food), Vector3.new(0.3, 0.5, 1), { Size = UDim2.fromScale(1, 1), Parent = seat.circle })
	end
	seat.food = food
	seat.state = now
	refresh(seat)
end

-- Something floating up from a table for a moment: "+2" with a coin, or a word.
local function float(seat: Seat, text: string, coin: boolean)
	local gui = Ui.new("BillboardGui", {
		Size = UDim2.fromOffset(260, 64),
		StudsOffsetWorldSpace = Vector3.new(0, 2 * S, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 120,
		Adornee = seat.spot,
		Parent = seat.spot,
	})
	local row = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, 54),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Ui.colors.paper,
		Parent = gui,
	}, {
		Ui.round(),
		Ui.stroke(3),
		Ui.padding(8),
		Ui.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	if coin then
		Ui.coin(36, { LayoutOrder = 1, Parent = row })
	end
	Ui.text({ Text = text, TextSize = 30, TextWrapped = false, Size = UDim2.fromOffset(0, 38), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2, Parent = row })
	TweenService:Create(gui, TweenInfo.new(1.6), { StudsOffsetWorldSpace = Vector3.new(0, 4 * S, 0) }):Play()
	task.delay(1.6, function()
		gui:Destroy()
	end)
end

-- The bubble gives a little shake: not that one!
local function shake(seat: Seat)
	local circle = seat.circle
	local info = TweenInfo.new(0.07, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 3, true)
	circle.Rotation = -10
	local tween = TweenService:Create(circle, info, { Rotation = 10 })
	tween:Play()
	tween.Completed:Once(function()
		circle.Rotation = 0
	end)
end

---------------------------------------------------------------- the food helpers carry

local function showCarry(who: Player)
	local character = who.Character
	local old = character and character:FindFirstChild("CafeCarry")
	if old then
		old:Destroy()
	end
	local food = who:GetAttribute("CafeCarry")
	local root = character and character.PrimaryPart
	if not (character and root and typeof(food) == "string" and (K.MENU[food] or food == "dirty")) then
		return
	end
	-- welded over their head, so it moves with them for free
	local dish = CafeFood.model(food, 1.5)
	dish.Name = "CafeCarry"
	dish:PivotTo(root.CFrame * CFrame.new(0, CARRY_HEIGHT, 0))
	for _, part in dish:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = part
		end
	end
	dish.Parent = character
end

local function watchCarry(who: Player)
	who:GetAttributeChangedSignal("CafeCarry"):Connect(function()
		showCarry(who)
	end)
	who.CharacterAdded:Connect(function(character)
		character:WaitForChild("HumanoidRootPart", 10)
		showCarry(who)
	end)
	showCarry(who)
end

---------------------------------------------------------------- starting

-- The ribbon across the Cafe road's arch, until you've enough sunshine (like the Garden's).
local function gate()
	local spot = CFrame.lookAt(Config.polar(K.angle, Config.EDGE_R - 0.5), Vector3.zero)
	local barrier = Ui.new("Part", {
		Name = "CafeRibbon",
		Anchored = true,
		CanCollide = true,
		CanQuery = false,
		CanTouch = false,
		Transparency = 1,
		Size = Vector3.new(K.GATE_WIDTH * S, 40, 1),
		CFrame = spot + Vector3.new(0, 20, 0),
	})
	local ribbon = Ui.new("Part", {
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Material = Enum.Material.SmoothPlastic,
		Color = C.teal,
		Size = Vector3.new(4.4 * S, 0.12 * S, 0.06 * S),
		CFrame = spot + Vector3.new(0, 1.2 * S, 0),
		Parent = barrier,
	})
	local sign = Ui.new("BillboardGui", {
		Size = UDim2.fromOffset(230, 64),
		StudsOffsetWorldSpace = Vector3.new(0, 2.2 * S, 0),
		MaxDistance = 60,
		LightInfluence = 0,
		Adornee = ribbon,
		Parent = barrier,
	})
	local words = Ui.text({
		Text = `Biscuit's Cafe opens when you have {K.SUN} sunshine ☀️`,
		TextSize = 17,
		BackgroundTransparency = 0,
		BackgroundColor3 = Ui.colors.paper,
		Size = UDim2.fromScale(1, 1),
		Parent = sign,
	})
	Ui.corner(14).Parent = words
	Ui.stroke(2.5).Parent = words
	local function check()
		barrier.Parent = if sunshine() >= K.SUN then nil else Workspace
	end
	player:GetAttributeChangedSignal("Sun"):Connect(check)
	check()
end

local function button(name: string, at: CFrame, action: string, distance: number): (BasePart, ProximityPrompt)
	local spot = Ui.new("Part", {
		Name = name,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Transparency = 1,
		Size = Vector3.new(2, 2, 2),
		CFrame = at + Vector3.new(0, 2, 0),
		Parent = folder,
	})
	local prompt = Ui.new("ProximityPrompt", {
		Name = name,
		ActionText = action,
		KeyboardKeyCode = Enum.KeyCode.E,
		GamepadKeyCode = Enum.KeyCode.ButtonX,
		HoldDuration = 0,
		MaxActivationDistance = distance,
		RequiresLineOfSight = false,
		Enabled = false,
		Style = Enum.ProximityPromptStyle.Custom, -- shown at the bottom of the screen (client/Prompts)
		Parent = spot,
	})
	return spot, prompt
end

-- A round bubble floating over `spot` (a table, or the wash-up tub), for a picture of food or
-- plates. Hidden until it's needed.
local function bubbleOver(spot: BasePart): (BillboardGui, Frame)
	local bubble = Ui.new("BillboardGui", {
		Size = UDim2.fromOffset(84, 84),
		StudsOffsetWorldSpace = Vector3.new(0, BUBBLE_HEIGHT * S - 2, 0), -- (the spot is 2 up)
		AlwaysOnTop = true, -- so the umbrellas never hide it
		LightInfluence = 0,
		MaxDistance = 140,
		Enabled = false,
		ResetOnSpawn = false,
		Adornee = spot,
		-- (in PlayerGui: a picture of a 3D model doesn't draw in a sign kept out in the world)
		Parent = player:WaitForChild("PlayerGui"),
	})
	local circle = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(76, 76),
		BackgroundColor3 = Ui.colors.paper,
		Parent = bubble,
	}, { Ui.round(), Ui.stroke(3) })
	return bubble, circle
end

function Cafe.start()
	folder = Instance.new("Folder")
	folder.Name = "MyCafe"
	folder.Parent = Workspace
	state = Workspace:WaitForChild("CafeShift")
	gate()

	-- the stations' buttons (only while you're helping)
	local stationButtons: { ProximityPrompt } = {}
	for i, id in K.STATIONS do
		local _, prompt = button("CafeStation", Config.cafeStation(i), "Pick up", K.STATION_BUTTON)
		prompt.ObjectText = K.MENU[id].name
		prompt:SetAttribute("Station", i)
		stationButtons[i] = prompt
	end
	-- the wash-up tub's button, and a bubble of dirty plates over it, so you can see where they
	-- go (both only while you're carrying dirty plates)
	local washSpot, washButton = button("CafeWash", Config.cafeWash(), "Wash up", K.STATION_BUTTON)
	washButton.ObjectText = "Dirty plates"
	local washBubble, washCircle = bubbleOver(washSpot)
	picture(CafeFood.model("dirty"), Vector3.new(0.2, 0.8, 1), { Size = UDim2.fromScale(1, 1), Parent = washCircle }, 1.6)

	-- End shift, just above the emote button (client/Emotes), while you're helping
	local endButton: GuiObject? = nil
	local function showEndButton(mine: boolean)
		local hud = Hud.gui()
		if mine and not endButton and hud then
			-- (on a TV it's sized up by hand: a second UIScale would undo the button's press squash)
			local k = if Ui.CONSOLE then Config.UI.CONSOLE_SCALE else 1
			local gap = EMOTE_BUTTON / 2 * k + 10
			local ending = false
			local made = Ui.button("End shift", Ui.colors.cream, function()
				if ending then
					return
				end
				ending = true
				pcall(function()
					Remotes.CafeAction:InvokeServer("stop")
				end)
				ending = false
				Hud.announce("Thank you for helping!", "Ask Biscuit if you'd like another shift.")
			end, {
				AnchorPoint = Vector2.new(1, 1),
				Position = if Ui.CONSOLE
					then UDim2.new(1 - Config.UI.TV_SAFE, 0, 0.55, -gap)
					else UDim2.new(1, -16, 0.55, -gap),
				Size = UDim2.fromOffset(120 * k, Ui.TOUCH * k),
				TextSize = math.round(18 * k),
				Parent = hud,
			})
			endButton = made
		end
		if endButton then
			endButton.Visible = mine
		end
	end

	-- Biscuit's and Pepper's buttons step aside while you're helping (yours to put back when
	-- you're not); they can stream in later, so look again when they do.
	local function counterStaff()
		local mine = helping()
		for _, model in CollectionService:GetTagged(RESIDENT_TAG) do
			if BEHIND_COUNTER[model:GetAttribute("ResidentId") :: any] then
				for _, thing in model:GetDescendants() do
					if thing:IsA("ProximityPrompt") then
						thing.Enabled = not mine
					end
				end
			end
		end
	end
	CollectionService:GetInstanceAddedSignal(RESIDENT_TAG):Connect(function()
		task.defer(counterStaff)
	end)
	-- (and if one of their buttons streams in later still, it steps aside as it shows)
	ProximityPromptService.PromptShown:Connect(function(prompt)
		local model = prompt:FindFirstAncestorOfClass("Model")
		if helping() and model and BEHIND_COUNTER[model:GetAttribute("ResidentId") :: any] then
			prompt.Enabled = false
		end
	end)

	-- each table: its button, and the bubble over it showing what the visitor would like
	for i = 1, #K.TABLES do
		local spot, prompt = button("CafeTable", Config.cafeTable(i), "Serve", K.TABLE_BUTTON)
		prompt:SetAttribute("Table", i)
		local bubble, circle = bubbleOver(spot)
		seats[i] = { i = i, button = prompt, bubble = bubble, circle = circle, spot = spot }
	end

	-- the dots over the counter, one for each order in the shift
	local boardSpot = Ui.new("Part", {
		Name = "CafeBoard",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Transparency = 1,
		Size = Vector3.new(1, 1, 1),
		CFrame = Config.cafeAt(0, K.COUNTER_Z) + Vector3.new(0, 3.6 * S, 0),
		Parent = folder,
	})
	local board = Ui.new("BillboardGui", {
		Size = UDim2.fromOffset(K.ORDERS * 28 + 16, 40),
		LightInfluence = 0,
		MaxDistance = 140,
		Enabled = false,
		Adornee = boardSpot,
		Parent = boardSpot,
	})
	local row = Ui.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Ui.colors.paper,
		Parent = board,
	}, {
		Ui.round(),
		Ui.stroke(2.5),
		Ui.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local dots: { Frame } = {}
	for i = 1, K.ORDERS do
		dots[i] = Ui.new("Frame", { Size = UDim2.fromOffset(22, 22), LayoutOrder = i, Parent = row }, { Ui.round(), Ui.stroke(2) })
	end
	local function showBoard()
		local served = state:GetAttribute("Served")
		served = if typeof(served) == "number" then served else 0
		board.Enabled = state:GetAttribute("Active") == true
		for i, dot in dots do
			dot.BackgroundColor3 = if i <= served then Ui.colors.yellow else Ui.colors.cream
		end
	end

	local function showButtons()
		local mine = helping()
		local plates = player:GetAttribute("CafeCarry") == "dirty"
		for _, prompt in stationButtons do
			prompt.Enabled = mine and not plates
		end
		washButton.Enabled = mine and plates
		washBubble.Enabled = mine and plates
		for _, seat in seats do
			refresh(seat)
		end
		showEndButton(mine)
		counterStaff()
	end

	state.AttributeChanged:Connect(function(name)
		local i = tonumber(string.match(name, "^Table(%d+)$"))
		if i and seats[i] then
			update(i)
		else
			showBoard()
		end
	end)
	player:GetAttributeChangedSignal("CafeHelper"):Connect(showButtons)
	player:GetAttributeChangedSignal("CafeCarry"):Connect(showButtons)
	for i in seats do
		update(i)
	end
	showBoard()
	showButtons()

	-- what everyone's carrying
	for _, who in Players:GetPlayers() do
		task.spawn(watchCarry, who)
	end
	Players.PlayerAdded:Connect(watchCarry)

	-- Visitors are only drawn near the Cafe: look now and then whether you're near.
	task.spawn(function()
		local middle = Config.cafeFrame().Position
		while true do
			local camera = Workspace.CurrentCamera
			local nowNear = camera ~= nil and (camera.CFrame.Position - middle).Magnitude < K.DRAW_DISTANCE
			if nowNear ~= near then
				near = nowNear
				for _, seat in seats do
					if near then
						if seat.visitor and not seat.model and seat.state ~= "dirty" then
							arrive(seat, false)
						end
						refresh(seat)
					else
						stopWalk(seat.walk)
						seat.walk = nil
						if seat.model then
							seat.model:Destroy()
							seat.model = nil
						end
						if seat.plate then
							seat.plate:Destroy()
							seat.plate = nil
						end
					end
				end
				if not near then
					for _, w in walkers do
						w.model:Destroy()
					end
					table.clear(walkers)
				end
			end
			task.wait(LOOK)
		end
	end)

	-- Walking visitors: along their path, a little each frame (only while there are any).
	RunService.Heartbeat:Connect(function(dt)
		for k = #walkers, 1, -1 do
			local w = walkers[k]
			w.travelled += w.speed * dt
			local left = w.travelled
			local at, ahead = w.points[#w.points], w.points[#w.points] - w.points[#w.points - 1]
			for p = 2, #w.points do
				local a, b = w.points[p - 1], w.points[p]
				local piece = (b - a).Magnitude
				if left <= piece and piece > 0 then
					at, ahead = a + (b - a) * (left / piece), b - a
					break
				end
				left -= piece
			end
			local flat = Vector3.new(ahead.X, 0, ahead.Z)
			local feet = if flat.Magnitude > 0.01 then CFrame.lookAt(at, at + flat) else CFrame.new(at)
			w.root.CFrame = feet * CFrame.new(0, Builder.ROOT_HEIGHT, 0)
			if w.travelled >= w.length then
				table.remove(walkers, k)
				w.model:SetAttribute("Pace", 0)
				if w.finish then
					w.finish()
				end
			end
		end
	end)

	-- the buttons
	local busy = false -- waiting for the server, so a quick second tap doesn't ask twice
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name == "CafeShift" then
			openCard()
			return
		end
		if busy or not (prompt.Name == "CafeStation" or prompt.Name == "CafeTable" or prompt.Name == "CafeWash") then
			return
		end
		busy = true
		local function oh(why: any)
			Hud.announce("Oh!", if typeof(why) == "string" then why else "Something went wrong.")
		end
		-- (in pcall, so a hiccup on the way to the server never leaves the buttons stuck)
		pcall(function()
			if prompt.Name == "CafeStation" then
				local ok, why = Remotes.CafeAction:InvokeServer("pick", prompt:GetAttribute("Station"))
				if not ok then
					oh(why)
				end
			elseif prompt.Name == "CafeWash" then
				local ok, why = Remotes.CafeAction:InvokeServer("wash")
				if not ok then
					oh(why)
				end
			else
				local i = prompt:GetAttribute("Table")
				local seat = typeof(i) == "number" and seats[i]
				if not seat then
					return
				end
				local carry = player:GetAttribute("CafeCarry")
				if seat.state == "dirty" then
					local ok, why = Remotes.CafeAction:InvokeServer("clear", i)
					if not ok then
						oh(why)
					end
				elseif typeof(carry) ~= "string" then
					-- nothing in your paws: show them where to go
					shake(seat)
					float(seat, "From the counter!", false)
				elseif carry == "dirty" then
					shake(seat)
					float(seat, "Wash up first!", false)
				else
					local ok, why = Remotes.CafeAction:InvokeServer("serve", i)
					if not ok and why == "wrong" then
						shake(seat)
						float(seat, "Not that one!", false)
					elseif not ok then
						oh(why)
					end
				end
			end
		end)
		busy = false
	end)

	-- news from the server about the shift
	local cappedSaid = false
	Remotes.CafeNews.OnClientEvent:Connect(function(what, a, b)
		if what == "served" and typeof(a) == "number" and seats[a] then
			if typeof(b) == "number" and b > 0 then
				float(seats[a], `+{b}`, true)
			elseif not cappedSaid then
				cappedSaid = true
				Hud.announce("Biscuit says thank you!", "Coins for shifts come back a bit later.")
			end
		elseif what == "joined" and typeof(a) == "string" then
			Hud.announce(`{a} is helping too!`)
		elseif what == "done" then
			cappedSaid = false
			shiftDone(if typeof(a) == "number" then a else 0, if typeof(b) == "number" then b else K.ORDERS)
		elseif what == "left" then
			cappedSaid = false
			Hud.announce("You've left the shift", "Ask Biscuit if you'd like another.")
		end
	end)
end

function Cafe.isOpen(): boolean
	return screen ~= nil
end

return Cafe
