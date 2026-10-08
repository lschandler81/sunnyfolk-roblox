-- The goals on the player's screen (the list is in shared/Goals; the server keeps score):
--   * a card under the Goals button saying which goal you're on, and how far you've got
--   * a yellow arrow at your feet and a pin over the place to go, pointing the way (they only
--     point: they never move you)
--   * "Well done!" when you finish one (Hud.announce: it waits until any open screen has closed
--     and the last message has gone, so it's always seen)
--   * the Goals screen (from the HUD's Goals button): every goal, ticked off, and your
--     sunshine
-- Everything here only shows what the server says; it never changes progress.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Builder = require(Shared.CharacterBuilder)
local Config = require(Shared.Config)
local GoalList = require(Shared.Goals)
local Controls = require(script.Parent.Controls)
local Hud = require(script.Parent.Hud)
local Ui = require(script.Parent.Ui)

local Remotes = Shared:WaitForChild("Remotes")
local player = Players.LocalPlayer

local LIST = GoalList.LIST
local RESIDENT_TAG = "SunnyfolkResident" -- server/Residents tags each resident with this
local FIND_SECONDS = 0.25 -- how often to look again for where to point
local NEAR = 10 -- studs: closer than this, the arrow at your feet goes (the pin's enough)
-- How high (studs) the pin floats over what it points at: just above a coin, over a
-- resident's name tag, and in between for doors, plots and places.
local PIN_HEIGHT = { coin = 3.5, talk = 9 }
local PIN_HEIGHT_OTHER = 6

local GoalsPanel = {}

local screen: ScreenGui? = nil

local function currentStep(): number?
	local goal = player:GetAttribute("Goal")
	return if typeof(goal) == "number" then goal else nil
end

local function met(): { string }
	local list = player:GetAttribute("GoalMet")
	return if typeof(list) == "string" and list ~= "" then string.split(list, ",") else {}
end

-- "(3/10)" for a goal you count up, or "" for the rest.
local function progress(goal: GoalList.Goal): string
	if goal.kind == "coin" then
		local got = player:GetAttribute("GoalCount")
		return ` ({math.min(goal.need or 1, if typeof(got) == "number" then got else 0)}/{goal.need})`
	elseif goal.kind == "talk" and goal.who and #goal.who > 1 then
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
	elseif goal.kind == "coin" then
		local folder = Workspace:FindFirstChild("MyCoins")
		local spots = {}
		for _, coin in if folder then folder:GetChildren() else {} do
			if coin:IsA("Model") then
				table.insert(spots, coin:GetPivot().Position)
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
	elseif goal.kind == "harvest" then
		return Config.gardenFrame().Position
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
		Size = UDim2.fromOffset(48, 62),
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

	-- The game's buttons ("Talk", "Hat Shop"...), from client/Prompts, which says how many
	-- are showing. On a phone they're right where the card is, so it steps aside for them.
	local prompts = player:WaitForChild("PlayerGui"):WaitForChild("Prompts", 10)
	local function buttonsShowing(): boolean
		local count = prompts and prompts:GetAttribute("Showing")
		return typeof(count) == "number" and count > 0
	end

	local function refresh()
		local step = currentStep()
		local goal = step and LIST[step]
		-- On a phone (a short screen): one short line, and out of the way while there's a button
		-- to press. Elsewhere: the goal number, what to do and a hint.
		local small = Ui.shortScreen()
		card.Visible = goal ~= nil and not (small and buttonsShowing())
		if goal then
			number.Visible = not small
			hint.Visible = not small
			number.Text = `Goal {step} of {#LIST}`
			local coral = Ui.colors.coral:ToHex()
			words.Text = if small
				then `<font color="#{coral}">{step}/{#LIST}</font>  {goal.text}{progress(goal)}`
				else goal.text .. progress(goal)
			hint.Text = goal.hint
		end
	end
	for _, attribute in { "Goal", "GoalCount", "GoalMet" } do
		player:GetAttributeChangedSignal(attribute):Connect(refresh)
	end
	if prompts then
		prompts:GetAttributeChangedSignal("Showing"):Connect(refresh)
	end
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(refresh)
	end
	refresh()

	-- "Well done!" (in turn: see Hud.announce)
	Remotes.GoalDone.OnClientEvent:Connect(function(_id, coins, sun, finished, bonus)
		if typeof(coins) ~= "number" or typeof(sun) ~= "number" then
			return
		end
		Hud.announce("Well done!", `+{coins} coins and {sun} sunshine`)
		if finished and bonus == true then
			local extra = GoalList.FINISH
			Hud.announce("All goals done!", `+{extra.coins} coins and {extra.sun} sunshine. Now go and explore!`)
		elseif finished then
			Hud.announce("All goals done!", "Now go and explore!")
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
		local step = currentStep()
		local goal = step and LIST[step]
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
		spot.Position = target
		local height = PIN_HEIGHT[goal.kind] or PIN_HEIGHT_OTHER
		pin.StudsOffsetWorldSpace = Vector3.new(0, height + math.sin(now * 3) * 0.6, 0)
		spot.Parent = Workspace

		local feet = root.Position - Vector3.new(0, Builder.ROOT_HEIGHT - 0.2, 0)
		local flat = Vector3.new(target.X - feet.X, 0, target.Z - feet.Z)
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

	local step = currentStep() or 1
	Ui.text({
		Text = if GoalList.done(step) then "All goals done!" else "Your goals",
		TextSize = 22,
		TextColor3 = Ui.colors.coral,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.fromOffset(200, Ui.TOUCH),
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

	-- the goals, in two columns of four
	local list = Ui.new("Frame", {
		Position = UDim2.fromOffset(14, 60),
		Size = UDim2.fromOffset(592, 222),
		BackgroundTransparency = 1,
		Parent = card,
	}, {
		Ui.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(290, 50),
			CellPadding = UDim2.fromOffset(12, 6),
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	for i, goal in LIST do
		local done = i < step
		local now = i == step
		local row = Ui.new("Frame", {
			BackgroundColor3 = if now then Ui.colors.yellowLight else Ui.colors.paper,
			BackgroundTransparency = if now then 0 else 1,
			LayoutOrder = i,
			Parent = list,
		}, { Ui.corner(12) })
		local badge = Ui.new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 6, 0.5, 0),
			Size = UDim2.fromOffset(36, 36),
			BackgroundColor3 = if done then Ui.colors.teal elseif now then Ui.colors.yellow else Ui.colors.cream,
			Parent = row,
		}, { Ui.round(), Ui.stroke(2.5, if done or now then Ui.colors.ink else Ui.colors.grey) })
		Ui.text({
			Text = tostring(i),
			TextSize = 18,
			TextColor3 = if done then Ui.colors.paper elseif now then Ui.colors.ink else Ui.colors.grey,
			Size = UDim2.fromScale(1, 1),
			Parent = badge,
		})
		Ui.text({
			Text = if done then `{goal.text} · done!` elseif now then goal.text .. progress(goal) else goal.text,
			TextSize = 15,
			TextColor3 = if done then Ui.colors.teal elseif now then Ui.colors.ink else Ui.colors.grey,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(50, 0),
			Size = UDim2.new(1, -54, 1, 0),
			Parent = row,
		})
	end
	Ui.controller(gui, card, closeButton, close)
end

return GoalsPanel
