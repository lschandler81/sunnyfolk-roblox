-- Clover's Hat Shop: buying hats and choosing which one to wear. The shop screen itself is
-- client/HatShop; this checks every purchase.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Builder = require(Shared.CharacterBuilder)
local Looks = require(Shared.Looks)
local PlayerData = require(script.Parent.PlayerData)
local RemoteGuard = require(script.Parent.RemoteGuard)

local Remotes = Shared:WaitForChild("Remotes")

local HatShop = {}

local function wear(player: Player, hatId: string?)
	PlayerData.update(player, function(data)
		data.hat = hatId
	end)
	if player.Character then
		Builder.setHat(player.Character, hatId)
	end
end

function HatShop.start()
	-- Returns (true) when it's bought, or (false, "a kind message") when it can't be.
	Remotes.BuyHat.OnServerInvoke = function(player, hatId)
		if not RemoteGuard.allow(player, "BuyHat") then
			return false, "Just a moment!"
		end
		local hat = typeof(hatId) == "string" and Looks.hat(hatId)
		local data = PlayerData.get(player)
		if not (hat and hat.kind == "shop" and data) then
			return false, "Clover doesn't have that one."
		end
		if table.find(data.hats, hat.id) then
			return false, "You've already got that one!"
		end
		if data.coins < hat.price then
			return false, `You need {hat.price - data.coins} more coins.`
		end
		PlayerData.update(player, function(d)
			d.coins -= hat.price
			table.insert(d.hats, hat.id)
		end)
		wear(player, hat.id)
		return true
	end

	-- Put on a hat you own, or take your hat off (nil).
	Remotes.WearHat.OnServerEvent:Connect(function(player, hatId)
		if not RemoteGuard.allow(player, "WearHat") then
			return
		end
		local data = PlayerData.get(player)
		if not data then
			return
		end
		if hatId == nil then
			wear(player, nil)
		elseif typeof(hatId) == "string" and table.find(data.hats, hatId) then
			wear(player, hatId)
		end
	end)
end

return HatShop
