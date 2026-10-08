-- Starts the game on each player's computer: the welcome screen first, then the town with
-- coins, talking, the shops, "My things", homes, the goals, the daily present and request
-- board, pets, the Garden and its Garden Book, and the animals' animation.

local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Config = require(Shared.Config)
local Remotes = Shared:WaitForChild("Remotes")

local Animator = require(script.Parent.Animator)
local Chooser = require(script.Parent.Chooser)
local Coins = require(script.Parent.Coins)
local Controls = require(script.Parent.Controls)
local DailyPanel = require(script.Parent.DailyPanel)
local Garden = require(script.Parent.Garden)
local GoalsPanel = require(script.Parent.GoalsPanel)
local HatShop = require(script.Parent.HatShop)
local HomeDesigner = require(script.Parent.HomeDesigner)
local Homes = require(script.Parent.Homes)
local PetShop = require(script.Parent.PetShop)
local Pets = require(script.Parent.Pets)
local Hud = require(script.Parent.Hud)
local Prompts = require(script.Parent.Prompts)
local Run = require(script.Parent.Run)
local Talk = require(script.Parent.Talk)
local Wardrobe = require(script.Parent.Wardrobe)
local GardenBook = require(script.Parent.GardenBook)

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- Roblox's own backpack, health bar and emotes aren't used here.
for _, kind in { Enum.CoreGuiType.Backpack, Enum.CoreGuiType.Health, Enum.CoreGuiType.EmotesMenu } do
	pcall(function()
		StarterGui:SetCoreGuiEnabled(kind, false)
	end)
end

-- No chat box at all, if Config.PLAYER_CHAT is turned off. On a TV (Xbox, PlayStation)
-- there's never one: Roblox's console guidelines say the chat window must be off there.
if not Config.PLAYER_CHAT or GuiService:IsTenFootInterface() then
	pcall(function()
		local window = TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")
		local input = TextChatService:FindFirstChildOfClass("ChatInputBarConfiguration")
		if window then
			window.Enabled = false
		end
		if input then
			input.Enabled = false
		end
	end)
end

Animator.start()
Prompts.start()
Run.start()
Coins.start()
-- a shop's button opens its screen: the Pet Shop's own, or the shop screen for hats and clothes
Talk.start(function(shopId)
	if shopId == "pets" then
		PetShop.open()
	else
		HatShop.open(shopId)
	end
end)
Pets.start()
Garden.start()
GardenBook.start()
Homes.start(Hud.toast)
DailyPanel.start()

-- While the welcome screen is up (before you've joined in), the camera drifts slowly
-- round the square.
local drifting: RBXScriptConnection? = nil
local function driftRoundSquare()
	camera.CameraType = Enum.CameraType.Scriptable
	drifting = RunService.RenderStepped:Connect(function()
		local a = os.clock() * 0.05
		camera.CFrame = CFrame.lookAt(Vector3.new(math.sin(a) * 120, 45, math.cos(a) * 120), Vector3.new(0, 6, 0))
	end)
end

local function follow(character: Model)
	if drifting then
		drifting:Disconnect()
		drifting = nil
	end
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	for _, state in { Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Ragdoll } do
		humanoid:SetStateEnabled(state, false)
	end
	camera.CameraType = Enum.CameraType.Custom
	camera.CameraSubject = humanoid
end
player.CharacterAdded:Connect(follow)

-- What you picked last time, if anything.
local function lastChoice()
	local look = player:GetAttribute("Look")
	if typeof(look) == "string" then
		local ok, choice = pcall(function()
			return HttpService:JSONDecode(look)
		end)
		if ok then
			return choice
		end
	end
	return nil
end

local function chooseAnimal()
	if HatShop.isOpen() or HomeDesigner.isOpen() or GoalsPanel.isOpen() or DailyPanel.isOpen() or PetShop.isOpen()
		or Garden.isOpen() or Wardrobe.isOpen() or GardenBook.isOpen() then
		return
	end
	Hud.show(false)
	Run.show(false)
	Controls.set(false, "chooser")
	if not player.Character then
		driftRoundSquare()
	end
	local function backToPlaying()
		Controls.set(true, "chooser")
		Hud.show(true)
		Run.show(true)
	end
	-- a controller's B goes back without changing anything, once they've got an animal
	local back = if player.Character then backToPlaying else nil
	Chooser.open(lastChoice(), player:GetAttribute("Hat"), function(choice)
		Remotes.Play:FireServer(choice)
		backToPlaying()
	end, back)
end

if not player:GetAttribute("Loaded") then
	player:GetAttributeChangedSignal("Loaded"):Wait()
end
Hud.create(GoalsPanel.open, function()
	Wardrobe.open(chooseAnimal)
end, GardenBook.open)
local corner = Hud.corner()
if corner then
	GoalsPanel.start(corner)
end
chooseAnimal()
