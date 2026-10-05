-- Starts the game on each player's computer: the welcome screen first, then the town with
-- coins, talking, the Hat Shop, homes and the animals' animation.

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
local HatShop = require(script.Parent.HatShop)
local HomeDesigner = require(script.Parent.HomeDesigner)
local Homes = require(script.Parent.Homes)
local Hud = require(script.Parent.Hud)
local Prompts = require(script.Parent.Prompts)
local Talk = require(script.Parent.Talk)

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- Roblox's own backpack, health bar and emotes aren't used here.
for _, kind in { Enum.CoreGuiType.Backpack, Enum.CoreGuiType.Health, Enum.CoreGuiType.EmotesMenu } do
	pcall(function()
		StarterGui:SetCoreGuiEnabled(kind, false)
	end)
end

-- No chat box at all, if Config.PLAYER_CHAT is turned off.
if not Config.PLAYER_CHAT then
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
Coins.start()
Talk.start(HatShop.open)
Homes.start(Hud.toast)

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
	if HatShop.isOpen() or HomeDesigner.isOpen() then
		return
	end
	Hud.show(false)
	Controls.set(false)
	if not player.Character then
		driftRoundSquare()
	end
	Chooser.open(lastChoice(), player:GetAttribute("Hat"), function(choice)
		Remotes.Play:FireServer(choice)
		Controls.set(true)
		Hud.show(true)
	end)
end

if not player:GetAttribute("Loaded") then
	player:GetAttributeChangedSignal("Loaded"):Wait()
end
Hud.create(chooseAnimal)
chooseAnimal()
