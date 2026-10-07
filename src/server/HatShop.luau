-- The shops: Clover's Hat Shop and the Clothes Shop. Buying things and choosing what to wear.
-- The shop screen itself is client/HatShop; this checks every purchase.
--
--   Buy(shopId, itemId)          "hats" or "clothes", and the item's id. Returns (true), or
--                                (false, "a kind message").
--   Wear(shopId, itemId, slot)   put on something you own, or take it off (itemId nil: the hat,
--                                or for clothes, whatever's in `slot`).
--
-- One hat is worn at a time. Clothes go in slots (neck, body, back), one in each; the free
-- scarf is worn on the neck whenever nothing else is.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Builder = require(Shared.CharacterBuilder)
local Config = require(Shared.Config)
local Looks = require(Shared.Looks)
local Analytics = require(script.Parent.Analytics)
local Avatars = require(script.Parent.Avatars)
local Goals = require(script.Parent.Goals)
local PlayerData = require(script.Parent.PlayerData)
local RemoteGuard = require(script.Parent.RemoteGuard)

local Remotes = Shared:WaitForChild("Remotes")

local HatShop = {}

-- What each shop sells: `item(id)` finds one of its things (nil if it doesn't sell it), and
-- `owned` is where the save keeps them.
local SHOPS = {
	hats = {
		item = function(id: string)
			local hat = Looks.hat(id)
			return if hat and hat.kind == "shop" then hat else nil
		end,
		owned = "hats",
		notSold = "Clover doesn't have that one.",
	},
	clothes = {
		item = Looks.shopItem,
		owned = "clothes",
		notSold = "The shop doesn't have that one.",
	},
}

local function wearHat(player: Player, hatId: string?)
	PlayerData.update(player, function(data)
		data.hat = hatId
	end)
	if player.Character then
		Builder.setHat(player.Character, hatId)
	end
end

-- Rebuilds a player's animal in what they're now wearing: straight away, or, if it was
-- rebuilt very recently, once Config.CLOTHES_REBUILD_SECONDS have passed (with every change
-- made meanwhile).
local lastRebuild: { [Player]: number } = {}
local rebuildWaiting: { [Player]: boolean } = {}
local function rebuild(player: Player)
	if rebuildWaiting[player] then
		return -- already coming, and it'll include this change
	end
	local wait = (lastRebuild[player] or 0) + Config.CLOTHES_REBUILD_SECONDS - os.clock()
	rebuildWaiting[player] = true
	task.delay(math.max(0, wait), function()
		rebuildWaiting[player] = nil
		if player.Parent and player.Character then
			lastRebuild[player] = os.clock()
			Avatars.spawn(player)
		end
	end)
end

-- Puts `item` on (in its slot, instead of whatever was there), or empties `slot`.
local function wearClothes(player: Player, item: any, slot: string?)
	local changed = false
	PlayerData.update(player, function(data)
		local emptying = if item then item.slot else slot
		for i = #data.wearing, 1, -1 do
			local worn = Looks.shopItem(data.wearing[i])
			if not worn or worn.slot == emptying then
				table.remove(data.wearing, i)
				changed = true
			end
		end
		if item then
			table.insert(data.wearing, item.id)
			changed = true
		end
	end)
	-- Clothes are part of the animal itself, so it's rebuilt where it stands.
	if changed and player.Character then
		rebuild(player)
	end
end

function HatShop.start()
	Remotes.Buy.OnServerInvoke = function(player, shopId, itemId)
		if not RemoteGuard.allow(player, "Buy") then
			return false, "Just a moment!"
		end
		local shop = typeof(shopId) == "string" and SHOPS[shopId]
		local item = shop and typeof(itemId) == "string" and shop.item(itemId)
		local data = PlayerData.get(player)
		if not (shop and item and data) then
			return false, if shop then shop.notSold else "That shop isn't open."
		end
		local owned = (data :: any)[shop.owned]
		if table.find(owned, item.id) then
			return false, "You've already got that one!"
		end
		if data.coins < item.price then
			return false, `You need {item.price - data.coins} more coins.`
		end
		local balance, firstHat = nil, false
		PlayerData.update(player, function(d)
			firstHat = shopId == "hats" and #d.hats == 0
			d.coins -= item.price
			table.insert((d :: any)[shop.owned], item.id)
			balance = d.coins
		end)
		if not balance then
			return false, "Something went wrong. Please try again."
		end
		if shopId == "hats" then
			Analytics.coinsSpent(player, item.price, balance, `hat:{item.id}`)
			Analytics.step(player, Analytics.FIRST_HAT, firstHat)
			wearHat(player, item.id)
			Goals.event(player, "hat")
		else
			Analytics.coinsSpent(player, item.price, balance, `clothes:{item.id}`)
			wearClothes(player, item)
			Goals.event(player, "clothes", item.id)
		end
		return true
	end

	Remotes.Wear.OnServerEvent:Connect(function(player, shopId, itemId, slot)
		if not RemoteGuard.allow(player, "Wear") then
			return
		end
		local data = PlayerData.get(player)
		if not data then
			return
		end
		if shopId == "hats" then
			if itemId == nil then
				wearHat(player, nil)
			elseif typeof(itemId) == "string" and table.find(data.hats, itemId) then
				wearHat(player, itemId)
			end
		elseif shopId == "clothes" then
			if itemId == nil then
				if typeof(slot) == "string" and table.find(Looks.SLOTS, slot) then
					wearClothes(player, nil, slot)
				end
			elseif typeof(itemId) == "string" and table.find(data.clothes, itemId) then
				local item = Looks.shopItem(itemId)
				if item and not table.find(data.wearing, itemId) then
					wearClothes(player, item)
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastRebuild[player] = nil
		rebuildWaiting[player] = nil
	end)
end

return HatShop
