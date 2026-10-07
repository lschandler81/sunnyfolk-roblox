-- Pets on the server: adopting one, changing it, and buying and wearing its gear (Config.PETS).
-- The server only keeps the pet in the player's save (shown to everyone through their Pet
-- attribute); each player's own screen builds and moves the pets (client/Pets), so pets cost
-- the server nothing as they walk about.
--
-- One remote, PetAction (a RemoteFunction), with what to do and its details:
--   "adopt", kind, color, name     a new pet, for Config.PETS.ADOPT_PRICE coins
--   "change", kind, color, name    a different kind, colour or name, free (once you've one)
--   "buy", gearId                  buy a collar or something for its head (and put it on)
--   "wear", gearId                 put on something you own
--   "off", slot                    take off its "collar" or "top"
-- It returns (true), or (false, "a kind message"). Colours and names are numbers into the
-- lists in Config.PETS, so nobody ever types a name.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Config = require(Shared.Config)
local Analytics = require(script.Parent.Analytics)
local Goals = require(script.Parent.Goals)
local PlayerData = require(script.Parent.PlayerData)
local RemoteGuard = require(script.Parent.RemoteGuard)

local Remotes = Shared:WaitForChild("Remotes")

local PETS = Config.PETS

local Pets = {}

-- A whole number from `low` to `high`, or nil.
local function pick(value: any, low: number, high: number): number?
	if typeof(value) ~= "number" or value ~= value or value % 1 ~= 0 or value < low or value > high then
		return nil
	end
	return value
end

-- Checks the kind, colour and name a player picked. nil if any doesn't make sense.
local function checkLook(kind: any, color: any, name: any): (string?, number?, number?)
	local info = typeof(kind) == "string" and PETS.KINDS[kind]
	if not info then
		return nil, nil, nil
	end
	local c = pick(color, 1, #info.colors)
	local n = pick(name, 1, #PETS.NAMES)
	if not (c and n) then
		return nil, nil, nil
	end
	return kind, c, n
end

local function action(player: Player, what: any, a: any, b: any, c: any): (boolean, string?)
	local data = PlayerData.get(player)
	if not data then
		return false, "Just a moment!"
	end

	if what == "adopt" or what == "change" then
		local kind, color, name = checkLook(a, b, c)
		if not (kind and color and name) then
			return false, "Something went wrong. Please try again."
		end
		if what == "change" then
			if not data.pet then
				return false, "Adopt a pet first!"
			end
			PlayerData.update(player, function(d)
				if d.pet then
					d.pet.kind, d.pet.color, d.pet.name = kind, color, name
				end
			end)
			return true
		end
		if data.pet then
			return false, "You've already got a pet!"
		end
		if data.coins < PETS.ADOPT_PRICE then
			return false, `You need {PETS.ADOPT_PRICE - data.coins} more coins.`
		end
		local balance = nil
		PlayerData.update(player, function(d)
			d.coins -= PETS.ADOPT_PRICE
			d.pet = { kind = kind, color = color, name = name }
			balance = d.coins
		end)
		if not balance then
			return false, "Something went wrong. Please try again."
		end
		Analytics.coinsSpent(player, PETS.ADOPT_PRICE, balance, `pet:{kind}`)
		Goals.event(player, "pet")
		return true
	end

	if not data.pet then
		return false, "Adopt a pet first!"
	end

	if what == "buy" or what == "wear" then
		local gear = typeof(a) == "string" and Config.petGear(a)
		if not gear then
			return false, "The shop doesn't have that one."
		end
		local owned = table.find(data.petGear, gear.id) ~= nil
		if what == "buy" then
			if owned then
				return false, "You've already got that one!"
			end
			if data.coins < gear.price then
				return false, `You need {gear.price - data.coins} more coins.`
			end
			local balance = nil
			PlayerData.update(player, function(d)
				d.coins -= gear.price
				table.insert(d.petGear, gear.id)
				if d.pet then
					(d.pet :: any)[gear.slot] = gear.id -- straight on
				end
				balance = d.coins
			end)
			if not balance then
				return false, "Something went wrong. Please try again."
			end
			Analytics.coinsSpent(player, gear.price, balance, `petgear:{gear.id}`)
			return true
		end
		if not owned then
			return false, "Buy it first!"
		end
		PlayerData.update(player, function(d)
			if d.pet then
				(d.pet :: any)[gear.slot] = gear.id
			end
		end)
		return true
	end

	if what == "off" then
		if a ~= "collar" and a ~= "top" then
			return false, "Something went wrong. Please try again."
		end
		PlayerData.update(player, function(d)
			if d.pet then
				(d.pet :: any)[a] = nil
			end
		end)
		return true
	end

	return false, "Something went wrong. Please try again."
end

function Pets.start()
	Remotes.PetAction.OnServerInvoke = function(player, what, a, b, c)
		if not RemoteGuard.allow(player, "Pet") then
			return false, "Just a moment!"
		end
		return action(player, what, a, b, c)
	end
end

return Pets
