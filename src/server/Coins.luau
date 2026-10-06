-- Coins: each player sees their own coins floating round the square (see client/Coins).
-- When they pick one up their game tells the server, which checks they were really next
-- to it, that it had come back since they last took it, and that they haven't picked up more
-- than Config.COIN_MAX_PER_MINUTE in the last minute, before adding it to their total.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Config = require(Shared.Config)
local PlayerData = require(script.Parent.PlayerData)
local RemoteGuard = require(script.Parent.RemoteGuard)

local Remotes = Shared:WaitForChild("Remotes")

local REACH = 12 -- studs: a little extra for the time messages take to arrive

local Coins = {}

function Coins.start()
	local taken: { [Player]: { [string]: number } } = {}

	local perMinute = { calls = Config.COIN_MAX_PER_MINUTE, seconds = 60 }

	Remotes.CollectCoin.OnServerEvent:Connect(function(player, coinId)
		if not RemoteGuard.allow(player, "CollectCoin") then
			return
		end
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
		if not RemoteGuard.allow(player, "CoinsPerMinute", perMinute) then
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
