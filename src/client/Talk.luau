-- Talking to the residents: press Talk (E, or tap) and they say something in a speech
-- bubble, nodding along. The first time each visit they say hello to you by name and wave.
-- On a phone on its side, what they say shows in a card at the top left instead (Ui.messages),
-- clear of the HUD and the buttons.
-- Also puts a name tag over every animal (other than you), just above its ears or hat, and
-- keeps Clover's Hat Shop buttons hidden until you've said hello to her (shared/Goals).
--
-- Their lines are in assets/characters/sunnyfolk.json. Only the person talking sees the
-- bubble, so nobody's chat gets in anyone else's way.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Builder = require(Shared.CharacterBuilder)
local Config = require(Shared.Config)
local GoalList = require(Shared.Goals)
local Looks = require(Shared.Looks)
local Animator = require(script.Parent.Animator)
local Ui = require(script.Parent.Ui)

local player = Players.LocalPlayer

local Talk = {}

local TAG_HEIGHT = 5 -- studs above the middle of the animal, at least
local TAG_GAP = 1 -- studs between the top of the animal (ears, hat) and its name tag
local WALK_AWAY = 24 -- the bubble goes when you're this far away
local RESIDENT_TAG = "SunnyfolkResident" -- server/Residents tags each resident with this

---------------------------------------------------------------- name tags

local tags: { [Model]: BillboardGui } = {}

-- How high over its middle (studs) an animal's name tag and speech bubble go: just above
-- the top of it, so a bunny's ears or a tall hat never poke through.
local function tagHeight(model: Model, root: BasePart): number
	local box, size = model:GetBoundingBox()
	local top = box.Position.Y + size.Y / 2 - root.Position.Y
	return math.max(TAG_HEIGHT, top + TAG_GAP)
end

local function addTag(model: Model)
	if tags[model] then
		return
	end
	local root = model:WaitForChild("HumanoidRootPart", 10)
	local name = model:GetAttribute("DisplayName")
	if not (root and name and model.Parent) or model:GetAttribute("UserId") == player.UserId then
		return -- not ready, or it's you
	end
	local resident = model:GetAttribute("ResidentId") ~= nil
	local tag = Ui.new("BillboardGui", {
		Name = "NameTag",
		Adornee = root,
		StudsOffsetWorldSpace = Vector3.new(0, tagHeight(model, root :: BasePart), 0),
		Size = UDim2.fromOffset(200, 34),
		MaxDistance = 70,
		LightInfluence = 0,
		Parent = root,
	}, {
		Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(0, 30),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = if resident then Ui.colors.paper else Ui.colors.cream,
			BackgroundTransparency = 0.05,
		}, {
			Ui.round(),
			Ui.stroke(2.5),
			Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }),
			Ui.text({
				Text = name,
				TextSize = 18,
				TextColor3 = if resident then Ui.colors.coral else Ui.colors.ink,
				Size = UDim2.fromScale(0, 1),
				AutomaticSize = Enum.AutomaticSize.X,
				TextWrapped = false,
			}),
		}),
	})
	tags[model] = tag
	-- a hat put on (or taken off) later changes how tall it is: lift the tag again once the
	-- hat's parts have arrived
	local function lift()
		if tag.Parent then
			tag.StudsOffsetWorldSpace = Vector3.new(0, tagHeight(model, root :: BasePart), 0)
		end
	end
	model.ChildAdded:Connect(function()
		task.delay(0.5, lift)
	end)
	model.ChildRemoved:Connect(function()
		task.delay(0.5, lift)
	end)
end

---------------------------------------------------------------- speech bubbles

local bubble: Instance? = nil -- the bubble over their head, or the card on a phone
local speaker: Model? = nil
local bubbleEnds = 0
local lineNumber: { [string]: number } = {}
local greeted: { [string]: boolean } = {}

local function hush()
	if bubble then
		bubble:Destroy()
		bubble = nil
	end
	if speaker and tags[speaker] then
		tags[speaker].Enabled = true
	end
	speaker = nil
end

local function say(model: Model, who: string, text: string)
	hush()
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	-- On a phone on its side, a card at the top left (under Roblox's buttons, left of the HUD)
	local small = Ui.shortScreen()
	local card = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(300, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Ui.colors.paper,
		ZIndex = 2,
	}, {
		Ui.corner(18),
		Ui.stroke(3),
		Ui.new("UIPadding", {
			PaddingLeft = UDim.new(0, 14),
			PaddingRight = UDim.new(0, 14),
			PaddingTop = UDim.new(0, 8),
			PaddingBottom = UDim.new(0, 12),
		}),
		Ui.new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
		Ui.text({
			Text = who,
			TextSize = if small then 16 else 17,
			TextColor3 = Ui.colors.coral,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, 20),
			LayoutOrder = 1,
			ZIndex = 2,
		}),
		Ui.text({
			Text = text,
			TextSize = if small then 17 else 21,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 2,
			ZIndex = 2,
		}),
	})
	-- the little tail pointing down at whoever's talking
	local tail = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(18, 18),
		Rotation = 45,
		BackgroundColor3 = Ui.colors.paper,
		ZIndex = 1,
	}, { Ui.stroke(3) })
	if small then
		-- (first in the column, above any big message)
		card.AnchorPoint = Vector2.zero
		card.Position = UDim2.new()
		card.Size = UDim2.fromScale(1, 0)
		card.LayoutOrder = 1
		card.Parent = Ui.messages()
		tail:Destroy()
		bubble = card
	else
		bubble = Ui.new("BillboardGui", {
			Name = "SpeechBubble",
			Adornee = root,
			-- (the name tag's height, measured before any wave or nod)
			StudsOffsetWorldSpace = Vector3.new(0, (if tags[model] then tags[model].StudsOffsetWorldSpace.Y
				else tagHeight(model, root :: BasePart)) - 0.4, 0),
			Size = UDim2.fromOffset(320, 260),
			SizeOffset = Vector2.new(0, 0.5),
			AlwaysOnTop = true,
			LightInfluence = 0,
			Parent = player:WaitForChild("PlayerGui"),
		}, { tail, card })
	end
	speaker = model
	if tags[model] then
		tags[model].Enabled = false
	end
	local seconds = 2.5 + #text * 0.06
	bubbleEnds = os.clock() + seconds
	Animator.talk(model, math.min(seconds, 2.5))
end

local function talkTo(model: Model)
	local id = model:GetAttribute("ResidentId")
	local info = typeof(id) == "string" and Looks.resident(id)
	if not info then
		return
	end
	local n = lineNumber[id] or 0
	lineNumber[id] = n + 1
	local text = info.lines[(n % #info.lines) + 1]
	if not greeted[id] then
		-- the first chat of the visit starts with a hello, by name
		greeted[id] = true
		local hello = Config.GREETINGS[((n + #player.DisplayName) % #Config.GREETINGS) + 1]
		text = `{hello}, {player.DisplayName}! {text}`
		Animator.wave(model)
	end
	say(model, info.name, text)
end

-- A resident (by id, like "pebble") says `text` in a speech bubble on this screen only, as if
-- you'd talked to them (the Library's Pebble). Returns their model, or nil if they aren't here.
function Talk.residentSays(id: string, text: string): Model?
	local info = Looks.resident(id)
	for _, model in CollectionService:GetTagged(RESIDENT_TAG) do
		if model:IsA("Model") and model:GetAttribute("ResidentId") == id and info then
			say(model, info.name, text)
			return model
		end
	end
	return nil
end

---------------------------------------------------------------- starting

-- `openShop(shopId)` runs when someone presses a shop's button (by Clover, or at a shop door).
function Talk.start(openShop: (string) -> ())
	CollectionService:GetInstanceAddedSignal(Builder.TAG):Connect(function(model)
		task.spawn(addTag, model)
	end)
	CollectionService:GetInstanceRemovedSignal(Builder.TAG):Connect(function(model)
		tags[model :: Model] = nil
	end)
	for _, model in CollectionService:GetTagged(Builder.TAG) do
		task.spawn(addTag, model)
	end

	-- Clover's Hat Shop buttons (by her, and at the shop's door; server/Residents makes them)
	-- only work on your screen once you've said hello to her.
	local function hatShopButton(object: Instance)
		if object:IsA("ProximityPrompt") and object.Name == "Shop" and object:GetAttribute("ShopId") == "hats" then
			object.Enabled = GoalList.hatShopOpen(GoalList.fromAttribute(player:GetAttribute("GoalsDone")))
		end
	end
	task.spawn(function()
		local residents = Workspace:WaitForChild("Residents")
		residents.DescendantAdded:Connect(hatShopButton)
		local function all()
			for _, object in residents:GetDescendants() do
				hatShopButton(object)
			end
		end
		player:GetAttributeChangedSignal("GoalsDone"):Connect(all)
		all()
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local model = prompt:FindFirstAncestorOfClass("Model")
		if prompt.Name == "Talk" and model then
			talkTo(model)
		elseif prompt.Name == "Shop" then
			local shopId = prompt:GetAttribute("ShopId")
			hush()
			openShop(if typeof(shopId) == "string" then shopId else "hats")
		end
	end)

	-- the bubble goes after a while, or when you walk off
	RunService.Heartbeat:Connect(function()
		if not speaker then
			return
		end
		local mine = player.Character and player.Character.PrimaryPart
		local theirs = speaker.PrimaryPart
		local far = mine and theirs and (mine.Position - theirs.Position).Magnitude > WALK_AWAY
		if os.clock() > bubbleEnds or far or not speaker.Parent then
			hush()
		end
	end)
end

return Talk
