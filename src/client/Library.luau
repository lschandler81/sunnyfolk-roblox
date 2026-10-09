-- The Library, on each player's screen. "Go in" at the library on the south lawn fades you
-- into the library hall, far from town (server/Town builds it; it's much bigger inside, like
-- your house), and "Go outside" by its door brings you back. There you help Pebble tidy the
-- shelves:
--
--   * "Help Pebble" at Pebble's desk (a sign hangs over it) starts a round (server/Library makes
--     it). While you're helping, a "Stop tidying" button sits above the emote button (D-pad up
--     on a controller), and Pebble's own Talk button steps aside. Going outside stops it too.
--     Your books stand on the cart, and the bookcases the round uses get a sign: a colour with
--     its own white symbol (heart, moon, diamond, spot), so it works without seeing colours,
--     and in later rounds a tall or short book outline. These, and all the buttons here, are made on your
--     screen only, so everyone in the library can tidy their own books at once.
--   * "Pick up" by the cart (the nearest book) puts it over your animal's head; everyone sees
--     books being carried (each player's LibraryCarry attribute). "Put away" at a bookcase puts
--     it on the shelf if it belongs there, and Pebble says thank you; if not, it hops back onto
--     the cart. Nothing fails and there's no timer. With the last book, Pebble cheers and a
--     stamp goes on your library card. Stamps unlock the picture stories.
--   * "Read" in the story corner (under its sign) opens the Story corner screen: the stories
--     (shared/Stories) on two shelves, each with its own coloured cover, and the ones you've
--     unlocked open as a picture book: a big emoji picture on the left page and a line or two
--     on the right, with a friendly question at the end, answered by tapping a picture.
--   * While you're in the hall, the roof and any wall between you and the camera fade, like
--     inside your house.
--
-- The hall's buttons use F (Y on a controller), so they never clash with talking to Pebble (E).
-- The doors use E (X), like your house's; only the nearest E button shows (Pebble's Talk, or
-- "Go outside"), so one press never does both.

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Build = require(Shared.Build)
local Config = require(Shared.Config)
local Stories = require(Shared.Stories)
local Animator = require(script.Parent.Animator)
local Controls = require(script.Parent.Controls)
local Hud = require(script.Parent.Hud)
local Talk = require(script.Parent.Talk)
local Ui = require(script.Parent.Ui)

local Remotes = Shared:WaitForChild("Remotes")
local player = Players.LocalPlayer

local L = Config.LIBRARY
local S = Config.STUDS
local BOOK = L.BOOK
local WIDE, HIGH = 620, 290 -- the Stories card, laid out for a landscape phone
local TOP = 56 -- where its header ends
local CARRY_HEIGHT = 4.2 -- studs over an animal's middle, for the book it carries (like the Cafe's dishes)
local SIGN_PIXELS = 40 -- pixels per stud on the signs and books
local SEE_THROUGH = Config.ROOM.CUTAWAY -- how walls fade (the same as inside your house)
local RESIDENT_TAG = "SunnyfolkResident" -- server/Residents tags each resident with this
local EMOTE_BUTTON = 56 -- the emote button's size (client/Emotes), so Stop tidying sits just above it
local RIGHT = { "Thank you!", "Just right!", "Lovely!", "That's the one!" } -- Pebble, when a book goes on the right shelf
local HINTS = {
	colour = "Can you put each book on the shelf with its colour?",
	size = "Tall books on one shelf, short books on the other!",
	both = "Look at the colour and the size!",
}

local Library = {}

local screen: ScreenGui? = nil
local random = Random.new()

-- The round you're on, as the server made it ({ kind, shelves, books }), or nil; which shelf
-- each tidied book is on; and the book in your paws.
local round: any = nil
local placed: { [number]: number } = {}
local carrying: number? = nil
local finished = false -- every book is tidied (they stay on the shelves until the next round)
local stamping = false -- waiting for the round's stamp
local busy = false -- asking the server something
local mine: Folder? = nil -- your books, signs and buttons (only on your screen)
local going = false -- going through a door
local fadeFrame: Frame? = nil
local stopButton: GuiObject? = nil
local padHint: ImageLabel? = nil
local stop: () -> () -- (below)

-- In the middle of a round (not finished yet)?
local function tidying(): boolean
	return round ~= nil and not finished
end

-- Your library card, as the server last said (PlayerData's Library attribute).
local function myCard(): { stamps: number, stories: number, read: { string } }
	local card = { stamps = 0, stories = 0, read = {} }
	local saved = player:GetAttribute("Library")
	if typeof(saved) == "string" then
		local ok, data = pcall(function()
			return HttpService:JSONDecode(saved)
		end)
		if ok and typeof(data) == "table" then
			card.stamps = if typeof(data.stamps) == "number" then data.stamps else 0
			card.stories = if typeof(data.stories) == "number" then data.stories else 0
			card.read = if typeof(data.read) == "table" then data.read else {}
		end
	end
	return card
end

local function colourOf(i: number): Color3
	local each = L.BOOK_COLORS[i]
	return if each then Color3.fromHex(each.color) else Ui.colors.grey
end

local function symbolOf(i: number): string
	local each = L.BOOK_COLORS[i]
	return if each then each.symbol else "spot"
end

---------------------------------------------------------------- drawing

-- A white symbol, `size` pixels square, centred at `at` in `parent`, drawn from a few frames so
-- it shows the same everywhere: a heart, a moon, a diamond or a spot. `back` is the colour
-- behind it (the moon is a circle with a bite taken out in that colour).
local function symbol(kind: string, back: Color3, size: number, parent: Instance, at: UDim2)
	local holder = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = at,
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local function piece(x: number, y: number, s: number, rotation: number, color: Color3, round: boolean, z: number?)
		Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(x, y),
			Size = UDim2.fromScale(s, s),
			Rotation = rotation,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = z or 1,
			Parent = holder,
		}, if round then { Ui.round() } else nil)
	end
	local white = Ui.colors.paper
	if kind == "heart" then
		-- a diamond with two circles on its top edges
		piece(0.5, 0.58, 0.5, 45, white, false)
		piece(0.323, 0.403, 0.5, 0, white, true)
		piece(0.677, 0.403, 0.5, 0, white, true)
	elseif kind == "moon" then
		piece(0.5, 0.5, 0.84, 0, white, true)
		piece(0.7, 0.36, 0.7, 0, back, true, 2)
	elseif kind == "diamond" then
		piece(0.5, 0.5, 0.64, 45, white, false)
	else
		piece(0.5, 0.5, 0.72, 0, white, true)
	end
end

-- The outline of a tall or short book, for a shelf that sorts by size. `k` scales it.
local function sizeIcon(size: string, color: Color3, k: number, parent: Instance)
	local holder = Ui.new("Frame", { Size = UDim2.fromOffset(16 * k, 26 * k), BackgroundTransparency = 1, Parent = parent })
	Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -k),
		Size = UDim2.fromOffset(11 * k, (if size == "tall" then 23 else 13) * k),
		BackgroundTransparency = 1,
		Parent = holder,
	}, { Ui.corner(2 * k), Ui.stroke(2.5 * k, color) })
end

-- Writing and pictures on one face of a part.
local function face(part: BasePart, side: Enum.NormalId): SurfaceGui
	return Ui.new("SurfaceGui", {
		Face = side,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = SIGN_PIXELS,
		LightInfluence = 0,
		Parent = part,
	})
end

-- A book, standing on `at` (its bottom middle), with its spine (two pale bands and its symbol)
-- facing both ways along `at`'s Z.
local function bookPart(book: { color: number, size: string }, at: CFrame): BasePart
	local high = (if book.size == "short" then BOOK.short else BOOK.tall) * S
	local color = colourOf(book.color)
	local part = Instance.new("Part")
	part.Size = Vector3.new(BOOK.thick * S, high, BOOK.deep * S)
	part.CFrame = at * CFrame.new(0, high / 2, 0)
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	for _, side in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = face(part, side)
		for _, y in { 0.1, 0.9 } do
			Ui.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, y),
				Size = UDim2.new(1, 0, 0, 5),
				BackgroundColor3 = Ui.colors.paper,
				BackgroundTransparency = 0.35,
				BorderSizePixel = 0,
				Parent = gui,
			})
		end
		symbol(symbolOf(book.color), color, BOOK.thick * S * SIGN_PIXELS * 0.8, gui, UDim2.fromScale(0.5, 0.5))
	end
	return part
end

-- An invisible spot for a button.
local function spot(at: CFrame, folder: Instance): BasePart
	Build.into(folder)
	return Build.block(Vector3.one, at, Color3.new(1, 1, 1), { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
end

-- A button (shown at the bottom of the screen by client/Prompts).
local function button(parent: Instance, name: string, action: string, object: string): ProximityPrompt
	return Ui.new("ProximityPrompt", {
		Name = name,
		ActionText = action,
		ObjectText = object,
		KeyboardKeyCode = Enum.KeyCode.F,
		GamepadKeyCode = Enum.KeyCode.ButtonY,
		HoldDuration = 0,
		MaxActivationDistance = L.BUTTON_REACH,
		RequiresLineOfSight = false,
		-- (only the nearest library button shows: the book you're closest to, say)
		Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton,
		Style = Enum.ProximityPromptStyle.Custom,
		Parent = parent,
	})
end

-- Drops `part` into place from a little above it.
local function drop(part: BasePart, from: number)
	local rest = part.CFrame
	part.CFrame = rest * CFrame.new(0, from, 0)
	TweenService:Create(part, TweenInfo.new(0.35, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), { CFrame = rest }):Play()
end

-- Where the `j`th of `count` books stands on bookcase `k`'s middle shelf.
local function onShelf(k: number, j: number, count: number): CFrame
	return Config.libraryCase(k) * CFrame.new((j - (count + 1) / 2) * 0.75 * S, L.SHELF_Y * S, 0.05 * S)
end

-- Draws your books, the signs on the bookcases and the buttons, from scratch. `fresh` is a book
-- just put on a shelf (it drops into place); `back` is one that just hopped back to the cart.
local function draw(fresh: number?, back: number?)
	if mine then
		mine:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "MyLibrary"
	mine = folder

	-- the reading corner's button, and the door's, always
	-- (in the middle of the rug in front of the armchair, so it shows wherever you stand on it)
	local read = button(spot(Config.libraryChair() * CFrame.new(0, S, 1.8 * S), folder), "LibraryRead", "Read", "Story corner")
	read.MaxActivationDistance = L.READ_REACH
	local out = button(spot(Config.libraryHallDoor() * CFrame.new(0, S, 0.8 * S), folder), "LibraryOut", "Go outside", "")
	out.KeyboardKeyCode = Enum.KeyCode.E
	out.GamepadKeyCode = Enum.KeyCode.ButtonX

	-- the desk's button, when there's no round going
	if (not round or finished) and not stamping then
		button(spot(Config.libraryAt(L.DESK.x, L.DESK.z) * CFrame.new(0, L.DESK_SIZE.Y * S, 0), folder), "LibraryStart", "Help Pebble", "Pebble's desk")
	end

	if round then
		-- the signs on the bookcases this round uses
		for s, shelf in round.shelves do
			local k = shelf.case
			if not L.CASES[k] then
				continue
			end
			Build.into(folder)
			local board = Build.block(
				Vector3.new(2.6, 0.8, 0.1) * S,
				Config.libraryCase(k) * CFrame.new(0, (L.CASE.Y + 0.42) * S, (L.CASE.Z / 2 - 0.15) * S),
				Ui.colors.cream,
				{ CanCollide = false, CanQuery = false, CanTouch = false }
			)
			board.Name = `Sign{s}`
			local gui = face(board, Enum.NormalId.Back) -- (its back faces into the room)
			local back = if shelf.color then colourOf(shelf.color) else Ui.colors.creamDeep
			Ui.new("Frame", {
				Position = UDim2.fromOffset(6, 6),
				Size = UDim2.new(1, -12, 1, -12),
				BackgroundColor3 = back,
				Parent = gui,
			}, {
				Ui.corner(14),
				Ui.stroke(4),
				Ui.new("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 18),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			})
			local row = gui:FindFirstChildOfClass("Frame") :: Frame
			if shelf.color then
				local mark = Ui.new("Frame", { Size = UDim2.fromOffset(62, 62), BackgroundTransparency = 1, LayoutOrder = 1, Parent = row })
				symbol(symbolOf(shelf.color), back, 62, mark, UDim2.fromScale(0.5, 0.5))
			end
			if shelf.size then
				sizeIcon(shelf.size, if shelf.color then Ui.colors.paper else Ui.colors.ink, 2.4, row)
			end
			-- and its button, while you're carrying a book
			if carrying and not finished then
				local put = button(spot(CFrame.new(Config.libraryCaseFront(k) + Vector3.new(0, 1.2 * S, 0)), folder), "LibraryPut", "Put away", "")
				put:SetAttribute("Case", k)
			end
		end

		-- the books: on their shelves, or on the cart
		local onEach: { [number]: { number } } = {}
		for i = 1, #round.books do
			local s = placed[i]
			local shelf = s and round.shelves[s]
			if shelf then
				onEach[shelf.case] = onEach[shelf.case] or {}
				table.insert(onEach[shelf.case], i)
			end
		end
		for k, books in onEach do
			for j, i in books do
				local part = bookPart(round.books[i], onShelf(k, j, #books))
				part.Parent = folder
				if i == fresh then
					drop(part, 1.5 * S)
				end
			end
		end
		for i, book in round.books do
			if not placed[i] and i ~= carrying then
				local part = bookPart(book, Config.libraryCartSlot(i, #round.books))
				part.Parent = folder
				if not carrying and not finished then
					local pick = button(part, "LibraryPick", "Pick up", "")
					pick:SetAttribute("Book", i)
				end
				if i == back then
					drop(part, 2.5 * S)
				end
			end
		end
	end
	folder.Parent = Workspace

	-- while you're helping: Stop tidying, and Pebble's Talk button steps aside
	local helping = tidying()
	local hud = Hud.gui()
	if helping and not stopButton and hud then
		-- (on a TV it's sized up by hand, like the Cafe's End shift)
		local k = if Ui.CONSOLE then Config.UI.CONSOLE_SCALE else 1
		local gap = EMOTE_BUTTON / 2 * k + 10
		local made = Ui.button("Stop tidying", Ui.colors.cream, function()
			stop()
		end, {
			AnchorPoint = Vector2.new(1, 1),
			Position = if Ui.CONSOLE then UDim2.new(1 - Config.UI.TV_SAFE, 0, 0.55, -gap) else UDim2.new(1, -16, 0.55, -gap),
			Size = UDim2.fromOffset(140 * k, Ui.TOUCH * k),
			TextSize = math.round(18 * k),
			Selectable = false, -- a controller uses D-pad up instead
			Parent = hud,
		})
		padHint = Ui.new("ImageLabel", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(0, -6, 0.5, 0),
			Size = UDim2.fromOffset(32 * k, 32 * k),
			BackgroundTransparency = 1,
			Image = Ui.padImage(Enum.KeyCode.DPadUp),
			Visible = Ui.usingController(),
			Parent = made,
		})
		stopButton = made
	end
	if stopButton then
		stopButton.Visible = helping
	end
	for _, model in CollectionService:GetTagged(RESIDENT_TAG) do
		if model:GetAttribute("ResidentId") == "pebble" then
			for _, thing in model:GetDescendants() do
				if thing:IsA("ProximityPrompt") then
					thing.Enabled = not helping
				end
			end
		end
	end
end

---------------------------------------------------------------- books being carried

-- The book over an animal's head (their LibraryCarry attribute: "colour:size"), welded on so
-- it moves with them for free.
local function showCarry(who: Player)
	local character = who.Character
	local old = character and character:FindFirstChild("LibraryCarry")
	if old then
		old:Destroy()
	end
	local value = who:GetAttribute("LibraryCarry")
	local root = character and character.PrimaryPart
	if not (character and root and typeof(value) == "string") then
		return
	end
	local colour, size = string.match(value, "^(%d+):(%a+)$")
	local book = { color = tonumber(colour) or 0, size = size or "" }
	if not (L.BOOK_COLORS[book.color] and (book.size == "tall" or book.size == "short")) then
		return
	end
	local part = bookPart(book, root.CFrame * CFrame.new(0, CARRY_HEIGHT, 0))
	part.Name = "LibraryCarry"
	part.Anchored = false
	part.Massless = true
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part
	part.Parent = character
end

local function watchCarry(who: Player)
	who:GetAttributeChangedSignal("LibraryCarry"):Connect(function()
		showCarry(who)
	end)
	who.CharacterAdded:Connect(function(character)
		character:WaitForChild("HumanoidRootPart", 10)
		showCarry(who)
	end)
	showCarry(who)
end

---------------------------------------------------------------- tidying

-- Pebble says something in a bubble over Pebble's head (or, if Pebble isn't about, in a
-- message). Returns Pebble's model, if Pebble's here.
local function pebbleSays(text: string): Model?
	local pebble = Talk.residentSays("pebble", text)
	if not pebble then
		Hud.toast(text)
	end
	return pebble
end

-- Asks the server. Returns whether it answered, then what it said.
local function ask(...: any): (boolean, any, any, any, any, any)
	local args = table.pack(...)
	local result = table.pack(pcall(function()
		return Remotes.LibraryAction:InvokeServer(table.unpack(args, 1, args.n))
	end))
	return result[1], result[2], result[3], result[4], result[5], result[6]
end

-- The round's stamp has arrived: Pebble cheers.
local function celebrate(coins: any, story: any)
	local pebble = pebbleSays("Hooray! All tidy! Thank you!")
	if pebble then
		Animator.emote(pebble, "cheer")
	end
	local small = if typeof(coins) == "number" and coins > 0
		then `+{coins} coins and a stamp on your library card`
		else "A stamp on your library card"
	if typeof(story) == "number" and Stories.LIST[story] then
		small ..= ". A new story is waiting in the cosy corner!"
	end
	Hud.announce("All tidy!", small)
end

-- Stops helping part way through a round (the Stop tidying button).
stop = function()
	if busy or not tidying() then
		return
	end
	busy = true
	local ok, done, message = ask("stop")
	busy = false
	if not (ok and done) then
		Hud.toast(if ok and typeof(message) == "string" then message else "Something went wrong. Try again!")
		return
	end
	round, placed, carrying, finished = nil, {}, nil, false
	draw()
	pebbleSays("Thank you for helping! Come back to my desk any time.")
end

-- A round finished quicker than the server allows: wait, then ask for its stamp.
local function waitForStamp(seconds: number)
	stamping = true
	draw()
	pebbleSays("Hooray! Let me stamp your library card...")
	task.wait(math.min(seconds, L.MIN_ROUND) + 0.2)
	local ok, done, coins, story = false, false, nil, nil
	for _ = 1, 3 do
		ok, done, coins, story = ask("stamp")
		if ok and not done and coins == "wait" and typeof(story) == "number" then
			task.wait(math.min(story, L.MIN_ROUND) + 0.2)
		else
			break
		end
	end
	stamping = false
	if ok and done then
		celebrate(coins, story)
	end
	draw()
end

local function start()
	if busy or stamping then
		return
	end
	busy = true
	local ok, done, data, lastCoins, lastStory = ask("start")
	busy = false
	if not (ok and done and typeof(data) == "table" and typeof(data.shelves) == "table" and typeof(data.books) == "table") then
		pebbleSays(if ok and typeof(data) == "string" then data else "Something went wrong. Try again!")
		return
	end
	round, placed, carrying, finished = data, {}, nil, false
	draw()
	if typeof(lastCoins) == "number" then
		-- (the last round's stamp, which was still waiting)
		celebrate(lastCoins, lastStory)
	end
	pebbleSays(HINTS[round.kind] or HINTS.colour)
end

local function pick(i: any)
	if busy or not round or finished or carrying or typeof(i) ~= "number" then
		return
	end
	busy = true
	local ok, done, message = ask("pick", i)
	busy = false
	if ok and done then
		carrying = i
		draw()
	elseif ok and typeof(message) == "string" then
		pebbleSays(message)
	end
end

local function put(k: any)
	local i = carrying
	if busy or not round or not i or typeof(k) ~= "number" then
		return
	end
	busy = true
	local ok, done, result, s, a, b = ask("put", k)
	busy = false
	if not (ok and done) then
		if ok and typeof(result) == "string" then
			pebbleSays(result)
		end
		-- (the server had put it back already: say the animal was changed)
		if player:GetAttribute("LibraryCarry") == nil then
			carrying = nil
			draw()
		end
		return
	end
	carrying = nil
	if result == "back" then
		draw(nil, i)
		pebbleSays("Not that shelf. Try another!")
		return
	end
	if typeof(s) == "number" then
		placed[i] = s
	end
	if result == "placed" then
		draw(i)
		pebbleSays(RIGHT[random:NextInteger(1, #RIGHT)])
	elseif result == "wait" then
		finished = true
		draw(i)
		waitForStamp(if typeof(a) == "number" then a else L.MIN_ROUND)
	elseif result == "done" then
		finished = true
		draw(i)
		celebrate(a, b)
	end
end

---------------------------------------------------------------- going in and out

-- Fades the screen to dark (and waits for it), or back again (like going into your house).
local function fade(dark: boolean)
	if not fadeFrame then
		local gui = Ui.screen("LibraryFade", 40) -- over everything
		gui.ScreenInsets = Enum.ScreenInsets.None
		fadeFrame = Ui.new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Ui.colors.ink,
			BackgroundTransparency = 1,
			Parent = gui,
		})
	end
	local tween = TweenService:Create(fadeFrame :: Frame, TweenInfo.new(Config.ROOM.FADE_SECONDS), {
		BackgroundTransparency = if dark then 0 else 1,
	})
	tween:Play()
	if dark then
		tween.Completed:Wait()
	end
end

-- Asks the server to take you into the hall ("enter") or back out ("leave"), with the screen
-- dark meanwhile.
local function goThrough(what: string)
	if going or busy then
		return
	end
	going = true
	fade(true)
	local ok, done, why = ask(what)
	task.wait(0.1) -- (a moment for your animal to arrive)
	-- the camera back behind your animal, so forward is into the hall (or away from the door)
	local root = player.Character and player.Character.PrimaryPart
	local camera = Workspace.CurrentCamera
	if ok and done and root and camera then
		local back = Config.ROOM.CAMERA_BEHIND
		camera.CFrame = CFrame.lookAt((root.CFrame * CFrame.new(0, back.height, back.distance)).Position, root.Position)
	end
	fade(false)
	going = false
	if ok and done and what == "leave" and tidying() then
		-- (going outside stops a round part way through: the server has put it away)
		round, placed, carrying, finished = nil, {}, nil, false
		draw()
	elseif ok and done and what == "enter" then
		local card = myCard()
		pebbleSays(if card.stamps == 0
			then `Hello, {player.DisplayName}! Can you help me tidy the books? Come to my desk!`
			else `Welcome back, {player.DisplayName}!`)
	elseif not (ok and done) then
		Hud.toast(if ok and typeof(why) == "string" then why else "Something went wrong.")
	end
end

---------------------------------------------------------------- seeing in

-- A few times a second while you're in the hall: any wall between your animal and the camera
-- (looking that way as far as Config.ROOM.CUTAWAY.REACH) fades, so Roblox's camera stays back
-- and looks in. They come back when you go out.
local function seeThrough()
	local faded: { [Instance]: boolean } = {}
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local function setFade(thing: Instance, amount: number)
		for _, part in thing:GetDescendants() do
			if part:IsA("BasePart") then
				part.LocalTransparencyModifier = amount
			end
		end
	end
	while true do
		local root = player.Character and player.Character.PrimaryPart
		local building = Workspace:FindFirstChild("LibraryHall")
		local inside = root ~= nil and building ~= nil and Config.libraryInside(root.Position)
		-- out of the hall some other way (back to the fountain, say) part way through a round:
		-- the server puts it away, so it goes here too
		if root and not inside and tidying() and not busy and not going then
			round, placed, carrying, finished = nil, {}, nil, false
			draw()
		end

		local inWay: { [Instance]: boolean } = {}
		local shell = building and building:FindFirstChild("Shell")
		local camera = Workspace.CurrentCamera
		if inside and shell and camera then
			local from = camera.Focus.Position
			local away = camera.CFrame.Position - from
			local left = shell:GetChildren()
			for _ = 1, 3 do
				if away.Magnitude < 0.1 or #left == 0 then
					break
				end
				params.FilterDescendantsInstances = left
				local hit = Workspace:Raycast(from, away.Unit * SEE_THROUGH.REACH, params)
				local wall = hit and hit.Instance.Parent
				if not (wall and (wall.Name == "Wall" or wall.Name == "Roof")) then
					break
				end
				inWay[wall] = true
				table.remove(left, table.find(left, wall))
			end
		end
		for wall in faded do
			if not inWay[wall] then
				faded[wall] = nil
				setFade(wall, 0)
			end
		end
		for wall in inWay do
			if not faded[wall] then
				faded[wall] = true
				setFade(wall, SEE_THROUGH.FADE)
			end
		end
		task.wait(if inside then SEE_THROUGH.SECONDS else 0.5)
	end
end

---------------------------------------------------------------- the Story corner screen

-- A colour a little darker (a book's spine, the fold between its pages).
local function darker(color: Color3, by: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), by)
end

-- Little yellow stars flying out from the middle of `object`, fading as they go (like the Fish
-- Book's).
local function burst(object: GuiObject)
	for i = 1, 10 do
		local a = i / 10 * math.pi * 2
		local star = Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.4),
			Size = UDim2.fromOffset(14, 14),
			Rotation = 45,
			BackgroundColor3 = Ui.colors.yellow,
			ZIndex = 5,
			Parent = object,
		}, { Ui.stroke(2, Ui.colors.coral) })
		TweenService:Create(star, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, math.cos(a) * 130, 0.4, math.sin(a) * 80),
			Rotation = 225,
			BackgroundTransparency = 1,
		}):Play()
		task.delay(0.9, function()
			star:Destroy()
		end)
	end
end

function Library.open()
	if screen or Ui.openScreens > 0 then
		return
	end
	Controls.set(false, "library")
	local gui = Ui.screen("Library", 15)
	screen = gui
	local card = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(WIDE, HIGH),
		BackgroundColor3 = Ui.colors.paper,
		Parent = gui,
	}, { Ui.corner(22), Ui.stroke(3) })
	Ui.fitToScreen(card, WIDE, HIGH)
	local body = Ui.new("Frame", {
		Position = UDim2.fromOffset(0, TOP),
		Size = UDim2.fromOffset(WIDE, HIGH - TOP),
		BackgroundTransparency = 1,
		Parent = card,
	})

	local view = "stories" -- "stories" or "reading"
	local token = 0 -- goes up each time the page changes, so answers for an old page are ignored

	local function close()
		gui:Destroy()
		screen = nil
		Controls.set(true, "library")
	end

	local function focus(object: GuiObject?)
		if object and object.Parent and Ui.usingController() then
			GuiService.SelectedObject = object
		end
	end

	local function clearBody()
		token += 1
		body:ClearAllChildren()
	end

	local function wobble(object: GuiObject)
		task.spawn(function()
			for _, r in { -9, 9, -6, 6, 0 } do
				TweenService:Create(object, TweenInfo.new(0.06), { Rotation = r }):Play()
				task.wait(0.06)
			end
		end)
	end

	local function pop(object: GuiObject, from: number)
		local scale = object:FindFirstChildOfClass("UIScale") or Ui.new("UIScale", { Parent = object })
		scale.Scale = from
		TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end

	-- the header: the title, your library card, and Bye!
	Ui.text({
		Text = "📖 Story corner",
		TextSize = 21,
		TextColor3 = Ui.colors.coral,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		Position = UDim2.fromOffset(16, 6),
		Size = UDim2.fromOffset(176, Ui.TOUCH),
		Parent = card,
	})
	local closeButton = Ui.button("Bye!", Ui.colors.cream, close, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 6),
		Size = UDim2.fromOffset(84, Ui.TOUCH),
		TextSize = 20,
		Parent = card,
	})
	-- the library card: a stamp for each round, and how many more until the next story
	local stampCard = Ui.new("Frame", {
		Position = UDim2.fromOffset(196, 6),
		Size = UDim2.fromOffset(318, Ui.TOUCH),
		BackgroundColor3 = Ui.colors.cream,
		Parent = card,
	}, {
		Ui.corner(14),
		Ui.stroke(3),
		Ui.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	do
		local mineCard = myCard()
		Ui.text({ Text = "Library card", TextSize = 15, TextColor3 = Ui.colors.teal, AutomaticSize = Enum.AutomaticSize.X, TextWrapped = false, Size = UDim2.fromOffset(0, 30), LayoutOrder = 1, Parent = stampCard })
		if mineCard.stories >= #Stories.LIST then
			Ui.text({ Text = "Every story is open!", TextSize = 15, AutomaticSize = Enum.AutomaticSize.X, TextWrapped = false, Size = UDim2.fromOffset(0, 30), LayoutOrder = 2, Parent = stampCard })
		else
			local from = if mineCard.stories == 0 then 0 else Stories.stampsFor(mineCard.stories)
			local slots = Stories.stampsFor(mineCard.stories + 1) - from
			local filled = math.clamp(mineCard.stamps - from, 0, slots)
			for i = 1, slots do
				local got = i <= filled
				local stamp = Ui.new("Frame", {
					Size = UDim2.fromOffset(26, 26),
					BackgroundColor3 = if got then Ui.colors.coral else Ui.colors.paper,
					LayoutOrder = 1 + i,
					Parent = stampCard,
				}, { Ui.round(), Ui.stroke(2.5, if got then Ui.colors.ink else Ui.colors.grey) })
				if got then
					symbol("heart", Ui.colors.coral, 16, stamp, UDim2.fromScale(0.5, 0.5))
				end
			end
			-- then the story they'll unlock
			Ui.text({ Text = "📖", TextSize = 24, Size = UDim2.fromOffset(30, 30), LayoutOrder = slots + 2, Parent = stampCard })
		end
	end

	local showStories: () -> ()
	local readStory: (number) -> ()

	-- The Story corner: the stories on two shelves of four, each a book with its own coloured
	-- cover, its picture in a round window and its title. One you haven't unlocked is grey with
	-- a lock (and the next shows how many more stamps it needs); one you've read has a gold star,
	-- and one you haven't yet says "New!".
	showStories = function()
		clearBody()
		view = "stories"
		local mineCard = myCard()
		for row = 0, 1 do
			Ui.new("Frame", {
				Position = UDim2.fromOffset(18, row * 114 + 100),
				Size = UDim2.fromOffset(WIDE - 36, 10),
				BackgroundColor3 = Color3.fromHex("#b57b4a"),
				BorderSizePixel = 0,
				Parent = body,
			}, { Ui.corner(4), Ui.stroke(2) })
		end
		local first: GuiObject? = nil
		for i, story in Stories.LIST do
			local row, col = (i - 1) // 4, (i - 1) % 4
			local open = i <= mineCard.stories
			local read = table.find(mineCard.read, story.id) ~= nil
			local cover = if open then Color3.fromHex(story.color) else Color3.fromHex("#cfc6b8")
			local tile: TextButton
			tile = Ui.button("", cover, function()
				if open then
					readStory(i)
				else
					wobble(tile)
				end
			end, {
				Position = UDim2.fromOffset(30 + col * 144, row * 114 + 2),
				Size = UDim2.fromOffset(128, 98),
				Parent = body,
			})
			first = first or (if open then tile else nil)
			-- two ridges down its spine
			for _, x in { 9, 16 } do
				Ui.new("Frame", {
					Position = UDim2.fromOffset(x, 7),
					Size = UDim2.new(0, 3, 1, -14),
					BackgroundColor3 = darker(cover, 0.25),
					BorderSizePixel = 0,
					Parent = tile,
				})
			end
			-- its picture, in a round window
			local window = Ui.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 8, 0, 6),
				Size = UDim2.fromOffset(50, 50),
				BackgroundColor3 = Ui.colors.paper,
				Parent = tile,
			}, { Ui.round(), Ui.stroke(2.5, darker(cover, 0.35)) })
			Ui.text({ Text = if open then story.cover else "🔒", TextSize = 30, Size = UDim2.fromScale(1, 1), Parent = window })
			-- its title (or, for the next to open, the stamps it needs) on a cream band
			local words = story.title
			if not open then
				local more = Stories.stampsFor(i) - mineCard.stamps
				words = if i == mineCard.stories + 1 then `{more} more {if more == 1 then "stamp" else "stamps"}` else ""
			end
			if words ~= "" then
				local band = Ui.new("Frame", {
					Position = UDim2.fromOffset(24, 60),
					Size = UDim2.new(1, -30, 0, 32),
					BackgroundColor3 = Ui.colors.paper,
					Parent = tile,
				}, { Ui.corner(8) })
				Ui.text({
					Text = words,
					TextScaled = true,
					TextColor3 = if open then Ui.colors.ink else Ui.colors.teal,
					Size = UDim2.fromScale(1, 1),
					Parent = band,
				})
				local label = band:FindFirstChildOfClass("TextLabel") :: TextLabel
				Ui.padding(3).Parent = label
				Ui.new("UITextSizeConstraint", { MinTextSize = 9, MaxTextSize = 14, Parent = label })
			end
			-- a gold star once you've read it, or "New!" until you have
			if read then
				Ui.text({
					Text = "⭐",
					TextSize = 24,
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, 4, 0, -6),
					Size = UDim2.fromOffset(30, 30),
					ZIndex = 3,
					Parent = tile,
				})
			elseif open then
				local tag = Ui.text({
					Text = "New!",
					TextSize = 13,
					TextColor3 = Ui.colors.paper,
					BackgroundTransparency = 0,
					BackgroundColor3 = Ui.colors.coral,
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, 6, 0, -6),
					Size = UDim2.fromOffset(42, 20),
					ZIndex = 3,
					Parent = tile,
				})
				Ui.corner(10).Parent = tag
				Ui.stroke(2).Parent = tag
			end
		end
		focus(first or closeButton)
	end

	-- Reads story number `index` as an open picture book: the picture on the left page and the
	-- words on the right, a page at a time, then its question, then a well done.
	readStory = function(index: number)
		local story = Stories.LIST[index]
		if not story then
			return
		end
		clearBody()
		view = "reading"
		local mine = token
		local page = 1
		local color = Color3.fromHex(story.color)
		-- the book: a cover in the story's colour, with its pages on it
		local book = Ui.new("Frame", {
			Position = UDim2.fromOffset(20, 0),
			Size = UDim2.fromOffset(WIDE - 40, 180),
			BackgroundColor3 = color,
			Parent = body,
		}, { Ui.corner(16), Ui.stroke(3) })
		local pages = Ui.new("CanvasGroup", {
			Position = UDim2.fromOffset(8, 8),
			Size = UDim2.new(1, -16, 1, -16),
			BackgroundTransparency = 1,
			Parent = book,
		})
		-- the buttons under the book
		local nav = Ui.new("Frame", {
			Position = UDim2.fromOffset(0, 186),
			Size = UDim2.fromOffset(WIDE, Ui.TOUCH),
			BackgroundTransparency = 1,
			Parent = body,
		})
		local pageWide = (WIDE - 56 - 6) / 2 -- (each of the two pages, with the fold between)

		local function paper(x: number, wide: number): Frame
			return Ui.new("Frame", {
				Position = UDim2.fromOffset(x, 0),
				Size = UDim2.new(0, wide, 1, 0),
				BackgroundColor3 = Ui.colors.paper,
				Parent = pages,
			}, { Ui.corner(10) })
		end
		-- the pages fade in, as if just turned
		local function turn()
			pages.GroupTransparency = 1
			TweenService:Create(pages, TweenInfo.new(0.25), { GroupTransparency = 0 }):Play()
		end
		local function navButton(text: string, color_: Color3, onClick: () -> (), x: number, wide: number, right: boolean?): TextButton
			return Ui.button(text, color_, onClick, {
				AnchorPoint = Vector2.new(if right then 1 else 0, 0),
				Position = if right then UDim2.new(1, -x, 0, 0) else UDim2.fromOffset(x, 0),
				Size = UDim2.fromOffset(wide, Ui.TOUCH),
				TextSize = 20,
				Parent = nav,
			})
		end
		local drawPage: () -> ()

		local function doneView(coins: number)
			pages:ClearAllChildren()
			nav:ClearAllChildren()
			local sheet = paper(0, WIDE - 56)
			Ui.text({ Text = "🌟📚🌟", TextSize = 44, Position = UDim2.fromOffset(0, 10), Size = UDim2.new(1, 0, 0, 54), Parent = sheet })
			Ui.text({
				Text = "The end! You read the whole story!",
				TextSize = 22,
				TextColor3 = Ui.colors.teal,
				Position = UDim2.fromOffset(10, 66),
				Size = UDim2.new(1, -20, 0, 30),
				Parent = sheet,
			})
			if coins > 0 then
				local line = Ui.new("Frame", {
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, 0, 0, 104),
					Size = UDim2.fromOffset(200, 32),
					BackgroundTransparency = 1,
					Parent = sheet,
				}, {
					Ui.new("UIListLayout", {
						FillDirection = Enum.FillDirection.Horizontal,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, 8),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
				})
				Ui.coin(26, { LayoutOrder = 1, Parent = line })
				Ui.text({ Text = `+{coins}`, TextSize = 22, AutomaticSize = Enum.AutomaticSize.X, TextWrapped = false, Size = UDim2.fromOffset(0, 32), LayoutOrder = 2, Parent = line })
				pop(line, 0.4)
			end
			turn()
			burst(book)
			local more = navButton("More stories", Ui.colors.yellow, showStories, 0, 190)
			more.AnchorPoint = Vector2.new(0.5, 0)
			more.Position = UDim2.fromScale(0.5, 0)
			focus(more)
		end

		local function questionView()
			pages:ClearAllChildren()
			nav:ClearAllChildren()
			local q = story.question
			local sheet = paper(0, WIDE - 56)
			Ui.text({ Text = `🤔 {q.ask}`, TextSize = 19, Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -20, 0, 32), Parent = sheet })
			local message = Ui.text({
				Text = "",
				TextSize = 16,
				TextColor3 = Ui.colors.teal,
				Position = UDim2.fromOffset(150, 0),
				Size = UDim2.fromOffset(WIDE - 300, Ui.TOUCH),
				Parent = nav,
			})
			local answered = false
			local firstAnswer: GuiObject? = nil
			local wide, gap = 166, 14
			local left = (WIDE - 56 - (#q.answers * wide + (#q.answers - 1) * gap)) / 2
			for j, answer in q.answers do
				local button_: TextButton
				button_ = Ui.button("", Ui.colors.cream, function()
					if answered then
						return
					end
					if j ~= q.right then
						button_.BackgroundColor3 = Ui.colors.grey
						wobble(button_)
						message.Text = "Not quite! Have another try."
						return
					end
					answered = true
					button_.BackgroundColor3 = Ui.colors.mint
					message.Text = ""
					local ok, done, coins = ask("read", story.id, j)
					if token ~= mine then
						return
					end
					if not (ok and done and typeof(coins) == "number") then
						-- (it wasn't saved: let them tap the answer again)
						answered = false
						button_.BackgroundColor3 = Ui.colors.cream
						message.Text = "Something went wrong. Tap it again!"
						return
					end
					doneView(coins)
				end, {
					Position = UDim2.fromOffset(left + (j - 1) * (wide + gap), 40),
					Size = UDim2.fromOffset(wide, 110),
					Parent = sheet,
				})
				firstAnswer = firstAnswer or button_
				Ui.text({ Text = answer.pic, TextSize = 38, Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 50), Parent = button_ })
				Ui.text({ Text = answer.text, TextSize = 15, Position = UDim2.fromOffset(6, 58), Size = UDim2.new(1, -12, 0, 46), Parent = button_ })
			end
			navButton("Back", Ui.colors.cream, function()
				page = #story.pages
				drawPage()
			end, 20, 110)
			turn()
			focus(firstAnswer)
		end

		drawPage = function()
			if page > #story.pages then
				questionView()
				return
			end
			pages:ClearAllChildren()
			nav:ClearAllChildren()
			local each = story.pages[page]
			local leftPage = paper(0, pageWide)
			local rightPage = paper(pageWide + 6, pageWide)
			-- the fold between the pages
			Ui.new("Frame", {
				Position = UDim2.fromOffset(pageWide, 4),
				Size = UDim2.new(0, 6, 1, -8),
				BackgroundColor3 = darker(color, 0.3),
				BorderSizePixel = 0,
				Parent = pages,
			}, { Ui.corner(3) })
			Ui.text({
				Text = story.title,
				TextSize = 14,
				TextColor3 = darker(color, 0.25),
				Position = UDim2.fromOffset(10, 6),
				Size = UDim2.new(1, -20, 0, 20),
				Parent = leftPage,
			})
			Ui.text({ Text = each.pic, TextSize = 54, Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 1, -34), Parent = leftPage })
			Ui.text({ Text = each.text, TextSize = 19, Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -28, 1, -34), Parent = rightPage })
			Ui.text({
				Text = `{page} / {#story.pages}`,
				TextSize = 13,
				TextColor3 = Ui.colors.grey,
				TextXAlignment = Enum.TextXAlignment.Right,
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, -10, 1, -4),
				Size = UDim2.fromOffset(70, 20),
				Parent = rightPage,
			})
			turn()
			if page > 1 then
				navButton("Back", Ui.colors.cream, function()
					page -= 1
					drawPage()
				end, 20, 110)
			end
			-- a dot for each page, the one you're on in the story's colour
			local dots = Ui.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(#story.pages * 18, 12),
				BackgroundTransparency = 1,
				Parent = nav,
			}, {
				Ui.new("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					Padding = UDim.new(0, 6),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			})
			for i = 1, #story.pages do
				Ui.new("Frame", {
					Size = UDim2.fromOffset(12, 12),
					BackgroundColor3 = if i == page then color else Ui.colors.creamDeep,
					LayoutOrder = i,
					Parent = dots,
				}, { Ui.round(), Ui.stroke(1.5) })
			end
			focus(navButton(if page == #story.pages then "The end!" else "Next", Ui.colors.yellow, function()
				page += 1
				drawPage()
			end, 20, 130, true))
		end
		drawPage()
	end

	gui.Destroying:Connect(function()
		token += 1
	end)
	showStories()
	-- B closes the book you're reading, or else the Story corner
	Ui.controller(gui, card, closeButton, function()
		if view == "reading" then
			showStories()
		else
			close()
		end
	end)
end

function Library.start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name == "LibraryDoor" then
			goThrough("enter")
		elseif prompt.Name == "LibraryOut" then
			goThrough("leave")
		elseif prompt.Name == "LibraryStart" then
			start()
		elseif prompt.Name == "LibraryPick" then
			pick(prompt:GetAttribute("Book"))
		elseif prompt.Name == "LibraryPut" then
			put(prompt:GetAttribute("Case"))
		elseif prompt.Name == "LibraryRead" then
			Library.open()
		end
	end)
	-- D-pad up stops tidying (not while a screen is open, the menu is up, or the ring is on a
	-- button), and the D-pad's picture shows by the button with a controller
	UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode == Enum.KeyCode.DPadUp and not processed and tidying() and Ui.openScreens == 0
			and not GuiService.MenuIsOpen and GuiService.SelectedObject == nil then
			stop()
		end
	end)
	UserInputService.LastInputTypeChanged:Connect(function()
		if padHint then
			padHint.Visible = Ui.usingController() and padHint.Image ~= ""
		end
	end)
	-- Pebble's Talk button stays aside while you're helping, even if Pebble streams in later
	ProximityPromptService.PromptShown:Connect(function(prompt)
		local model = prompt:FindFirstAncestorOfClass("Model")
		if tidying() and model and model:GetAttribute("ResidentId") == "pebble" then
			prompt.Enabled = false
		end
	end)
	-- the server puts a carried book back on the cart if your animal changes
	player:GetAttributeChangedSignal("LibraryCarry"):Connect(function()
		if carrying and not busy and player:GetAttribute("LibraryCarry") == nil then
			carrying = nil
			draw()
		end
	end)
	Players.PlayerAdded:Connect(watchCarry)
	for _, other in Players:GetPlayers() do
		watchCarry(other)
	end
	draw()
	task.spawn(seeThrough)
end

return Library
