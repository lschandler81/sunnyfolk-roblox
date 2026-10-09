-- Fishing on this player's screen (Config.FISHING; the server picks every bite and every fish
-- in server/Fishing):
--   * a "Go fishing" button by each pond in Config.FISHING_PONDS (made here, on this screen only)
--   * while you fish: your animal stands still facing the water, and a card along the bottom
--     says what to do, with Reel in, Fish book and All done. Cast, wait for the splash (the
--     bobber dips and a big yellow "!" pops up over it), then reel in. Tapping before the
--     splash just says "Not yet!" (nothing is sent, so nothing is lost). A catch leaps out of
--     the water, says its name, and goes back in. A fish that isn't reeled in swims off, and
--     the line is cast again by itself.
--   * everyone fishing nearby has a rod in their paw and a line out to their bobber, from their
--     Fishing attribute (where their bobber is), so friends can fish side by side
-- With a controller: A reels in, Y opens the Fish Book and D-pad down is All done (each button
-- shows its picture). With a keyboard, Space or E reels in. While you fish, every other button
-- nearby ("Talk"...) steps aside.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Build = require(Shared.Build)
local Config = require(Shared.Config)
local Controls = require(script.Parent.Controls)
local FishBook = require(script.Parent.FishBook)
local Hud = require(script.Parent.Hud)
local Run = require(script.Parent.Run)
local Ui = require(script.Parent.Ui)

local Remotes = Shared:WaitForChild("Remotes")
local player = Players.LocalPlayer

local F = Config.FISHING
local C = Build.C
local S = Config.STUDS
local PROPS = { CanCollide = false, CanTouch = false, CanQuery = false, CastShadow = false }
local ARM_POSE = Vector2.new(0.95, -0.12) -- the paw holding the rod, out in front (like a mug)
local CARD = Vector2.new(460, 132) -- the card's size on a phone, in pixels
local CARD_MOST = 1.3 -- how much bigger it may grow on a tablet or computer
local CARD_TALL = 0.28 -- and never taller than this part of the screen, so your animal shows
local BANG_SIZE = 2.4 -- studs: the "!" over a biting fish is this big in the world
local LEAP = 1.1 -- seconds a caught fish spends leaping out of the water
local LINE = Color3.fromHex("#f7f3e8")

local Fishing = {}

local folder: Folder

---------------------------------------------------------------- everyone's rods and bobbers

-- What's drawn for each player who's fishing: the rod in their paw, their bobber, its gentle
-- bobbing, and what their paw's pose was before.
type Gear = { model: Model, rod: Model, bobber: BasePart, bob: Tween, pose: any }
local gear: { [Player]: Gear } = {}

local function clearGear(who: Player)
	local g = gear[who]
	if not g then
		return
	end
	gear[who] = nil
	g.bob:Cancel()
	g.rod:Destroy()
	g.bobber:Destroy()
	if g.model.Parent then
		g.model:SetAttribute("RightArmPose", g.pose)
	end
end

-- A ring on the water at `at` that spreads and fades: a splash.
local function ripple(at: Vector3)
	Build.into(folder)
	local ring = Build.cylinder(0.4 * S, 0.05, CFrame.new(at), C.white, PROPS) -- (a flat one)
	ring.Transparency = 0.2
	local grow = 1.6 * S
	TweenService:Create(ring, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.05, grow, grow),
		Transparency = 1,
	}):Play()
	task.delay(0.9, function()
		ring:Destroy()
	end)
end

-- Players fishing whose animal hasn't arrived on this screen yet (it's far away, so it hasn't
-- streamed in): drawn as soon as it does.
local arriving: { [Player]: RBXScriptConnection } = {}

local function drawGear(who: Player)
	clearGear(who)
	if arriving[who] then
		arriving[who]:Disconnect()
		arriving[who] = nil
	end
	local at = who:GetAttribute("Fishing")
	local character = who.Character
	local root = character and character.PrimaryPart
	if typeof(at) ~= "Vector3" or not character then
		return
	end
	if not root then
		arriving[who] = character.ChildAdded:Connect(function(child)
			if child.Name == "HumanoidRootPart" then
				task.defer(drawGear, who)
			end
		end)
		return
	end

	-- the rod: held out on the side of their right paw, angled up over the water, welded to
	-- them so it moves with them for free
	local arm = character:FindFirstChild("RightArm")
	local armX = if arm and arm:IsA("BasePart") then root.CFrame:PointToObjectSpace(arm.Position).X else 1
	local side = if armX < 0 then -1 else 1
	local base = root.CFrame * CFrame.new(side * math.max(math.abs(armX), 0.8), 0.2, -1)
	local tip = root.CFrame * CFrame.new(side * 1.4, 3.8, -5.6)
	local along = CFrame.lookAt(base.Position, tip.Position) * CFrame.Angles(-math.pi / 2, 0, 0)
	local length = (tip.Position - base.Position).Magnitude
	local rod = Instance.new("Model")
	rod.Name = "FishingRod"
	Build.into(rod)
	local pole = Build.cylinder(0.06 * S, length, along * CFrame.new(0, length / 2, 0), C.woodDark, PROPS)
	Build.cylinder(0.12 * S, 0.5 * S, along * CFrame.new(0, 0.25 * S, 0), C.coral, PROPS) -- the handle
	Build.cylinder(0.14 * S, 0.12 * S, along * CFrame.new(0.14 * S, 0.7 * S, 0) * CFrame.Angles(0, 0, math.pi / 2), C.yellow, PROPS) -- the reel
	for _, part in rod:GetChildren() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = part
		end
	end
	local tipAttachment = Instance.new("Attachment")
	tipAttachment.Position = Vector3.new(length / 2, 0, 0) -- (a cylinder part's length is along its X)
	tipAttachment.Parent = pole
	rod.Parent = character

	-- the bobber: red underneath, white on top, bobbing gently
	Build.into(folder)
	local float = Build.ball(0.35 * S, CFrame.new(at + Vector3.new(0, 0.1, 0)), C.coral, PROPS)
	local top = Build.ball(0.22 * S, float.CFrame * CFrame.new(0, 0.16 * S, 0), C.white, PROPS)
	top.Anchored = false
	top.Massless = true
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = float
	weld.Part1 = top
	weld.Parent = top
	local lineEnd = Instance.new("Attachment")
	lineEnd.Position = Vector3.new(0, 0.25 * S, 0)
	lineEnd.Parent = float
	local line = Instance.new("Beam")
	line.Attachment0 = tipAttachment
	line.Attachment1 = lineEnd
	line.Width0 = 0.08
	line.Width1 = 0.08
	line.Color = ColorSequence.new(LINE)
	line.LightInfluence = 0
	line.FaceCamera = true
	line.Segments = 1
	line.Parent = float
	local bob = TweenService:Create(float, TweenInfo.new(1.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		CFrame = float.CFrame + Vector3.new(0, 0.15, 0),
	})
	bob:Play()

	-- their paw stays up, holding it (client/Animator)
	local pose = character:GetAttribute("RightArmPose")
	character:SetAttribute("RightArmPose", ARM_POSE)
	gear[who] = { model = character, rod = rod, bobber = float, bob = bob, pose = pose }
	if who == player then
		ripple(at)
	end
end

local function watchGear(who: Player)
	who:GetAttributeChangedSignal("Fishing"):Connect(function()
		drawGear(who)
	end)
	who.CharacterAdded:Connect(function(character)
		character:WaitForChild("HumanoidRootPart", 10)
		drawGear(who)
	end)
	drawGear(who)
end

---------------------------------------------------------------- your own fishing

-- While you're fishing: which pond, and where you've got to. `token` changes with every cast,
-- so a wait from an earlier cast never sets off a splash.
type Mine = { pond: number, phase: string, token: {} }
local mine: Mine? = nil

local card: Frame
local message: TextLabel
local reelButton: TextButton
local bang: BillboardGui? = nil -- the big "!" over your bobber while a fish bites

local function say(text: string)
	message.Text = text
end

local function shake()
	message.Rotation = 4
	TweenService:Create(message, TweenInfo.new(0.35, Enum.EasingStyle.Elastic), { Rotation = 0 }):Play()
end

local function noBang()
	if bang then
		bang:Destroy()
		bang = nil
	end
	reelButton.BackgroundColor3 = Ui.colors.yellow
end

local waitForBite: (seconds: number) -> ()

-- Casts the line: the server says when a fish will bite.
local function cast()
	local current = mine
	if not current then
		return
	end
	noBang()
	current.phase = "cast"
	current.token = {}
	reelButton.Text = "Reel in!"
	say("Wait for the splash...")
	local ok, result = pcall(function()
		return table.pack(Remotes.FishAction:InvokeServer("cast", current.pond))
	end)
	if mine ~= current then
		return -- they stopped while it was on its way
	end
	if not (ok and result[1] == true and typeof(result[2]) == "number") then
		Fishing.stop()
		local why = if ok then result[2] else nil
		Hud.announce("Oh!", if typeof(why) == "string" then why else "Something went wrong.")
		return
	end
	local g = gear[player]
	if g then
		ripple(g.bobber.Position) -- (a cast at the same spot as last time doesn't redraw it)
	end
	waitForBite(result[2])
end

-- A fish bites: the bobber dips, a big "!" pops up, and the button turns coral. It waits
-- BITE_SECONDS for you; then it swims off, and the line is cast again.
local function bite(token: {})
	local current = mine
	if not (current and current.token == token) then
		return
	end
	current.phase = "bite"
	say("Splash! Reel in!")
	noBang()
	reelButton.BackgroundColor3 = Ui.colors.coral
	local g = gear[player]
	if g then
		ripple(g.bobber.Position)
		g.bob:Pause()
		local dip = TweenService:Create(g.bobber, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 5, true), {
			CFrame = g.bobber.CFrame - Vector3.new(0, 0.5, 0),
		})
		dip:Play()
		dip.Completed:Once(function()
			if gear[player] == g then
				g.bob:Play()
			end
		end)
		local sign = Ui.new("BillboardGui", {
			Size = UDim2.fromScale(BANG_SIZE, BANG_SIZE), -- (in studs, so it's smaller further away)
			StudsOffsetWorldSpace = Vector3.new(0, 1.3 * S, 0),
			AlwaysOnTop = true,
			LightInfluence = 0,
			Adornee = g.bobber,
			Parent = g.bobber,
		})
		local mark = Ui.text({
			Text = "!",
			TextScaled = true,
			BackgroundTransparency = 0,
			BackgroundColor3 = Ui.colors.yellow,
			Size = UDim2.fromScale(1, 1),
			Parent = sign,
		})
		Ui.round().Parent = mark
		Ui.stroke(3).Parent = mark
		Ui.new("UIPadding", { -- room round the "!" inside its circle
			PaddingTop = UDim.new(0.18, 0),
			PaddingBottom = UDim.new(0.18, 0),
			Parent = mark,
		})
		bang = sign
	end
	task.delay(F.BITE_SECONDS, function()
		if mine and mine.token == token and mine.phase == "bite" then
			-- gone: a tap now says "Not yet!", and nothing from this bite can come back
			local gone = {}
			mine.phase = "gone"
			mine.token = gone
			noBang()
			say("It swam off! Here comes another...")
			task.delay(1.2, function()
				if mine and mine.token == gone then
					cast()
				end
			end)
		end
	end)
end

-- Waits `seconds` for the next bite (as the server said).
waitForBite = function(seconds: number)
	local current = mine
	if not current then
		return
	end
	noBang()
	current.phase = "wait"
	local token = {}
	current.token = token
	task.delay(seconds, bite, token)
end

-- The caught fish leaps out of the water and splashes back in.
local function leap(id: string)
	local g = gear[player]
	local root = player.Character and player.Character.PrimaryPart
	if not (g and root) then
		return
	end
	local at = g.bobber.Position
	local fish = FishBook.model(id, 1.4)
	local across = CFrame.lookAt(at, at + root.CFrame.RightVector) -- side on to you
	fish:PivotTo(across)
	fish.Parent = folder
	-- up in an arc and back down, wiggling
	local k = Instance.new("NumberValue")
	k.Changed:Connect(function(t)
		local up = math.sin(t * math.pi) * 2.2 * S
		fish:PivotTo((across + Vector3.new(0, up, 0)) * CFrame.Angles(0, math.sin(t * 30) * 0.3, 0))
	end)
	local tween = TweenService:Create(k, TweenInfo.new(LEAP, Enum.EasingStyle.Linear), { Value = 1 })
	tween:Play()
	tween.Completed:Once(function()
		ripple(at)
		fish:Destroy()
		k:Destroy()
	end)
	ripple(at)
end

-- Reel in! Before the splash it just says "Not yet!"; after a catch it casts again.
local function reel()
	local current = mine
	if not current or current.phase == "reeling" then
		return
	end
	if current.phase == "caught" then
		task.spawn(cast)
		return
	end
	if current.phase ~= "bite" then
		say("Not yet! Wait for the splash.")
		shake()
		return
	end
	current.phase = "reeling"
	local token = current.token
	noBang()
	local ok, result = pcall(function()
		return table.pack(Remotes.FishAction:InvokeServer("reel"))
	end)
	if mine ~= current or current.token ~= token then
		return
	end
	if ok and result[1] == true and typeof(result[2]) == "string" then
		local fish = Config.fish(result[2])
		local coins = if typeof(result[3]) == "number" then result[3] else 0
		current.phase = "caught"
		reelButton.Text = "Fish again"
		leap(result[2])
		local name = if fish then fish.name else "fish"
		say(if coins > 0
			then `A {name}! New in your book! +{coins} coins`
			else `A {name}! Back in the water it goes. Splash!`)
	elseif ok and result[1] == false and (result[2] == "soon" or result[2] == "away") and typeof(result[3]) == "number" then
		say("It swam off! Wait for the next one...")
		waitForBite(result[3])
	else
		Fishing.stop()
		local why = if ok then result[2] else nil
		Hud.announce("Oh!", if typeof(why) == "string" then why else "Something went wrong.")
	end
end

-- Puts the rod away (and tells the server).
function Fishing.stop()
	if not mine then
		return
	end
	mine = nil
	noBang()
	card.Visible = false
	ProximityPromptService.Enabled = true
	Controls.set(true, "fishing")
	local hud = Hud.gui()
	if hud and hud.Enabled then
		Run.show(true)
	end
	task.spawn(pcall, function()
		Remotes.FishAction:InvokeServer("stop")
	end)
end

local function begin(pond: number)
	local spot = Config.FISHING_PONDS[pond]
	local hud = Hud.gui()
	local root = player.Character and player.Character.PrimaryPart
	if mine or not spot or not root or Ui.openScreens > 0 or not (hud and hud.Enabled)
		or player:GetAttribute("CafeHelper") then
		return
	end
	mine = { pond = pond, phase = "cast", token = {} }
	-- stand still, facing the water
	Controls.set(false, "fishing")
	Run.show(false)
	root.CFrame = CFrame.lookAt(root.Position, Vector3.new(spot.centre.X, root.Position.Y, spot.centre.Z))
	-- every button nearby steps aside (a "Talk" under the card would take E from Reel in)
	ProximityPromptService.Enabled = false
	card.Visible = true
	task.spawn(cast)
end

function Fishing.isFishing(): boolean
	return mine ~= nil
end

---------------------------------------------------------------- the card

local function makeCard()
	local gui = Ui.screen("Fishing", 7) -- over the HUD; under the Fish Book and other screens
	card = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(CARD.X, CARD.Y),
		BackgroundColor3 = Ui.colors.paper,
		Visible = false,
		Parent = gui,
	}, { Ui.corner(20), Ui.stroke(3) })
	local scale = Ui.new("UIScale", { Parent = card })
	message = Ui.text({
		Text = "",
		TextSize = 18,
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.fromOffset(CARD.X - 28, 46),
		Parent = card,
	})
	-- three buttons along the bottom, each with its controller button's picture in its corner
	local pads: { ImageLabel } = {}
	local function addButton(text: string, color: Color3, x: number, wide: number, key: Enum.KeyCode, onClick: () -> ()): TextButton
		local button = Ui.button(text, color, onClick, {
			Position = UDim2.fromOffset(x, 60),
			Size = UDim2.fromOffset(wide, 60),
			TextSize = 22,
			Selectable = false, -- a controller uses its own buttons (A, Y, D-pad down)
			Parent = card,
		})
		table.insert(pads, Ui.new("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(4, 4),
			Size = UDim2.fromOffset(28, 28),
			BackgroundTransparency = 1,
			Image = Ui.padImage(key),
			Parent = button,
		}))
		return button
	end
	reelButton = addButton("Reel in!", Ui.colors.yellow, 14, 176, Enum.KeyCode.ButtonA, reel)
	addButton("Fish book", Ui.colors.cream, 202, 116, Enum.KeyCode.ButtonY, function()
		FishBook.open()
	end)
	addButton("All done", Ui.colors.cream, 330, 116, Enum.KeyCode.DPadDown, Fishing.stop)
	local function showPads()
		for _, pad in pads do
			pad.Visible = Ui.usingController() and pad.Image ~= ""
		end
	end
	UserInputService.LastInputTypeChanged:Connect(showPads)
	showPads()

	-- Along the bottom in the middle, kept in from the edges on a TV. Never smaller than a
	-- finger needs, and never so tall it hides your animal.
	local function place()
		local size = gui.AbsoluteSize
		if size.X <= 0 then
			return
		end
		if Ui.CONSOLE then
			scale.Scale = Config.UI.CONSOLE_SCALE
			card.Position = UDim2.fromScale(0.5, 1 - Config.UI.TV_SAFE)
			return
		end
		-- (no need to keep clear of the thumbstick or jump button: both are put away while you fish)
		local wide = (size.X - 32) / CARD.X
		local tall = size.Y * CARD_TALL / CARD.Y
		scale.Scale = math.clamp(math.min(wide, tall), Ui.TOUCH / 60, CARD_MOST)
		card.Position = UDim2.new(0.5, 0, 1, -Config.UI.PROMPT_BOTTOM)
	end
	place()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
end

---------------------------------------------------------------- starting

function Fishing.start()
	folder = Instance.new("Folder")
	folder.Name = "Fishing"
	folder.Parent = Workspace
	makeCard()

	-- a "Go fishing" button by each pond, reaching just past its edge
	for i, pond in Config.FISHING_PONDS do
		local spot = Ui.new("Part", {
			Name = "FishingSpot",
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			Transparency = 1,
			Size = Vector3.new(2, 2, 2),
			CFrame = CFrame.new(pond.centre + Vector3.new(0, 3, 0)),
			Parent = folder,
		})
		local button = Ui.new("ProximityPrompt", {
			Name = "Fishing",
			ActionText = "Go fishing",
			ObjectText = pond.name,
			HoldDuration = 0,
			MaxActivationDistance = (pond.r + F.REACH) * S,
			RequiresLineOfSight = false,
			Style = Enum.ProximityPromptStyle.Custom, -- shown at the bottom of the screen (client/Prompts)
			Parent = spot,
		})
		button:SetAttribute("Pond", i)
	end
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local pond = prompt:GetAttribute("Pond")
		if prompt.Name == "Fishing" and typeof(pond) == "number" then
			begin(pond)
		end
	end)

	-- everyone's rods and bobbers
	for _, who in Players:GetPlayers() do
		task.spawn(watchGear, who)
	end
	Players.PlayerAdded:Connect(watchGear)
	Players.PlayerRemoving:Connect(function(who)
		clearGear(who)
		if arriving[who] then
			arriving[who]:Disconnect()
			arriving[who] = nil
		end
	end)

	-- a new animal, or the HUD going (the welcome screen), puts the rod away
	player.CharacterAdded:Connect(function()
		Fishing.stop()
	end)
	local hud = Hud.gui()
	if hud then
		hud:GetPropertyChangedSignal("Enabled"):Connect(function()
			if not hud.Enabled then
				Fishing.stop()
			end
		end)
	end

	-- A reels in, Y opens the book, D-pad down is All done (B is kept for closing the book and
	-- the emotes); Space or E reel in on a keyboard. (Not while
	-- another screen is open, the menu is up, or the ring is on a button.)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not mine or Ui.openScreens > 0 or GuiService.MenuIsOpen or GuiService.SelectedObject ~= nil then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.ButtonA or ((key == Enum.KeyCode.Space or key == Enum.KeyCode.E) and not processed) then
			reel()
		elseif key == Enum.KeyCode.ButtonY then
			FishBook.open()
		elseif key == Enum.KeyCode.DPadDown then
			Fishing.stop()
		end
	end)
end

return Fishing
