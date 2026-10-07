-- The daily present and the request board on the player's screen (the server, server/Daily,
-- decides and pays everything; this only shows it):
--   * the present: a card with the seven days, today's ringed, and what you got
--   * the Request Board: today's three requests and how far you've got (from the board's Read
--     button). In Studio it also has a "Next day" button for testing.
--   * "Request done!" when you finish one
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

---------------------------------------------------------------- the request board

-- Today's requests as the server last said: { day, got = {...}, done = {...} }.
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

function DailyPanel.openBoard()
	if screen or Ui.openScreens > 0 then
		return
	end
	local gui, card, closeButton, close = openCard("RequestBoard", "Request Board", "Bye!", "board")

	-- the three requests, side by side
	local row = Ui.new("Frame", {
		Position = UDim2.fromOffset(14, 60),
		Size = UDim2.fromOffset(592, 166),
		BackgroundTransparency = 1,
		Parent = card,
	}, {
		Ui.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local function refresh()
		for _, child in row:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local mine = myRequests()
		if not mine then
			return
		end
		for slot, index in Config.requestsFor(mine.day) do
			local request = Config.REQUESTS[index]
			local done = mine.done[slot] == true
			local note = Ui.new("Frame", {
				Size = UDim2.fromOffset(189, 166),
				BackgroundColor3 = if done then Ui.colors.mint else Ui.colors.cream,
				Rotation = (slot - 2) * 1.5, -- pinned up a little crooked, like paper notes
				LayoutOrder = slot,
				Parent = row,
			}, { Ui.corner(12), Ui.stroke(2.5), Ui.padding(10) })
			Ui.text({
				Text = request.text,
				TextSize = 19,
				TextYAlignment = Enum.TextYAlignment.Top,
				Size = UDim2.new(1, 0, 0, 74),
				Parent = note,
			})
			local need = request.need or 1
			local got = math.min(need, mine.got[slot] or 0)
			Ui.text({
				Text = if done then "Done!" elseif need > 1 then `{got}/{need}` else "",
				TextSize = 20,
				TextColor3 = if done then Ui.colors.teal else Ui.colors.ink,
				Position = UDim2.fromOffset(0, 78),
				Size = UDim2.new(1, 0, 0, 26),
				Parent = note,
			})
			local reward = Ui.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromScale(0.5, 1),
				Size = UDim2.fromOffset(0, 30),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundTransparency = 1,
				Parent = note,
			}, {
				Ui.new("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 6),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			})
			Ui.coin(22, { LayoutOrder = 1, Parent = reward })
			Ui.text({
				Text = `+{request.coins}`,
				TextSize = 20,
				Size = UDim2.fromOffset(0, 28),
				AutomaticSize = Enum.AutomaticSize.X,
				TextWrapped = false,
				LayoutOrder = 2,
				Parent = reward,
			})
		end
	end
	refresh()
	local watching = player:GetAttributeChangedSignal("Requests"):Connect(refresh)
	gui.Destroying:Connect(function()
		watching:Disconnect()
	end)

	Ui.text({
		Text = "New requests every day!",
		TextSize = 16,
		TextColor3 = Ui.colors.teal,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(16, 238),
		Size = UDim2.fromOffset(260, 40),
		Parent = card,
	})
	-- Studio only: pretend it's tomorrow (live servers ignore this). Only while saving is off,
	-- so a test never puts made-up dates in a real save.
	if RunService:IsStudio() then
		if player:GetAttribute("Saving") == false then
			Ui.button("Next day (Studio test)", Ui.colors.creamDeep, function()
				Remotes.StudioNextDay:FireServer()
			end, {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -12, 0, 236),
				Size = UDim2.fromOffset(240, Ui.TOUCH),
				TextSize = 16,
				Parent = card,
			})
		else
			Ui.text({
				Text = "To test the next day, turn off Studio's API access (saving)",
				TextSize = 14,
				TextColor3 = Ui.colors.coral,
				TextXAlignment = Enum.TextXAlignment.Right,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -12, 0, 238),
				Size = UDim2.fromOffset(300, 40),
				Parent = card,
			})
		end
	end

	Ui.controller(gui, card, closeButton, close)
end

function DailyPanel.isOpen(): boolean
	return screen ~= nil
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
		Hud.announce("Request done!", `{text}: +{coins} coins`)
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name == "RequestBoard" then
			DailyPanel.openBoard()
		end
	end)
end

return DailyPanel
