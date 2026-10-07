-- Easy ways to read assets/characters/sunnyfolk.json: the animals and their coats, the scarf
-- colours, the hats, the clothes and the residents.

local CharacterData: any = require(script.Parent.CharacterData)

local Looks = {}

Looks.data = CharacterData

-- "#c98b52" -> Color3
function Looks.color(hex: string): Color3
	return Color3.fromHex(hex)
end

function Looks.animal(species: string)
	return CharacterData.animals[species]
end

function Looks.coats(species: string): { any }
	local animal = CharacterData.animals[species]
	return if animal then animal.coats else {}
end

function Looks.coat(species: string, coatId: string?)
	local coats = Looks.coats(species)
	for _, coat in coats do
		if coat.id == coatId then
			return coat
		end
	end
	return coats[1]
end

-- The scarf colours, as hex strings.
function Looks.scarves(): { string }
	return CharacterData.scarves
end

function Looks.hat(hatId: string?)
	for _, hat in CharacterData.hats do
		if hat.id == hatId then
			return hat
		end
	end
	return nil
end

-- Hats Clover sells, cheapest first.
function Looks.shopHats(): { any }
	local list = {}
	for _, hat in CharacterData.hats do
		if hat.kind == "shop" then
			table.insert(list, hat)
		end
	end
	table.sort(list, function(a, b)
		if a.price ~= b.price then
			return a.price < b.price
		end
		return a.name < b.name
	end)
	return list
end

-- The places clothes go. One thing can be worn in each; the free scarf is worn on the neck
-- whenever nothing else is.
Looks.SLOTS = { "neck", "body", "back" }

-- Clothes the Clothes Shop sells (cheapest first): ones with a price, for one of the slots
-- above (not the residents' own aprons). Worked out once, as it never changes.
local shopClothes = {}
local shopById = {}
for _, item in CharacterData.clothes do
	if (item.price or 0) > 0 and table.find(Looks.SLOTS, item.slot) then
		table.insert(shopClothes, item)
		shopById[item.id] = item
	end
end
table.sort(shopClothes, function(a, b)
	if a.price ~= b.price then
		return a.price < b.price
	end
	return a.name < b.name
end)

-- The Clothes Shop's things (don't change the list you get back).
function Looks.shopClothes(): { any }
	return shopClothes
end

-- One of the shop's clothes, or nil if `clothesId` isn't one.
function Looks.shopItem(clothesId: string?)
	return if typeof(clothesId) == "string" then shopById[clothesId] else nil
end

function Looks.clothes(clothesId: string)
	for _, item in CharacterData.clothes do
		if item.id == clothesId then
			return item
		end
	end
	return nil
end

function Looks.held(heldId: string)
	for _, item in CharacterData.held do
		if item.id == heldId then
			return item
		end
	end
	return nil
end

function Looks.resident(residentId: string)
	for _, resident in CharacterData.residents do
		if resident.id == residentId then
			return resident
		end
	end
	return nil
end

-- What a player looks like, from what they picked: { species, coat, scarf }, the hat they're
-- wearing and the clothes they're wearing (shop clothes ids). `scarf` is a number: which of the
-- scarf colours. The scarf goes on unless something else is worn on the neck.
function Looks.playerLook(choice: { species: string, coat: string?, scarf: number? }, hat: string?, wearing: { string }?)
	local scarves = Looks.scarves()
	local clothes = {}
	local neckTaken = false
	local worn: { string } = wearing or {}
	for _, id in worn do
		local item = Looks.shopItem(id)
		if item then
			table.insert(clothes, id)
			neckTaken = neckTaken or item.slot == "neck"
		end
	end
	if not neckTaken then
		table.insert(clothes, 1, "scarf")
	end
	return {
		species = choice.species,
		coat = choice.coat,
		scarf = scarves[choice.scarf or 1] or scarves[1],
		clothes = clothes,
		hat = hat,
	}
end

-- What a resident looks like, from their entry in sunnyfolk.json.
function Looks.residentLook(resident)
	return {
		species = resident.species,
		body = string.gsub(resident.body, "%.glb$", ""),
		colors = resident.colors,
		scarf = resident.scarfColor,
		clothes = resident.clothes,
		held = resident.held,
		hat = resident.hat,
		scale = resident.scale,
	}
end

return Looks
