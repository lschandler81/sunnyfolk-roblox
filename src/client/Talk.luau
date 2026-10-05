-- Talking to the residents: press Talk (E, or tap) and they say something in a speech
-- bubble, nodding along. The first time each visit they say hello to you by name and wave.
-- Also puts a name tag over every animal (other than you).
--
-- Their lines are in assets/characters/sunnyfolk.json. Only the person talking sees the
-- bubble, so nobody's chat gets in anyone else's way.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Builder = require(Shared.CharacterBuilder)
local Config = require(Shared.Config)
local Looks = require(Shared.Looks)
local Animator = require(script.Parent.Animator)
local Ui = require(script.Parent.Ui)

local player = Players.LocalPlayer

local Talk = {}

local TAG_HEIGHT = 5 -- studs above the middle of the animal (clear of tall hats)
local WALK_AWAY = 24 -- the bubble goes when you're this far away

---------------------------------------------------------------- name tags

local tags: { [Model]: BillboardGui } = {}

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
		StudsOffsetWorldSpace = Vector3.new(0, TAG_HEIGHT, 0),
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
end

---------------------------------------------------------------- speech bubbles

local bubble: BillboardGui? = nil
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
			TextSize = 17,
			TextColor3 = Ui.colors.coral,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, 20),
			LayoutOrder = 1,
			ZIndex = 2,
		}),
		Ui.text({
			Text = text,
			TextSize = 21,
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
	bubble = Ui.new("BillboardGui", {
		Name = "SpeechBubble",
		Adornee = root,
		StudsOffsetWorldSpace = Vector3.new(0, TAG_HEIGHT - 0.4, 0),
		Size = UDim2.fromOffset(320, 260),
		SizeOffset = Vector2.new(0, 0.5),
		AlwaysOnTop = true,
		LightInfluence = 0,
		Parent = player:WaitForChild("PlayerGui"),
	}, { tail, card })
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

---------------------------------------------------------------- starting

-- `openHatShop` runs when someone presses the Hat Shop button by Clover or the shop door.
function Talk.start(openHatShop: () -> ())
	CollectionService:GetInstanceAddedSignal(Builder.TAG):Connect(function(model)
		task.spawn(addTag, model)
	end)
	CollectionService:GetInstanceRemovedSignal(Builder.TAG):Connect(function(model)
		tags[model :: Model] = nil
	end)
	for _, model in CollectionService:GetTagged(Builder.TAG) do
		task.spawn(addTag, model)
	end

	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local model = prompt:FindFirstAncestorOfClass("Model")
		if prompt.Name == "Talk" and model then
			talkTo(model)
		elseif prompt.Name == "HatShop" then
			hush()
			openHatShop()
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
