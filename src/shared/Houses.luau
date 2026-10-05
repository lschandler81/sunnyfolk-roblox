-- Players' own houses at Home Pond: the choices you can make (shape, colours, garden and a
-- name sign), and building a house from those choices.
--
-- Only a few choices are free to start with. To add more later (including ones to buy),
-- add entries to the lists below; Houses.check only accepts what's listed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Build = require(Shared.Build)
local Config = require(Shared.Config)

local S = Config.STUDS
local C, DECOR = Build.C, Build.DECOR
local block, cylinder, disc, ball, blob = Build.block, Build.cylinder, Build.disc, Build.ball, Build.blob

local Houses = {}

export type Option = { id: string, name: string, color: string? }
export type Design = {
	shape: string,
	wall: string,
	roof: string,
	door: string,
	garden: string,
	sign: boolean, -- a sign with the player's name over their gate
}

Houses.SHAPES = {
	{ id = "cottage", name = "Cottage" },
	{ id = "tall", name = "Tall house" },
	{ id = "round", name = "Round hut" },
} :: { Option }

Houses.WALLS = {
	{ id = "cream", name = "Cream", color = "#f7e8c8" },
	{ id = "peach", name = "Peach", color = "#fbe3d2" },
	{ id = "mint", name = "Mint", color = "#e2f1e6" },
	{ id = "sky", name = "Sky", color = "#e6eef7" },
} :: { Option }

Houses.ROOFS = {
	{ id = "teal", name = "Teal", color = "#2f8a7c" },
	{ id = "coral", name = "Coral", color = "#f07055" },
	{ id = "lilac", name = "Lilac", color = "#d9b3dc" },
	{ id = "blue", name = "Blue", color = "#5aa9d8" },
} :: { Option }

Houses.DOORS = {
	{ id = "coral", name = "Coral", color = "#f07055" },
	{ id = "forest", name = "Forest", color = "#1f5f57" },
	{ id = "sunny", name = "Sunny", color = "#f6c64a" },
	{ id = "lilac", name = "Lilac", color = "#b583b9" },
} :: { Option }

Houses.GARDENS = {
	{ id = "flowers", name = "Flowers" },
	{ id = "veg", name = "Vegetables" },
	{ id = "pond", name = "Little pond" },
} :: { Option }

Houses.DEFAULT = { shape = "cottage", wall = "cream", roof = "teal", door = "coral", garden = "flowers", sign = true } :: Design

local function find(list: { Option }, id: any): Option?
	for _, option in list do
		if option.id == id then
			return option
		end
	end
	return nil
end
Houses.find = find

-- A tidy copy of a design, or nil if anything in it isn't one of the choices.
function Houses.check(design: any): Design?
	if typeof(design) ~= "table" then
		return nil
	end
	local checked = {
		shape = design.shape,
		wall = design.wall,
		roof = design.roof,
		door = design.door,
		garden = design.garden,
		sign = design.sign == true,
	}
	if find(Houses.SHAPES, checked.shape) and find(Houses.WALLS, checked.wall) and find(Houses.ROOFS, checked.roof)
		and find(Houses.DOORS, checked.door) and find(Houses.GARDENS, checked.garden)
	then
		return checked
	end
	return nil
end

local function colorOf(list: { Option }, id: string): Color3
	local option = find(list, id) or list[1]
	return Color3.fromHex(option.color or "#ffffff")
end

---------------------------------------------------------------- shapes

-- A round hut with a pointy roof, its door facing +Z of `at`.
local function roundHut(at: CFrame, wall: Color3, roof: Color3, door: Color3)
	local r = 2.6
	local base = 0.35 * S
	cylinder((r + 0.15) * S, base, at * CFrame.new(0, base / 2, 0), C.stone)
	cylinder(r * S, 2.8 * S, at * CFrame.new(0, base + 1.4 * S, 0), wall)
	for i, tier in { { 3.3, 0.35, 3.3 }, { 2.7, 0.4, 3.65 }, { 2.0, 0.45, 4.05 }, { 1.3, 0.45, 4.45 }, { 0.6, 0.45, 4.85 } } do
		cylinder(tier[1] * S, tier[2] * S, at * CFrame.new(0, tier[3] * S, 0), if i % 2 == 0 then roof:Lerp(Color3.new(1, 1, 1), 0.2) else roof)
	end
	ball(0.5 * S, at * CFrame.new(0, 5.2 * S, 0), C.yellow)
	-- the door, with a round top and a step
	block(Vector3.new(1.2, 1.7, 0.2) * S, at * CFrame.new(0, base + 0.85 * S, (r - 0.02) * S), door)
	disc(0.6 * S, 0.2 * S, at * CFrame.new(0, base + 1.7 * S, (r - 0.02) * S), door)
	ball(0.14 * S, at * CFrame.new(0.4 * S, 1.25 * S, (r + 0.1) * S), C.yellow, DECOR)
	block(Vector3.new(1.6, 0.14, 0.7) * S, at * CFrame.new(0, 0.07 * S, (r + 0.45) * S), C.stone, DECOR)
	-- round windows either side
	for _, side in { -1, 1 } do
		local window = at * CFrame.Angles(0, side * math.rad(50), 0)
		disc(0.55 * S, 0.06 * S, window * CFrame.new(0, base + 1.6 * S, (r + 0.01) * S), C.white, DECOR)
		disc(0.47 * S, 0.1 * S, window * CFrame.new(0, base + 1.6 * S, (r + 0.03) * S), C.skyBlue, DECOR)
	end
	-- a yard like the other houses
	for _, side in { -1, 1 } do
		Build.fence(at * CFrame.new(side * (r + 1.5) * S, 0, 0.6 * S) * CFrame.Angles(0, math.pi / 2, 0), 4.2)
		Build.bush(at * CFrame.new(side * (r - 0.6) * S, 0, (r + 0.4) * S), 0.8)
	end
	Build.mailbox(at * CFrame.new(3.1 * S, 0, 3.5 * S), roof)
end

---------------------------------------------------------------- gardens

-- Two beds either side of the path to the door.
local function garden(kind: string, at: CFrame)
	for _, side in { -1, 1 } do
		local bed = at * CFrame.new(side * 1.8 * S, 0, 5.2 * S)
		if kind == "flowers" then
			Build.planter(bed * CFrame.Angles(0, math.pi / 2, 0), 3.0, 1.5)
		elseif kind == "veg" then
			block(Vector3.new(1.6, 0.2, 3.0) * S, bed * CFrame.new(0, 0.1 * S, 0), C.soil)
			for row = 0, 2 do
				for col = 0, 1 do
					local spot = bed * CFrame.new((col - 0.5) * 0.75 * S, 0.2 * S, (row - 1) * 0.95 * S)
					if (row + col + (if side > 0 then 1 else 0)) % 2 == 0 then
						-- a cabbage
						blob(Vector3.new(0.6, 0.45, 0.6) * S, spot * CFrame.new(0, 0.18 * S, 0), C.leafLight, DECOR)
					else
						-- a carrot poking out, with its leaves
						cylinder(0.12 * S, 0.12 * S, spot * CFrame.new(0, 0.04 * S, 0), C.coral, DECOR)
						blob(Vector3.new(0.3, 0.4, 0.3) * S, spot * CFrame.new(0, 0.28 * S, 0), C.leaf, DECOR)
					end
				end
			end
		elseif kind == "pond" then
			if side < 0 then
				-- a little round pond with a rubber duck
				cylinder(1.3 * S, 0.4, bed * CFrame.new(0, 0.15, 0), C.water, { CanCollide = false })
				for i = 0, 9 do
					blob(Vector3.new(0.5, 0.3, 0.4) * S, bed * CFrame.Angles(0, i / 10 * math.pi * 2, 0) * CFrame.new(0, 0.08 * S, 1.35 * S), C.stone, DECOR)
				end
				local duck = bed * CFrame.new(0.3 * S, 0.12 * S, -0.2 * S)
				ball(0.4 * S, duck, C.yellow, DECOR)
				ball(0.26 * S, duck * CFrame.new(0, 0.22 * S, -0.14 * S), C.yellow, DECOR)
				block(Vector3.new(0.12, 0.05, 0.12) * S, duck * CFrame.new(0, 0.2 * S, -0.3 * S), C.coral, DECOR)
				cylinder(0.35 * S, 0.04, bed * CFrame.new(-0.5 * S, 0.37, 0.5 * S), C.leaf, DECOR)
			else
				Build.planter(bed * CFrame.Angles(0, math.pi / 2, 0), 3.0, 1.5)
			end
		end
	end
end

---------------------------------------------------------------- building

-- Builds a house and its front garden on a plot whose middle is `at`, front facing +Z.
-- `ownerName` goes on the name sign (if the design has one). Parts go wherever
-- Build.into() last pointed.
function Houses.build(design: Design, at: CFrame, ownerName: string?)
	local wall = colorOf(Houses.WALLS, design.wall)
	local roof = colorOf(Houses.ROOFS, design.roof)
	local door = colorOf(Houses.DOORS, design.door)
	if design.shape == "round" then
		roundHut(at, wall, roof, door)
	elseif design.shape == "tall" then
		Build.house(at, { w = 4.6, d = 4.4, h = 5.2, wall = wall, roof = roof, door = door, windows = { 0.32, 0.74 } })
	else
		Build.house(at, { w = 5.2, d = 4.4, h = 3.0, wall = wall, roof = roof, door = door })
	end
	garden(design.garden, at)

	if design.sign and ownerName then
		local signAt = at * CFrame.new(-3.3 * S, 0, 8.0 * S)
		cylinder(0.1 * S, 1.8 * S, signAt * CFrame.new(0, 0.9 * S, 0), C.woodDark)
		local board = block(Vector3.new(2.8, 0.7, 0.12) * S, signAt * CFrame.new(0, 1.75 * S, 0.1 * S) * CFrame.Angles(0, math.pi, 0), C.cream, DECOR)
		Build.label(board, `{ownerName}'s House`, C.ink, C.cream)
		Build.label(board, `{ownerName}'s House`, C.ink, C.cream, Enum.NormalId.Back)
	end
end

return Houses
