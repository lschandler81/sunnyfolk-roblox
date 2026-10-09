-- The Library: helping Pebble tidy the shelves, and the picture stories it unlocks
-- (Config.LIBRARY, shared/Stories). "Go in" at the library on the square takes you into the
-- library hall, far from town (server/Town builds both); your screen (client/Library) draws
-- your books on the cart and the signs on the bookcases, and the server makes every round and
-- checks every step, with the LibraryAction remote:
--
--   LibraryAction("enter")  at the library's door on the square: takes you into the hall.
--   LibraryAction("leave")  at the hall's door: takes you back out to the square.
--   LibraryAction("start")  at Pebble's desk. Makes a round to suit how many rounds you've
--     finished (your stamps): sorting by colour, then size, then both. Returns (true, round),
--     where round is { kind, shelves = { { case, color?, size? } }, books = { { color, size } } }:
--     each shelf is a bookcase (1 to 4, Config.LIBRARY.CASES) and what it takes. If the last
--     round was still waiting for its stamp, it gets it first, and the coins and story come after
--     the round.
--   LibraryAction("pick", book)  at the cart, with empty paws: picks up book number `book`.
--     Your LibraryCarry attribute ("colour:size") shows it in your paws on everyone's screen.
--   LibraryAction("put", case)  in front of bookcase `case`, carrying a book. If it belongs
--     there it goes on, and returns (true, "placed", shelf), or with the last book (true,
--     "done", shelf, coins, the number of a story just unlocked or nil). If not, it goes back on
--     the cart: (true, "back"). A round finished in under MIN_ROUND seconds returns (true,
--     "wait", shelf, seconds left), and the screen asks for its stamp then:
--   LibraryAction("stamp")  the stamp (and coins) for a finished round. Returns (true, coins,
--     story), or (false, "wait", seconds left).
--   LibraryAction("stop")  stops helping part way through a round (the "Stop tidying" button):
--     the round and the book in your paws are put away, with no stamp.
--   LibraryAction("read", storyId, answer)  you've read a story you've unlocked to the end and
--     picked the right answer to its question. The first time pays STORY_COINS. Returns (true,
--     coins).
--
-- A finished round gives a stamp, unlocks the next story when it's due, and pays ROUND_COINS
-- (up to COINS_PER_HOUR an hour). Changing animal or leaving puts a carried book back on the
-- cart, and going out of the hall stops a round part way through.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Builder = require(Shared.CharacterBuilder)
local Config = require(Shared.Config)
local Stories = require(Shared.Stories)
local Analytics = require(script.Parent.Analytics)
local Goals = require(script.Parent.Goals)
local PlayerData = require(script.Parent.PlayerData)
local RemoteGuard = require(script.Parent.RemoteGuard)

local Remotes = Shared:WaitForChild("Remotes")

local L = Config.LIBRARY
local S = Config.STUDS
local SLACK = 3 -- studs further than REACH, for a player who's just moved
local WRONG = "Something went wrong. Please try again."
local KINDS = { "colour", "size", "both" }
local DOOR_WAIT = 1 -- seconds between going in and out
local STREAM_WAIT = 5 -- seconds to wait at most for Roblox to load where you're going

local Library = {}

type Shelf = { case: number, color: number?, size: string? }
type Book = { color: number, size: string }
type Round = {
	kind: string,
	shelves: { Shelf },
	books: { Book },
	placed: { [number]: number }, -- which shelf each tidied book is on
	carrying: number?, -- the book in their paws
	startedAt: number,
	complete: boolean, -- every book is tidied, and it's waiting for its stamp
}

-- The round each player is on.
local rounds: { [Player]: Round } = {}
local random = Random.new()
local lastDoor: { [Player]: number } = {} -- when each player last arrived through a door
local moving: { [Player]: boolean } = {} -- going through a door right now

-- Moves a player's animal so its feet are at `feet`, once Roblox has loaded what's there (like
-- going into your house, server/Interiors).
local function moveTo(player: Player, feet: CFrame)
	pcall(function()
		player:RequestStreamAroundAsync(feet.Position, STREAM_WAIT)
	end)
	local character = player.Character
	if character and player.Parent then
		character:PivotTo(feet * CFrame.new(0, Builder.ROOT_HEIGHT, 0))
	end
end

local function shuffle<T>(list: { T }): { T }
	for i = #list, 2, -1 do
		local j = random:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

-- A whole number from 1 to `most`?
local function isIndex(value: any, most: number): boolean
	return typeof(value) == "number" and value == value and value % 1 == 0 and value >= 1 and value <= most
end

-- Is the player within reach of `spot` (flat): REACH web units, or `studs`?
local function near(player: Player, spot: Vector3, studs: number?): boolean
	local root = player.Character and player.Character.PrimaryPart
	if not root then
		return false
	end
	local gap = root.Position - spot
	return Vector3.new(gap.X, 0, gap.Z).Magnitude <= (studs or L.REACH * S + SLACK) and math.abs(gap.Y) < 30
end

-- Shows the book in their paws on everyone's screen (client/Library), or none.
local function carry(player: Player, book: Book?)
	if player.Parent then
		player:SetAttribute("LibraryCarry", if book then `{book.color}:{book.size}` else nil)
	end
end

-- What a round sorts by, from how many rounds they've finished.
local function kindFor(stamps: number): string
	if stamps >= L.MIXED_FROM then
		return KINDS[random:NextInteger(1, #KINDS)]
	elseif stamps >= L.BOTH_FROM then
		return "both"
	elseif stamps >= L.SIZE_FROM then
		return "size"
	end
	return "colour"
end

-- A new round: the shelves (each on a bookcase picked at random), then the books for them.
-- Every shelf gets at least one book, and none more than SHELF_MAX (so if the shelves are full,
-- there are fewer books). In a colour round the books are all tall; in a size round they're any
-- colour.
local function makeRound(stamps: number): Round
	local kind = kindFor(stamps)
	local colours = {}
	for i = 1, #L.BOOK_COLORS do
		colours[i] = i
	end
	shuffle(colours)
	local shelves: { Shelf } = {}
	if kind == "colour" then
		for i = 1, L.COLOUR_SHELVES do
			table.insert(shelves, { case = 0, color = colours[i] })
		end
	elseif kind == "size" then
		shelves = { { case = 0, size = "tall" }, { case = 0, size = "short" } }
	else
		for i = 1, 2 do
			table.insert(shelves, { case = 0, color = colours[i], size = "tall" })
			table.insert(shelves, { case = 0, color = colours[i], size = "short" })
		end
	end
	local cases = {}
	for k = 1, #L.CASES do
		cases[k] = k
	end
	shuffle(cases)
	for s, shelf in shelves do
		shelf.case = cases[s]
	end

	local books: { Book } = {}
	local onShelf = table.create(#shelves, 0)
	for i = 1, L.BOOKS do
		local s = i
		if i > #shelves then
			local roomy = {}
			for j = 1, #shelves do
				if onShelf[j] < L.SHELF_MAX then
					table.insert(roomy, j)
				end
			end
			if #roomy == 0 then
				break
			end
			s = roomy[random:NextInteger(1, #roomy)]
		end
		onShelf[s] += 1
		local shelf = shelves[s]
		table.insert(books, {
			color = shelf.color or random:NextInteger(1, #L.BOOK_COLORS),
			size = shelf.size or "tall",
		})
	end
	return {
		kind = kind,
		shelves = shelves,
		books = shuffle(books),
		placed = {},
		carrying = nil,
		startedAt = os.clock(),
		complete = false,
	}
end

-- The stamp and coins for a finished round, once. Returns the coins and the number of a story
-- it unlocked (or nil).
local function stamp(player: Player, round: Round): (number, number?)
	rounds[player] = nil
	local coins, balance, stamps, story = 0, nil, 0, nil
	PlayerData.update(player, function(d)
		local card = d.library
		card.stamps += 1
		stamps = card.stamps
		local open = math.max(card.stories, Stories.unlockedFor(card.stamps))
		if open > card.stories then
			card.stories = open
			story = open
		end
		-- coins, up to the hourly cap (like the Cafe's)
		local now = os.time()
		if now - card.hourStart >= L.HOUR then
			card.hourStart = now
			card.hourCoins = 0
		end
		coins = math.clamp(L.COINS_PER_HOUR - card.hourCoins, 0, L.ROUND_COINS)
		card.hourCoins += coins
		d.coins += coins
		balance = d.coins
	end)
	if not balance then
		return 0, nil
	end
	if coins > 0 then
		Analytics.coinsEarned(player, coins, balance, "library:round")
	end
	Analytics.libraryRound(player, round.kind, stamps)
	Goals.event(player, "library")
	return coins, story
end

-- Seconds until a finished round may have its stamp.
local function waitFor(round: Round): number
	return round.startedAt + L.MIN_ROUND - os.clock()
end

local function action(player: Player, what: any, arg: any, answer: any): (boolean, any, any, any, any)
	local data = PlayerData.get(player)
	if not data then
		return false, "Just a moment!"
	end
	local round = rounds[player]

	if what == "enter" or what == "leave" then
		if moving[player] or os.clock() - (lastDoor[player] or 0) < DOOR_WAIT then
			return false, "Just a moment!"
		end
		local feet
		if what == "enter" then
			if not near(player, Config.libraryDoor(), L.DOOR_REACH) then
				return false, "Walk up to the library door."
			end
			feet = Config.libraryHallDoor()
		else
			if not near(player, Config.libraryHallDoor().Position, L.DOOR_REACH) then
				return false, "Walk up to the door."
			end
			-- going out stops a round part way through (a finished one keeps its stamp), and a
			-- book they're carrying goes back
			if round and not round.complete then
				rounds[player] = nil
			end
			carry(player, nil)
			-- (facing the fountain)
			local door = Config.libraryDoor()
			feet = CFrame.lookAt(door, Vector3.new(0, door.Y, 0))
		end
		moving[player] = true
		moveTo(player, feet)
		moving[player] = nil
		-- (the wait counts from arriving, so a quick second tap doesn't take them straight back)
		lastDoor[player] = os.clock()
		return true
	elseif what == "start" then
		local lastCoins, lastStory = nil, nil
		if not near(player, Config.libraryDesk()) then
			return false, "Walk up to Pebble's desk."
		end
		if round and round.complete then
			-- (the last round's stamp first)
			if waitFor(round) > 0 then
				return false, "Pebble is stamping your card..."
			end
			lastCoins, lastStory = stamp(player, round)
		end
		carry(player, nil)
		local new = makeRound(data.library.stamps)
		rounds[player] = new
		return true, { kind = new.kind, shelves = new.shelves, books = new.books }, lastCoins, lastStory
	elseif what == "pick" then
		if not round or round.complete then
			return false, "Press Help Pebble at Pebble's desk first!"
		end
		if round.carrying then
			return false, "You've got a book already!"
		end
		if not isIndex(arg, #round.books) or round.placed[arg] then
			return false, WRONG
		end
		-- (measured from that book, so anyone its button shows for is close enough)
		if not near(player, Config.libraryCartSlot(arg, #round.books).Position) then
			return false, "Walk up to the book cart."
		end
		round.carrying = arg
		carry(player, round.books[arg])
		return true
	elseif what == "put" then
		local i = round and round.carrying
		if not (round and i) then
			return false, "Pick up a book first!"
		end
		if not isIndex(arg, #L.CASES) then
			return false, WRONG
		end
		if not near(player, Config.libraryCaseFront(arg)) then
			return false, "Walk up to the bookcase."
		end
		round.carrying = nil
		carry(player, nil)
		local s = nil
		for j, shelf in round.shelves do
			if shelf.case == arg then
				s = j
			end
		end
		if not (s and Config.shelfFits(round.shelves[s], round.books[i])) then
			return true, "back" -- (it goes back on the cart)
		end
		round.placed[i] = s
		for j = 1, #round.books do
			if not round.placed[j] then
				return true, "placed", s
			end
		end
		round.complete = true
		local left = waitFor(round)
		if left > 0 then
			return true, "wait", s, left
		end
		local coins, story = stamp(player, round)
		return true, "done", s, coins, story
	elseif what == "stop" then
		-- (a finished round waiting for its stamp keeps it)
		if round and not round.complete then
			rounds[player] = nil
		end
		carry(player, nil)
		return true
	elseif what == "stamp" then
		if not (round and round.complete) then
			return false, WRONG
		end
		local left = waitFor(round)
		if left > 0 then
			return false, "wait", left
		end
		local coins, story = stamp(player, round)
		return true, coins, story
	elseif what == "read" then
		local index = typeof(arg) == "string" and Stories.INDEX[arg]
		if not index or index > data.library.stories then
			return false, WRONG
		end
		local story = Stories.LIST[index]
		if answer ~= story.question.right then
			return false, "Not quite! Have another try."
		end
		if table.find(data.library.read, story.id) then
			return true, 0
		end
		local balance = nil
		PlayerData.update(player, function(d)
			if not table.find(d.library.read, story.id) then
				table.insert(d.library.read, story.id)
				d.coins += L.STORY_COINS
				balance = d.coins
			end
		end)
		if not balance then
			return false, WRONG
		end
		Analytics.coinsEarned(player, L.STORY_COINS, balance, `story:{story.id}`)
		Analytics.libraryStory(player, story.id)
		return true, L.STORY_COINS
	end
	return false, WRONG
end

function Library.start()
	Remotes.LibraryAction.OnServerInvoke = function(player, what, arg, answer)
		if not RemoteGuard.allow(player, "Library") then
			return false, "Just a moment!"
		end
		return action(player, what, arg, answer)
	end
	-- a new animal (or none) puts the book in their paws back on the cart
	local function watch(player: Player)
		player.CharacterRemoving:Connect(function()
			local round = rounds[player]
			if round then
				round.carrying = nil
			end
			carry(player, nil)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		rounds[player] = nil
		lastDoor[player] = nil
		moving[player] = nil
	end)
	-- a book carried out of the hall goes back on the cart (so nobody wanders off to the
	-- Cafe or a pond with one over their head)
	task.spawn(function()
		while true do
			task.wait(L.CARRY_CHECK)
			for player, round in rounds do
				local root = player.Character and player.Character.PrimaryPart
				-- (not while going through the door: they're on their way)
				if not moving[player] and not (root and Config.libraryInside(root.Position)) then
					-- out of the hall: a round part way through is stopped, and the book goes back
					if not round.complete then
						rounds[player] = nil
					end
					round.carrying = nil
					carry(player, nil)
				end
			end
		end
	end)
end

return Library
