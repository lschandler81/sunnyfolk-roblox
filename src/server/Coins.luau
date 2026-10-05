-- Coins: each player sees their own coins floating round the square (see client/Coins).
-- When they pick one up their game tells the server, which checks they were really next
-- to it, and that it had come back since they last took it, before adding it to their total.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Config = require(Shared.Config)
local PlayerData = require(script.Parent.PlayerData)

local Remotes = Shared:WaitForChild("Remotes")

local REACH = 12 -- studs: a little extra for the time messages take to arrive

local Coins = {}

function Coins.start()
	local taken: { [Player]: { [string]: number } } = {}

	Remotes.CollectCoin.OnServerEvent:Connect(function(player, coinId)
		local coin = typeof(coinId) == "string" and Config.COIN_BY_ID[coinId]
		local root = player.Character and player.Character.PrimaryPart
		if not (coin and root) then
			return
		end
		if (root.Position - coin.position).Magnitude > REACH then
			return
		end
		local mine = taken[player] or {}
		taken[player] = mine
		local now = os.clock()
		-- a second's grace, as the player's own timer may run a little ahead
		if mine[coinId] and now - mine[coinId] < Config.COIN_RETURN_SECONDS - 1 then
			return
		end
		mine[coinId] = now
		PlayerData.update(player, function(data)
			data.coins += 1
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		taken[player] = nil
	end)
end

return Coins
