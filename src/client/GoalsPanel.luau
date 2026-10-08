-- The goals on the player's screen (the lists are in shared/Goals; the server keeps score):
--   * a card under the Goals button with one "now" thing (the goal you're on and a hint) and,
--     when something's planted, one gentle "later" line ("Your sunflowers are growing")
--   * a yellow arrow at your feet and a pin over the place to go, pointing the way (they only
--     point: they never move you). The pin goes once you've arrived, and for the Garden goals
--     it points at the bed that needs you, just above that bed's own sign.
--   * "Well done!" when you finish one (Hud.announce: it waits until any open screen has closed
--     and the last message has gone, so it's always seen)
--   * the Goals screen (from the HUD's Goals button): the First Story, ticked off, and once
--     that's done, the Adventures as big picture cards to choose from, and your sunshine. It
--     opens by itself when the First Story is done.
-- Everything here only shows what the server says. The one thing it asks for is which
-- Adventure to do next (ChooseAdventure); the server checks that.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Build = require(Shared.Build)
local Builder = require(Shared.CharacterBuilder)
local CafeFood = require(Shared.CafeFood)
local Config = require(Shared.Config)
local GoalList = require(Shared.Goals)
local Houses = require(Shared.Houses)
local Looks = require(Shared.Looks)
local PetBuilder = require(Shared.PetBuilder)
local Controls = require(script.Parent.Controls)
local Garden = require(script.Parent.Garden)
local Hud = require(script.Parent.Hud)
local Ui = require(script.Parent.Ui)

local Remotes = Shared:WaitForChild("Remotes")
local player = Players.LocalPlayer

local STORY = GoalList.STORY
local S = Config.STUDS
local RESIDENT_TAG = "SunnyfolkResident" -- server/Residents tags each resident with this
local FIND_SECONDS = 0.25 -- how often to look again for where to point
local NEAR = 10 -- studs: closer than this, the arrow at your feet goes (the pin's enough)
-- How high (studs) the pin floats over what it points at: just above a coin, over a
-- resident's name tag, level with a garden bed's sign, and in between for doors, plots and
-- places.
local PIN_HEIGHT = { talk = 9, cafe = 9, plant = Config.GARDEN.SIGN_HEIGHT, harvest = Config.GARDEN.SIGN_HEIGHT }
local PIN_HEIGHT_OTHER = 6
-- Over a garden bed, the pin is lifted (in pixels, so at any distance) to sit just above the
-- bed's sign (client/Garden): half the sign, a gap and half the pin, as a part of the pin's
-- height.
local PIN_SIZE = Vector2.new(48, 62)
local OVER_SIGN = (Config.GARDEN.SIGN_SIZE.Y / 2 + Config.UI.GOAL_PIN_GAP + PIN_SIZE.Y / 2) / PIN_SIZE.Y
local PIN_LIFT = { plant = OVER_SIGN, harvest = OVER_SIGN }
local PIN_BOB = 0.08 -- how far it bobs up and down, as a part of its height

local GoalsPanel = {}

local screen: ScreenGui? = nil

-- The goal you're on, or nil (choosing an Adventure, or all done).
local function currentGoal(): GoalList.Goal?
	local id = player:GetAttribute("Goal")
	return if typeof(id) == "string" then GoalList.BY_ID[id] else nil
end

local function goalsDone(): { string }
	return GoalList.fromAttribute(player:GetAttribute("GoalsDone"))
end

local function met(): { string }
	local list = player:GetAttribute("GoalMet")
	return if typeof(list) == "string" and list ~= "" then string.split(list, ",") else {}
end

-- "(1/2)" for saying hello to more than one, or "" for the rest.
local function progress(goal: GoalList.Goal): string
	if goal.kind == "talk" and goal.who and #goal.who > 1 then
		return ` ({GoalList.metCount(goal, met())}/{#goal.who})`
	end
	return ""
end

---------------------------------------------------------------- where to point

local function nearestTo(from: Vector3, spots: { Vector3 }): Vector3?
	local best, bestGap = nil, math.huge
	for _, spot in spots do
		local gap = (spot - from).Magnitude
		if gap < bestGap then
			best, bestGap = spot, gap
		end
	end
	return best
end

-- Where a resident is: their model if it's near enough to be loaded, or else their home.
local function residentAt(id: string): Vector3?
	for _, model in CollectionService:GetTagged(RESIDENT_TAG) do
		if model:GetAttribute("ResidentId") == id and model:IsA("Model") and model.PrimaryPart then
			return model.PrimaryPart.Position
		end
	end
	local home = Config.RESIDENT_HOMES[id]
	return if home then home.at else nil
end

-- Where the goal you're on wants you to go, or nil.
local function targetFor(goal: GoalList.Goal, from: Vector3): Vector3?
	if goal.kind == "talk" then
		local spots = {}
		local done = met()
		local who: { string } = goal.who or {}
		for _, id in who do
			if not table.find(done, id) then
				local at = residentAt(id)
				if at then
					table.insert(spots, at)
				end
			end
		end
		return nearestTo(from, spots)
	elseif goal.kind == "shop" or goal.kind == "hat" or goal.kind == "pet" then
		-- the shop's door: the goal's own shop, the Pet Shop for a pet, or else the Hat Shop
		local shopId = goal.shop or (if goal.kind == "pet" then "pets" else "hats")
		local residents = Workspace:FindFirstChild("Residents")
		local door = residents and residents:FindFirstChild(`ShopDoor_{shopId}`)
		if door and door:IsA("BasePart") then
			return door.Position
		end
		for _, shop in Config.SHOPS do
			if shop.id == shopId then
				return Config.polar(shop.angle, Config.SHOP_DIST - 4)
			end
		end
		return nil
	elseif goal.kind == "home" then
		local plots = Workspace:FindFirstChild("HomePlots")
		local spots = {}
		for _, plot in if plots then plots:GetChildren() else {} do
			local at = plot:GetAttribute("Plot")
			if typeof(at) == "CFrame" and plot:GetAttribute("OwnerId") == nil then
				table.insert(spots, at.Position)
			end
		end
		return nearestTo(from, spots)
	elseif goal.kind == "visit" then
		return goal.at
	elseif goal.kind == "plant" or goal.kind == "harvest" then
		return Garden.bedThatNeedsYou(from)
	elseif goal.kind == "cafe" then
		-- (not while you're on a shift: you're already there)
		return if player:GetAttribute("CafeHelper") then nil else residentAt("biscuit")
	end
	return nil
end

---------------------------------------------------------------- the arrow and the pin

local function part(props: { [string]: any }): Part
	local defaults = {
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Material = Enum.Material.SmoothPlastic,
		Color = Ui.colors.yellow,
	}
	for key, value in props do
		defaults[key] = value
	end
	return Ui.new("Part", defaults)
end

local function makeArrow(): Model
	-- a flat yellow arrow on the ground, pointing along its -Z: a shaft, and two short arms
	-- meeting at the tip
	local arrow = Instance.new("Model")
	arrow.Name = "GoalArrow"
	part({ Size = Vector3.new(1.1, 0.25, 4), CFrame = CFrame.new(0, 0, 0.6), Parent = arrow })
	local tip = Vector3.new(0, 0, -1.9)
	local arm, turn = 2.6, math.rad(38)
	for _, side in { -1, 1 } do
		local way = Vector3.new(side * math.sin(turn), 0, math.cos(turn)) -- from the tip, back and out
		part({
			Size = Vector3.new(1.1, 0.25, arm),
			CFrame = CFrame.lookAt(tip + way * arm / 2, tip + way * arm),
			Parent = arrow,
		})
	end
	arrow.WorldPivot = CFrame.identity
	return arrow
end

local function makePin(): (Part, BillboardGui)
	-- an invisible spot with a yellow map pin over it that shows through walls
	local spot = part({ Name = "GoalPin", Size = Vector3.new(1, 1, 1), Transparency = 1 })
	local pin = Ui.new("BillboardGui", {
		Size = UDim2.fromOffset(PIN_SIZE.X, PIN_SIZE.Y),
		StudsOffsetWorldSpace = Vector3.new(0, 9, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		Parent = spot,
	})
	-- the point at the bottom: a square turned on its corner, half hidden by the circle
	local tip = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 40),
		Size = UDim2.fromOffset(22, 22),
		Rotation = 45,
		BackgroundColor3 = Ui.colors.yellow,
		Parent = pin,
	}, { Ui.stroke(3) })
	tip.ZIndex = 1
	local head = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = Ui.colors.yellow,
		Parent = pin,
	}, { Ui.round(), Ui.stroke(3) })
	head.ZIndex = 2
	Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(16, 16),
		BackgroundColor3 = Ui.colors.paper,
		ZIndex = 3,
		Parent = head,
	}, { Ui.round(), Ui.stroke(2.5) })
	return spot, pin
end

---------------------------------------------------------------- the card on the HUD

-- `corner` is the HUD's top-right frame. The card isn't a button, so it never takes a tap
-- meant for the game's buttons underneath it (the Goals button opens the list).
function GoalsPanel.start(corner: Frame)
	local hud = corner:FindFirstAncestorOfClass("ScreenGui")

	local card = Ui.new("Frame", {
		Size = UDim2.fromOffset(240, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Ui.colors.paper,
		LayoutOrder = 3,
		Visible = false,
		Parent = corner,
	}, {
		Ui.corner(14),
		Ui.stroke(2.5),
		Ui.new("UIPadding", {
			PaddingLeft = UDim.new(0, 12),
			PaddingRight = UDim.new(0, 12),
			PaddingTop = UDim.new(0, 6),
			PaddingBottom = UDim.new(0, 8),
		}),
		Ui.new("UIListLayout", { Padding = UDim.new(0, 1), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local function line(order: number, size: number, color: Color3): TextLabel
		return Ui.text({
			TextSize = size,
			TextColor3 = color,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order,
			Parent = card,
		})
	end
	local number = line(1, 14, Ui.colors.coral)
	local words = line(2, 16, Ui.colors.ink)
	words.RichText = true
	local hint = line(3, 14, Ui.colors.teal)
	local later = line(4, 14, Ui.colors.leaf)

	local function refresh()
		local goal = currentGoal()
		local done = goalsDone()
		local choosing = goal == nil and GoalList.storyDone(done) and not GoalList.allDone(done)
		-- On a phone (a short screen): one short line. Elsewhere: where you are, what to do, a
		-- hint, and the "later" line about your garden.
		local small = Ui.shortScreen()
		card.Visible = goal ~= nil or choosing
		number.Visible = not small
		hint.Visible = not small
		if goal then
			local step = GoalList.storyStep(goal.id)
			number.Text = if step then `First Story · {step} of {#STORY}` else "Your adventure"
			local coral = Ui.colors.coral:ToHex()
			words.Text = if small and step
				then `<font color="#{coral}">{step}/{#STORY}</font>  {goal.text}{progress(goal)}`
				else goal.text .. progress(goal)
			hint.Text = goal.hint
		elseif choosing then
			number.Text = "Adventures"
			words.Text = "Choose your next adventure"
			hint.Text = "Press Goals to pick one"
		end
		-- (not while the goal is about the garden already)
		local gardenGoal = goal ~= nil and (goal.kind == "plant" or goal.kind == "harvest")
		local text = if gardenGoal or small then nil else Garden.laterLine()
		later.Text = text or ""
		later.Visible = text ~= nil
	end
	for _, attribute in { "Goal", "GoalsDone", "GoalMet", "Garden" } do
		player:GetAttributeChangedSignal(attribute):Connect(refresh)
	end
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(refresh)
	end
	refresh()
	-- crops grow by the clock, so look again now and then
	task.spawn(function()
		while card.Parent do
			task.wait(1)
			refresh()
		end
	end)

	-- "Well done!" (in turn: see Hud.announce)
	Remotes.GoalDone.OnClientEvent:Connect(function(id, coins, sun, storyDone, finished, bonus)
		if typeof(coins) ~= "number" or typeof(sun) ~= "number" then
			return
		end
		Hud.announce("Well done!", `+{coins} coins and {sun} sunshine`)
		local goal = if typeof(id) == "string" then GoalList.BY_ID[id] else nil
		if goal and goal.next then
			Hud.announce(goal.next.title, goal.next.small)
		end
		if storyDone == true then
			Hud.announce("First Story done!", "Now choose your next adventure.")
			Hud.inTurn(GoalsPanel.open)
		end
		if finished == true and bonus == true then
			local extra = GoalList.FINISH
			Hud.announce("All adventures done!", `+{extra.coins} coins and {extra.sun} sunshine. Now go and explore!`)
		elseif finished == true then
			Hud.announce("All adventures done!", "Now go and explore!")
		end
	end)

	-- The arrow and the pin. Where to point is worked out a few times a second; the arrow
	-- follows your feet every frame (it's only one small thing, on your own screen).
	local arrow = makeArrow()
	local spot, pin = makePin()
	local target: Vector3? = nil
	local nextFind = 0
	RunService.RenderStepped:Connect(function()
		local character = player.Character
		local root = character and character.PrimaryPart
		local goal = currentGoal()
		local showing = goal ~= nil and root ~= nil and hud ~= nil and hud.Enabled and Ui.openScreens == 0
			and screen == nil
		if not showing or not root or not goal then
			arrow.Parent = nil
			spot.Parent = nil
			return
		end
		local now = os.clock()
		if now >= nextFind then
			nextFind = now + FIND_SECONDS
			target = targetFor(goal, root.Position)
		end
		if not target then
			arrow.Parent = nil
			spot.Parent = nil
			return
		end
		local feet = root.Position - Vector3.new(0, Builder.ROOT_HEIGHT - 0.2, 0)
		local flat = Vector3.new(target.X - feet.X, 0, target.Z - feet.Z)

		-- the pin, until you've arrived
		if flat.Magnitude < Config.UI.GOAL_PIN_ARRIVED then
			spot.Parent = nil
		else
			spot.Position = target
			pin.StudsOffsetWorldSpace = Vector3.new(0, PIN_HEIGHT[goal.kind] or PIN_HEIGHT_OTHER, 0)
			pin.SizeOffset = Vector2.new(0, (PIN_LIFT[goal.kind] or 0) + math.sin(now * 3) * PIN_BOB)
			spot.Parent = Workspace
		end

		if flat.Magnitude < NEAR then
			arrow.Parent = nil
			return
		end
		local way = flat.Unit
		local bob = 5.5 + math.sin(now * 4) * 0.5
		arrow:PivotTo(CFrame.lookAt(feet + way * bob, feet + way * (bob + 1)))
		arrow.Parent = Workspace
	end)
end

---------------------------------------------------------------- the Goals screen

-- Points a picture's camera at a model so all of it fits, looking from `from`.
local function aim(camera: Camera, model: Model, from: Vector3)
	local size = model:GetExtentsSize()
	local biggest = math.max(size.X, size.Y, size.Z)
	local centre = model:GetBoundingBox().Position
	camera.CFrame = CFrame.lookAt(centre + from.Unit * (biggest * 2.1 + 1), centre)
end

-- A little gazebo for its card, like the one in town (server/Town) with fewer parts.
local function littleGazebo(): Model
	local model = Instance.new("Model")
	Build.into(model)
	local C = Build.C
	Build.cylinder(4.6 * S, 0.2 * S, CFrame.new(0, 0.1 * S, 0), C.stone)
	Build.cylinder(4.2 * S, 0.25 * S, CFrame.new(0, 0.325 * S, 0), C.cream)
	for i = 0, 7 do
		local a = math.rad(22.5 + i * 45)
		Build.cylinder(0.14 * S, 3.0 * S, CFrame.Angles(0, a, 0) * CFrame.new(0, 1.95 * S, 3.7 * S), C.white)
	end
	for _, t in { { 4.6, 0.3, 3.6, C.coral }, { 3.6, 0.45, 3.95, C.cream }, { 2.5, 0.45, 4.35, C.coral }, { 1.3, 0.45, 4.75, C.cream } } do
		Build.cylinder(t[1] * S, t[2] * S, CFrame.new(0, t[3] * S, 0), t[4])
	end
	Build.ball(0.7 * S, CFrame.new(0, 5.15 * S, 0), C.yellow)
	return model
end

-- The picture on an Adventure's card, and which way its camera looks at it.
local function adventurePicture(id: string): (Model?, Vector3)
	if id == "home" then
		local model = Instance.new("Model")
		Build.into(model)
		Houses.build(Houses.DEFAULT, CFrame.identity, nil)
		return model, Vector3.new(0.45, 0.5, 1)
	elseif id == "friends" then
		local model = Instance.new("Model")
		for i, who in { "puddles", "pebble" } do
			local resident = Looks.resident(who)
			if resident then
				local animal = Builder.build(Looks.residentLook(resident), { viewport = true })
				animal:PivotTo(CFrame.new((i - 1.5) * 3.2, Builder.ROOT_HEIGHT, 0) * CFrame.Angles(0, (1.5 - i) * 0.5, 0))
				animal.Parent = model
			end
		end
		return model, Vector3.new(0.15, 0.25, -1)
	elseif id == "pet" then
		return PetBuilder.build({ kind = "puppy", color = 1 }).model, Vector3.new(0.6, 0.35, -1)
	elseif id == "clothes" then
		-- a backpack, if the shop has one, or else the first thing it sells
		local items = Looks.shopClothes()
		local item = items[1]
		for _, each in items do
			if each.slot == "back" then
				item = each
				break
			end
		end
		return if item then Builder.clothesModel("capybara", item.id) else nil, Vector3.new(0.6, 0.3, -1)
	elseif id == "gazebo" then
		return littleGazebo(), Vector3.new(0.4, 0.55, -1)
	elseif id == "cafe" then
		-- Biscuit, with a mug of cocoa beside her
		local model = Instance.new("Model")
		local biscuit = Looks.resident("biscuit")
		if biscuit then
			local animal = Builder.build(Looks.residentLook(biscuit), { viewport = true })
			animal:PivotTo(CFrame.new(-1.2, Builder.ROOT_HEIGHT, 0) * CFrame.Angles(0, 0.3, 0))
			animal.Parent = model
		end
		local cocoa = CafeFood.model("cocoa", 2)
		cocoa:PivotTo(CFrame.new(1.8, 0, -0.5))
		cocoa.Parent = model
		return model, Vector3.new(0.2, 0.25, -1)
	end
	return nil, Vector3.new(0, 0, -1)
end

function GoalsPanel.isOpen(): boolean
	return screen ~= nil
end

function GoalsPanel.open()
	if screen or Ui.openScreens > 0 then
		return
	end
	Controls.set(false, "goals")
	local gui = Ui.screen("Goals", 17)
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

	local function close()
		gui:Destroy()
		screen = nil
		Controls.set(true, "goals")
	end

	local done = goalsDone()
	local now = currentGoal()
	local storyDone = GoalList.storyDone(done)
	Ui.text({
		Text = if GoalList.allDone(done) then "All done!" elseif storyDone then "Adventures" else "Your First Story",
		TextSize = 22,
		TextColor3 = Ui.colors.coral,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.fromOffset(240, Ui.TOUCH),
		Parent = card,
	})
	local closeButton = Ui.button("Close", Ui.colors.cream, close, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(84, Ui.TOUCH),
		TextSize = 20,
		Parent = card,
	})

	-- your sunshine: a little sun and how much you've got
	local sun = player:GetAttribute("Sun")
	local sunPill = Ui.new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -100, 0, 8),
		Size = UDim2.fromOffset(0, Ui.TOUCH),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Ui.colors.cream,
		Parent = card,
	}, {
		Ui.round(),
		Ui.stroke(3),
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 14) }),
		Ui.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	Ui.new("Frame", {
		Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = Ui.colors.yellow,
		LayoutOrder = 1,
		Parent = sunPill,
	}, { Ui.round(), Ui.stroke(3, Ui.colors.coral) })
	Ui.text({
		Text = `{if typeof(sun) == "number" then sun else 0} sunshine`,
		TextSize = 18,
		Size = UDim2.fromOffset(0, 30),
		AutomaticSize = Enum.AutomaticSize.X,
		TextWrapped = false,
		LayoutOrder = 2,
		Parent = sunPill,
	})

	local first: GuiObject = closeButton
	if not storyDone then
		-- the First Story: four rows, ticked off as you go
		local list = Ui.new("Frame", {
			Position = UDim2.fromOffset(14, 62),
			Size = UDim2.fromOffset(592, 216),
			BackgroundTransparency = 1,
			Parent = card,
		}, {
			Ui.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		for i, goal in STORY do
			local isDone = table.find(done, goal.id) ~= nil
			local isNow = now ~= nil and now.id == goal.id
			local row = Ui.new("Frame", {
				Size = UDim2.fromOffset(592, 48),
				BackgroundColor3 = if isNow then Ui.colors.yellowLight else Ui.colors.paper,
				BackgroundTransparency = if isNow then 0 else 1,
				LayoutOrder = i,
				Parent = list,
			}, { Ui.corner(12) })
			local badge = Ui.new("Frame", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 6, 0.5, 0),
				Size = UDim2.fromOffset(36, 36),
				BackgroundColor3 = if isDone then Ui.colors.teal elseif isNow then Ui.colors.yellow else Ui.colors.cream,
				Parent = row,
			}, { Ui.round(), Ui.stroke(2.5, if isDone or isNow then Ui.colors.ink else Ui.colors.grey) })
			Ui.text({
				Text = tostring(i),
				TextSize = 18,
				TextColor3 = if isDone then Ui.colors.paper elseif isNow then Ui.colors.ink else Ui.colors.grey,
				Size = UDim2.fromScale(1, 1),
				Parent = badge,
			})
			Ui.text({
				Text = if isDone then `{goal.text} · done!` elseif isNow then `{goal.text}{progress(goal)} · {goal.hint}` else goal.text,
				TextSize = 16,
				TextColor3 = if isDone then Ui.colors.teal elseif isNow then Ui.colors.ink else Ui.colors.grey,
				TextXAlignment = Enum.TextXAlignment.Left,
				Position = UDim2.fromOffset(52, 0),
				Size = UDim2.new(1, -58, 1, 0),
				Parent = row,
			})
		end
	else
		-- the Adventures: a row of big picture cards. Tap one to do it next.
		local row = Ui.new("Frame", {
			Position = UDim2.fromOffset(14, 62),
			Size = UDim2.fromOffset(592, 216),
			BackgroundTransparency = 1,
			Parent = card,
		}, {
			Ui.new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		local chosen: GuiObject? = nil
		local firstOpen: GuiObject? = nil
		-- each card as wide as the row allows, so they all fit however many there are
		local count = #GoalList.ADVENTURES
		local wide = math.floor((592 - (count - 1) * 8) / count)
		for i, goal in GoalList.ADVENTURES do
			local isDone = table.find(done, goal.id) ~= nil
			local isNow = now ~= nil and now.id == goal.id
			local size = UDim2.fromOffset(wide, 216)
			local tile: GuiObject
			if isDone then
				tile = Ui.new("Frame", { Size = size, BackgroundColor3 = Ui.colors.paper, LayoutOrder = i, Parent = row },
					{ Ui.corner(16), Ui.stroke(3, Ui.colors.grey) })
			else
				tile = Ui.button("", if isNow then Ui.colors.yellowLight else Ui.colors.cream, function()
					Remotes.ChooseAdventure:FireServer(goal.id)
					close()
				end, { Size = size, LayoutOrder = i, Parent = row })
				firstOpen = firstOpen or tile
				if isNow then
					chosen = tile
				end
			end
			local stage = Ui.new("Frame", {
				Position = UDim2.fromOffset(6, 6),
				Size = UDim2.fromOffset(wide - 12, 104),
				BackgroundColor3 = Ui.colors.mint,
				Parent = tile,
			}, { Ui.corner(12) })
			local view, camera = Ui.viewport({ Size = UDim2.fromScale(1, 1), Parent = stage })
			-- (a model that can't be built leaves the picture empty, never the whole screen)
			local ok, model, from = pcall(adventurePicture, goal.id)
			if ok and model then
				model.Parent = view
				aim(camera, model, from)
			end
			local name = Ui.text({
				Text = goal.short or goal.text,
				TextScaled = true, -- (a long name shrinks a little to fit the narrower cards)
				TextColor3 = if isDone then Ui.colors.grey else Ui.colors.ink,
				Position = UDim2.fromOffset(4, 114),
				Size = UDim2.new(1, -8, 0, 52),
				Parent = tile,
			})
			Ui.new("UITextSizeConstraint", { MaxTextSize = 16, MinTextSize = 12, Parent = name })
			Ui.text({
				Text = if isDone then "Done!" elseif isNow then "Doing now" else `+{goal.coins} coins`,
				TextSize = 15,
				TextColor3 = if isDone then Ui.colors.teal elseif isNow then Ui.colors.coral else Ui.colors.teal,
				Position = UDim2.fromOffset(4, 170),
				Size = UDim2.new(1, -8, 0, 40),
				Parent = tile,
			})
		end
		first = chosen or firstOpen or closeButton
	end
	Ui.controller(gui, card, first, close)
end

return GoalsPanel
