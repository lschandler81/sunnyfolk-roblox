-- The coins floating round the square. Everyone has their own coins, so nobody can take
-- yours. Walk into one to pick it up; it comes back a few minutes later.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Config = require(Shared.Config)

local Remotes = Shared:WaitForChild("Remotes")
local player = Players.LocalPlayer

local Coins = {}

local GOLD = Color3.fromHex("#f6c64a")
local SHINE = Color3.fromHex("#fde08a")
local LEAF = Color3.fromHex("#6fa057")

local function coinModel(): Model
	local model = Instance.new("Model")
	local function piece(size: Vector3, offset: CFrame, color: Color3, shape: Enum.PartType)
		local p = Instance.new("Part")
		p.Shape = shape
		p.Size = size
		p.CFrame = offset
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Parent = model
		return p
	end
	-- a cylinder on its side (its round faces look along Z), with a shiny middle
	local face = CFrame.Angles(0, math.pi / 2, 0)
	piece(Vector3.new(0.26, 1.9, 1.9), face, GOLD, Enum.PartType.Cylinder)
	piece(Vector3.new(0.3, 1.3, 1.3), face, SHINE, Enum.PartType.Cylinder)
	piece(Vector3.new(0.12, 0.3, 0.5), CFrame.new(0.15, 0.95, 0) * CFrame.Angles(0, 0, 0.5), LEAF, Enum.PartType.Block)
	model.WorldPivot = CFrame.identity
	return model
end

function Coins.start()
	local folder = Instance.new("Folder")
	folder.Name = "MyCoins"
	folder.Parent = Workspace

	type Coin = { id: string, position: Vector3, model: Model, phase: number, back: number }
	local coins: { Coin } = {}
	local template = coinModel()
	for _, info in Config.COINS do
		local model = template:Clone()
		model.Name = info.id
		model:PivotTo(CFrame.new(info.position))
		model.Parent = folder
		table.insert(coins, { id = info.id, position = info.position, model = model, phase = math.random() * 6, back = 0 })
	end

	local function pickUp(coin: Coin)
		coin.back = os.clock() + Config.COIN_RETURN_SECONDS
		Remotes.CollectCoin:FireServer(coin.id)
		-- a little hop and spin as it goes
		local shown = coin.model
		local value = Instance.new("NumberValue")
		value.Changed:Connect(function(k)
			local spin = CFrame.Angles(0, k * 20, 0)
			shown:PivotTo(CFrame.new(coin.position + Vector3.new(0, k * 4, 0)) * spin)
			shown:ScaleTo(math.max(0.05, 1.3 - k))
		end)
		local tween = TweenService:Create(value, TweenInfo.new(0.4), { Value = 1 })
		tween.Completed:Connect(function()
			value:Destroy()
			shown.Parent = nil
			shown:ScaleTo(1)
		end)
		tween:Play()
	end

	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		local character = player.Character
		local root = character and character.PrimaryPart
		for _, coin in coins do
			if coin.back > 0 then
				if now >= coin.back then
					coin.back = 0
					coin.model.Parent = folder
				else
					continue
				end
			end
			local bob = math.sin(now * 2 + coin.phase) * 0.35
			coin.model:PivotTo(CFrame.new(coin.position + Vector3.new(0, bob, 0)) * CFrame.Angles(0, now * 2.4 + coin.phase, 0))
			if root then
				local gap = root.Position - coin.position
				if Vector3.new(gap.X, 0, gap.Z).Magnitude < Config.COIN_PICK_RADIUS and math.abs(gap.Y) < 4 then
					pickUp(coin)
				end
			end
		end
	end)
end

return Coins
