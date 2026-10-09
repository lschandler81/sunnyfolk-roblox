-- The daily present and the board, "Today in Sunnyfolk", on the player's screen (the server,
-- server/Daily, decides and pays everything; this only shows it):
--   * the present: a card with the seven days, today's ringed, and what you got
--   * the board (from its Read button): today's story on a big picture card, with how far
--     you've got; the three little helps underneath, smaller; and your story stamps. In Studio
--     it also has a "Next day" button for testing.
--   * a message when a new story is waiting (and once a visit while it waits), and a thank you
--     when you've done it; "Little help done!" when you finish a little help
-- The present and the messages wait their turn (Hud.inTurn), so they never pop up over the
-- welcome screen or a shop.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Config = require(Shared.Config)
local Controls = require(script.Parent.Controls)
local Hud = require(script.Parent.Hud)
local Ui = require(script.Parent.Ui)

local Remotes = Shared:WaitForChild("Remotes")
local player = Players.LocalPlayer
local TODAY = Config.TODAY

local DailyPanel = {}

local screen: ScreenGui? = nil

-- A 620 x 290 card (a landscape phone) that grows on bigger screens, with a title and a close
-- button. Returns the card, the close button and a function that closes it.
local function openCard(name: string, title: string, closeText: string, reason: string): (ScreenGui, Frame, TextButton, () -> ())
	Controls.set(false, reason)
	local gui = Ui.screen(name, 17)
	screen = gui
	local card = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(620, 290),
		BackgroundColor3 = Ui.colors.paper,
		Parent = gui,
	}, { Ui.corner(22), Ui.stroke(3) })
	Ui.fitToScreen(card, 620, 290)
	local function close()
		if gui.Parent then
			gui:Destroy()
			screen = nil
			Controls.set(true, reason)
		end
	end
	Ui.text({
		Text = title,
		TextSize = 22,
		TextColor3 = Ui.colors.coral,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.fromOffset(400, Ui.TOUCH),
		Parent = card,
	})
	local closeButton = Ui.button(closeText, Ui.colors.cream, close, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(100, Ui.TOUCH),
		TextSize = 20,
		Parent = card,
	})
	return gui, card, closeButton, close
end

---------------------------------------------------------------- the daily present

local function showPresent(day: number, coins: number, hat: string?)
	if screen or Ui.openScreens > 0 then
		return
	end
	local gui, card, _, close = openCard("DailyPresent", "Your daily present!", "Close", "present")

	-- the seven days: done ones teal, today's big and yellow, the rest to come
	local days = #Config.DAILY.COINS
	local row = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 66),
		Size = UDim2.fromOffset(0, 70),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Parent = card,
	}, {
		Ui.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	for i = 1, days do
		local today = i == day
		local size = if today then 64 else 50
		local circle = Ui.new("Frame", {
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = if i < day then Ui.colors.teal elseif today then Ui.colors.yellow else Ui.colors.cream,
			LayoutOrder = i,
			Parent = row,
		}, { Ui.round(), Ui.stroke(if today then 4 else 2.5, if i > day then Ui.colors.grey else Ui.colors.ink) })
		Ui.text({
			Text = tostring(i),
			TextSize = if today then 28 else 20,
			TextColor3 = if i < day then Ui.colors.paper elseif today then Ui.colors.ink else Ui.colors.grey,
			Size = UDim2.fromScale(1, 1),
			Parent = circle,
		})
	end

	local got = `Day {day}: +{coins} coins`
	if hat then
		got ..= ` and a {hat}!`
	end
	Ui.text({
		Text = got,
		TextSize = 24,
		Position = UDim2.fromOffset(20, 148),
		Size = UDim2.new(1, -40, 0, 34),
		Parent = card,
	})
	Ui.text({
		Text = if day < days
			then `Come back another day for the day {day + 1} present.`
			else "That's all seven! Your next visit starts again at day 1.",
		TextSize = 16,
		TextColor3 = Ui.colors.teal,
		Position = UDim2.fromOffset(20, 184),
		Size = UDim2.new(1, -40, 0, 24),
		Parent = card,
	})
	if hat then
		Ui.text({
			Text = "Wear it from Clover's Hat Shop.",
			TextSize = 16,
			TextColor3 = Ui.colors.teal,
			Position = UDim2.fromOffset(20, 208),
			Size = UDim2.new(1, -40, 0, 22),
			Parent = card,
		})
	end
	local lovely = Ui.button("Lovely!", Ui.colors.yellow, close, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(160, 48),
		TextSize = 22,
		Parent = card,
	})
	Ui.controller(gui, card, lovely, close)
end

---------------------------------------------------------------- the board

-- Today's little helps as the server last said: { day, got = {...}, done = {...} }.
local function myRequests(): { day: number, got: { number }, done: { boolean } }?
	local saved = player:GetAttribute("Requests")
	if typeof(saved) ~= "string" then
		return nil
	end
	local ok, value = pcall(function()
		return HttpService:JSONDecode(saved)
	end)
	if ok and typeof(value) == "table" and typeof(value.day) == "number" then
		return value
	end
	return nil
end

-- Their story as the server last said: its id (nil before their first), how far they've got,
-- whether it's done or they've read it, and their story stamps (for each story id).
local function myStory(): { id: string?, got: number, done: boolean, shown: boolean, stamps: { [string]: number } }
	local saved = player:GetAttribute("Today")
	local ok, value = false, nil
	if typeof(saved) == "string" then
		ok, value = pcall(function()
			return HttpService:JSONDecode(saved)
		end)
	end
	if not (ok and typeof(value) == "table") then
		value = {}
	end
	local stamps = {}
	if typeof(value.stamps) == "table" then
		for id, n in value.stamps do
			if typeof(id) == "string" and typeof(n) == "number" then
				stamps[id] = n
			end
		end
	end
	return {
		id = if typeof(value.id) == "string" then value.id else nil,
		got = if typeof(value.got) == "number" then value.got else 0,
		done = value.done == true,
		shown = value.shown == true,
		stamps = stamps,
	}
end

-- A row of little things side by side, centred up and down.
local function row(props: { [string]: any }, gap: number): Frame
	local frame = Ui.new("Frame", {
		BackgroundTransparency = 1,
	}, {
		Ui.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, gap),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	for key, value in pairs(props) do
		(frame :: any)[key] = value
	end
	return frame
end

-- Today's story: one big card across the top, with its picture, what to do, how far you've
-- got, and what it gives (coins and a story stamp).
local function storyCard(parent: GuiObject)
	local mine = myStory()
	local story = Config.todayStory(mine.id)
	local done = story ~= nil and mine.done
	local frame = Ui.new("Frame", {
		Position = UDim2.fromOffset(14, 56),
		Size = UDim2.fromOffset(592, 98),
		BackgroundColor3 = if done then Ui.colors.mint else Ui.colors.cream,
		Parent = parent,
	}, { Ui.corner(16), Ui.stroke(3) })
	local picture = Ui.new("Frame", {
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.fromOffset(82, 82),
		BackgroundColor3 = Color3.fromHex(if story then story.color else "#f2a7b8"),
		Parent = frame,
	}, { Ui.corner(14), Ui.stroke(2.5) })
	Ui.text({
		Text = if story then story.pic else "🐰",
		TextSize = 34,
		Size = UDim2.fromScale(1, 1),
		Parent = picture,
	})
	-- (before their first story, while they do the First Story's goals)
	Ui.text({
		Text = if story then story.title else "Your Goals come first",
		TextSize = 21,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(102, 6),
		Size = UDim2.fromOffset(360, 28),
		Parent = frame,
	})
	Ui.text({
		Text = if story then story.text else "Finish your first Goals. Then a friend here will need your help!",
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(102, 34),
		Size = UDim2.fromOffset(360, 36),
		Parent = frame,
	})
	if not story then
		return
	end
	Ui.text({
		Text = if done then "Done! A new story comes another day."
			elseif story.need > 1 then `{math.min(mine.got, story.need)}/{story.need}`
			else "",
		TextSize = 16,
		TextColor3 = Ui.colors.teal,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(102, 72),
		Size = UDim2.fromOffset(360, 20),
		Parent = frame,
	})
	-- what it gives
	local gives = Ui.new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(110, 80),
		BackgroundTransparency = 1,
		Parent = frame,
	}, {
		Ui.new("UIListLayout", {
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local coins = row({ Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 1, Parent = gives }, 6)
	Ui.coin(24, { LayoutOrder = 1, Parent = coins })
	Ui.text({
		Text = `+{TODAY.COINS}`,
		TextSize = 20,
		Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
		TextWrapped = false,
		LayoutOrder = 2,
		Parent = coins,
	})
	local stamp = row({ Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2, Parent = gives }, 6)
	Ui.new("Frame", {
		Size = UDim2.fromOffset(28, 28),
		BackgroundColor3 = Color3.fromHex(story.color),
		LayoutOrder = 1,
		Parent = stamp,
	}, { Ui.round(), Ui.stroke(2), Ui.text({ Text = story.stamp, TextSize = 15, Size = UDim2.fromScale(1, 1) }) })
	Ui.text({
		Text = "a stamp",
		TextSize = 16,
		Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
		TextWrapped = false,
		LayoutOrder = 2,
		Parent = stamp,
	})
end

-- The three little helps, side by side under the story, smaller: pinned up a little crooked,
-- like paper notes.
local function littleHelps(parent: GuiObject)
	Ui.text({
		Text = "Little helps",
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(18, 156),
		Size = UDim2.fromOffset(200, 22),
		Parent = parent,
	})
	local notes = row({ Position = UDim2.fromOffset(14, 178), Size = UDim2.fromOffset(592, 58), Parent = parent }, 12)
	local mine = myRequests()
	if not mine then
		return
	end
	for slot, index in Config.requestsFor(mine.day) do
		local request = Config.REQUESTS[index]
		local done = mine.done[slot] == true
		local note = Ui.new("Frame", {
			Size = UDim2.fromOffset(189, 58),
			BackgroundColor3 = if done then Ui.colors.mint else Ui.colors.cream,
			Rotation = (slot - 2) * 1.5,
			LayoutOrder = slot,
			Parent = notes,
		}, { Ui.corner(12), Ui.stroke(2.5), Ui.padding(6) })
		Ui.text({
			Text = request.text,
			TextSize = 15,
			TextYAlignment = Enum.TextYAlignment.Top,
			Size = UDim2.new(1, 0, 0, 30),
			Parent = note,
		})
		local need = request.need or 1
		local got = math.min(need, mine.got[slot] or 0)
		Ui.text({
			Text = if done then "Done!" elseif need > 1 then `{got}/{need}` else "",
			TextSize = 14,
			TextColor3 = if done then Ui.colors.teal else Ui.colors.ink,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(2, 31),
			Size = UDim2.new(0.5, 0, 0, 15),
			Parent = note,
		})
		local reward = row({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -2, 0, 30),
			Size = UDim2.fromOffset(0, 16),
			AutomaticSize = Enum.AutomaticSize.X,
			Parent = note,
		}, 4)
		Ui.coin(15, { LayoutOrder = 1, Parent = reward })
		Ui.text({
			Text = `+{request.coins}`,
			TextSize = 14,
			Size = UDim2.fromOffset(0, 16),
			AutomaticSize = Enum.AutomaticSize.X,
			TextWrapped = false,
			LayoutOrder = 2,
			Parent = reward,
		})
	end
end

-- Their story stamps along the bottom: one for each story, bright once they've done it, with
-- how many times if it's more than once.
local function stamps(parent: GuiObject)
	Ui.text({
		Text = "Story stamps",
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(18, 240),
		Size = UDim2.fromOffset(110, 44),
		Parent = parent,
	})
	local mine = myStory()
	local line = row({ Position = UDim2.fromOffset(130, 244), Size = UDim2.fromOffset(260, 36), Parent = parent }, 6)
	for i, story in TODAY.STORIES do
		local n = mine.stamps[story.id] or 0
		local stamp = Ui.new("Frame", {
			Size = UDim2.fromOffset(36, 36),
			BackgroundColor3 = if n > 0 then Color3.fromHex(story.color) else Ui.colors.cream,
			LayoutOrder = i,
			Parent = line,
		}, {
			Ui.round(),
			Ui.stroke(2, if n > 0 then Ui.colors.ink else Ui.colors.grey),
			Ui.text({ Text = story.stamp, TextSize = 18, TextTransparency = if n > 0 then 0 else 0.65, Size = UDim2.fromScale(1, 1) }),
		})
		if n > 1 then
			Ui.new("Frame", {
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, 4, 1, 4),
				Size = UDim2.fromOffset(18, 18),
				BackgroundColor3 = Ui.colors.ink,
				Parent = stamp,
			}, {
				Ui.round(),
				Ui.text({ Text = tostring(math.min(n, 99)), TextSize = 11, TextColor3 = Ui.colors.paper, Size = UDim2.fromScale(1, 1) }),
			})
		end
	end
end

function DailyPanel.openBoard()
	if screen or Ui.openScreens > 0 then
		return
	end
	local gui, card, closeButton, close = openCard("RequestBoard", "Today in Sunnyfolk", "Bye!", "board")

	-- everything that changes, rebuilt whenever the server says something's new
	local live: Frame? = nil
	local function refresh()
		if live then
			live:Destroy()
		end
		-- (under the title and buttons)
		local frame = Ui.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 0, Parent = card })
		live = frame
		storyCard(frame)
		littleHelps(frame)
		stamps(frame)
	end
	refresh()
	local watching = {
		player:GetAttributeChangedSignal("Requests"):Connect(refresh),
		player:GetAttributeChangedSignal("Today"):Connect(refresh),
	}
	gui.Destroying:Connect(function()
		for _, connection in watching do
			connection:Disconnect()
		end
	end)

	-- Studio only: pretend it's tomorrow (live servers ignore this). Only while saving is off,
	-- so a test never puts made-up dates in a real save.
	if RunService:IsStudio() then
		if player:GetAttribute("Saving") == false then
			Ui.button("Next day (Studio)", Ui.colors.creamDeep, function()
				Remotes.StudioNextDay:FireServer()
			end, {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -12, 0, 240),
				Size = UDim2.fromOffset(200, Ui.TOUCH),
				TextSize = 16,
				Parent = card,
			})
		else
			Ui.text({
				Text = "To test the next day, turn off Studio's API access (saving)",
				TextSize = 13,
				TextColor3 = Ui.colors.coral,
				TextXAlignment = Enum.TextXAlignment.Right,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -12, 0, 240),
				Size = UDim2.fromOffset(210, 44),
				Parent = card,
			})
		end
	end

	Ui.controller(gui, card, closeButton, close)
end

function DailyPanel.isOpen(): boolean
	return screen ~= nil
end

-- Tells them about a story that's waiting: once each visit, and again when a new one comes.
local told: string? = nil
local function tellStory()
	local mine = myStory()
	local story = Config.todayStory(mine.id)
	if not story or mine.done or mine.id == told then
		return
	end
	told = mine.id
	Hud.announce(`{story.title}!`, if mine.shown then story.text else "Read the board by the fountain")
end

function DailyPanel.start()
	Remotes.DailyPresent.OnClientEvent:Connect(function(day, coins, hat)
		if typeof(day) ~= "number" or typeof(coins) ~= "number" then
			return
		end
		local hatName = if typeof(hat) == "string" then hat else nil
		Hud.inTurn(function()
			showPresent(day, coins, hatName)
		end)
	end)
	Remotes.RequestDone.OnClientEvent:Connect(function(text, coins)
		if typeof(text) ~= "string" or typeof(coins) ~= "number" then
			return
		end
		Hud.announce("Little help done!", `{text}: +{coins} coins`)
	end)
	Remotes.TodayDone.OnClientEvent:Connect(function(id, coins)
		local story = Config.todayStory(id)
		if not story or typeof(coins) ~= "number" then
			return
		end
		Hud.announce(`{story.who} says thank you!`, `+{coins} coins and a story stamp`)
	end)
	player:GetAttributeChangedSignal("Today"):Connect(tellStory)
	tellStory()
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name == "RequestBoard" then
			DailyPanel.openBoard()
		end
	end)
end

return DailyPanel
