-- Builds a pet (a puppy, kitten or duckling) from a few simple parts, like the web game's
-- pet.js, with no meshes: a round body and head, ears or wings, a snout or beak, eyes, legs,
-- a tail, a collar and maybe something on its head. About 15 to 20 parts.
--
-- A pet is built facing -Z with its feet on the origin. Nothing in it collides, casts a
-- shadow or is seen by raycasts, so it costs physics nothing. Its parts are only ever moved
-- by PetBuilder.pose (which gives where each part goes, for workspace:BulkMoveTo), so walking,
-- sitting, wagging and hopping are just new places for the parts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Build = require(Shared.Build)
local Config = require(Shared.Config)

local C = Build.C
local S = Config.STUDS -- the web game's sizes are in its own units

local PetBuilder = {}

export type Look = {
	kind: string, -- "puppy", "kitten" or "duckling"
	color: number, -- which of its kind's colours (Config.PETS)
	collar: string?, -- a collar's gear id
	top: string?, -- the gear id of something on its head
}

-- One part, and which bit of the pet it moves with.
type Piece = { part: BasePart, group: string, rest: CFrame }

export type Pet = {
	model: Model,
	pieces: { Piece },
	pivots: { [string]: CFrame }, -- where each bit turns from (the head at its neck, and so on)
	inverse: { [string]: CFrame }, -- each pivot turned inside out (worked out once, for pose)
	legs: { { group: string, front: boolean, offset: number } }, -- its legs, and how each swings
	kind: string,
	head: BasePart, -- for its name tag
}

-- Anchored, and nothing that costs physics: no collisions, touches, raycasts or shadows.
local PROPS = { CanCollide = false, CanTouch = false, CanQuery = false, CastShadow = false, Massless = true }

local ORANGE = Color3.fromHex("#f28a3a")
local GOLD = Color3.fromHex("#f2c14e")
local BELLY = Color3.fromHex("#faf0e0")

-- web units (x, y, z with +z forward) to studs facing -Z
local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x * S, y * S, -z * S)
end

local function darker(color: Color3, k: number): Color3
	return Color3.new(color.R * k, color.G * k, color.B * k)
end

function PetBuilder.build(look: Look): Pet
	local kind = if Config.PETS.KINDS[look.kind] then look.kind else "puppy"
	local colors = Config.PETS.KINDS[kind].colors
	local color = Color3.fromHex(colors[look.color] or colors[1])
	local dark = darker(color, 0.78)
	local collarGear = Config.petGear(look.collar)
	-- a puppy or kitten has a coral collar until it's given another; a duckling only wears one
	-- it's been given (like the web game)
	local collar = if collarGear and collarGear.color then Color3.fromHex(collarGear.color) else C.coral

	local model = Instance.new("Model")
	model.Name = "Pet"
	Build.into(model)
	local pieces: { Piece } = {}
	local function add(group: string, p: BasePart): BasePart
		table.insert(pieces, { part = p, group = group, rest = p.CFrame })
		return p
	end
	local function blob(group: string, size: Vector3, cf: CFrame, c: Color3): BasePart
		return add(group, Build.blob(size * S, cf, c, PROPS))
	end
	local function ball(group: string, d: number, cf: CFrame, c: Color3): BasePart
		return add(group, Build.ball(d * S, cf, c, PROPS))
	end
	local function cylinder(group: string, r: number, h: number, cf: CFrame, c: Color3): BasePart
		return add(group, Build.cylinder(r * S, h * S, cf, c, PROPS))
	end
	local function blockPart(group: string, size: Vector3, cf: CFrame, c: Color3): BasePart
		return add(group, Build.block(size * S, cf, c, PROPS))
	end

	local pivots: { [string]: CFrame } = { body = CFrame.identity }
	local head: BasePart

	-- something on top of the head (the head's top is about 0.25 above its middle)
	local function top(h: CFrame)
		local id = look.top
		if id == "bow" then
			for _, side in { -1, 1 } do
				blob("head", Vector3.new(0.16, 0.12, 0.07), h * at(0.06 + side * 0.08, 0.27, 0) * CFrame.Angles(0, 0, side * 0.4), C.coral)
			end
			ball("head", 0.09, h * at(0.06, 0.27, 0.02), Color3.fromHex("#d9604a"))
		elseif id == "flower" then
			-- five white petals round a yellow middle
			for i = 0, 4 do
				local a = i / 5 * math.pi * 2
				ball("head", 0.1, h * at(-0.08 + math.sin(a) * 0.06, 0.28, math.cos(a) * 0.06), C.white)
			end
			ball("head", 0.09, h * at(-0.08, 0.3, 0), C.yellow)
		elseif id == "party" then
			-- a cone in coral and white stripes, each narrower than the last, tipped a little,
			-- with a yellow pompom on top
			local cone = h * at(0.03, 0.27, 0) * CFrame.Angles(0, 0, -0.15)
			for i = 0, 3 do
				cylinder("head", 0.1 - i * 0.022, 0.065, cone * at(0, 0.033 + i * 0.062, 0), if i % 2 == 0 then C.coral else C.white)
			end
			ball("head", 0.09, cone * at(0, 0.27, 0), C.yellow)
		elseif id == "crown" then
			-- a gold band with five points standing up round it: each a little square turned on
			-- its corner, its bottom half hidden in the band
			cylinder("head", 0.1, 0.07, h * at(0, 0.29, 0), GOLD)
			for i = 0, 4 do
				local a = i / 5 * math.pi * 2
				local point = h * at(math.sin(a) * 0.082, 0.325, math.cos(a) * 0.082) * CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, math.pi / 4)
				blockPart("head", Vector3.new(0.075, 0.075, 0.025), point, GOLD)
			end
		end
	end

	if kind == "duckling" then
		blob("body", Vector3.new(0.5, 0.42, 0.56), at(0, 0.3, 0), color)
		for _, side in { -1, 1 } do
			blob("body", Vector3.new(0.1, 0.18, 0.3), at(side * 0.24, 0.32, -0.02) * CFrame.Angles(0, 0, -side * 0.3), dark)
		end
		pivots.head = at(0, 0.58, 0.14)
		local h = pivots.head
		head = ball("head", 0.4, h * at(0, 0.06, 0), color)
		blob("head", Vector3.new(0.16, 0.06, 0.16), h * at(0, 0.02, 0.2), ORANGE)
		for _, side in { -1, 1 } do
			ball("head", 0.07, h * at(side * 0.09, 0.1, 0.15), C.ink)
		end
		if collarGear then
			cylinder("head", 0.16, 0.05, h * at(0, -0.12, 0), collar)
		end
		top(h)
		for i, side in { -1, 1 } do
			local leg = `leg{i}`
			pivots[leg] = at(side * 0.1, 0.14, 0)
			blob(leg, Vector3.new(0.12, 0.05, 0.16), pivots[leg] * at(0, -0.12, 0.04), ORANGE)
		end
		pivots.tail = at(0, 0.36, -0.28)
		blob("tail", Vector3.new(0.12, 0.08, 0.14), pivots.tail * at(0, 0.03, -0.02) * CFrame.Angles(0.5, 0, 0), color)
	else
		local kitten = kind == "kitten"
		blob("body", Vector3.new(0.44, 0.4, 0.7), at(0, 0.36, 0), color)
		blob("body", Vector3.new(0.3, 0.2, 0.42), at(0, 0.26, 0.05), BELLY)
		cylinder("body", 0.17, 0.06, at(0, 0.5, 0.3) * CFrame.Angles(0.47, 0, 0), collar) -- round the neck, sloping
		ball("body", 0.09, at(0, 0.4, 0.42), C.yellow)
		pivots.head = at(0, 0.62, 0.36)
		local h = pivots.head
		head = blob("head", Vector3.new(0.44, 0.38, 0.4), h * at(0, 0.06, 0), color)
		blob("head", if kitten then Vector3.new(0.18, 0.12, 0.16) else Vector3.new(0.24, 0.16, 0.16), h * at(0, -0.02, 0.18), BELLY)
		ball("head", if kitten then 0.06 else 0.09, h * at(0, 0.03, 0.27), if kitten then Color3.fromHex("#f4a6c0") else C.ink)
		for _, side in { -1, 1 } do
			ball("head", 0.08, h * at(side * 0.1, 0.1, 0.17), C.ink)
			if kitten then
				blob("head", Vector3.new(0.13, 0.2, 0.07), h * at(side * 0.12, 0.27, -0.02) * CFrame.Angles(0, 0, side * 0.25), color)
			else
				blob("head", Vector3.new(0.12, 0.26, 0.08), h * at(side * 0.21, 0.06, -0.02) * CFrame.Angles(0, 0, -side * 0.35), dark)
			end
		end
		top(h)
		for i, spot in { { -0.12, 0.2 }, { 0.12, 0.2 }, { -0.12, -0.2 }, { 0.12, -0.2 } } do
			local leg = `leg{i}`
			pivots[leg] = at(spot[1], 0.24, spot[2])
			blob(leg, Vector3.new(0.14, 0.26, 0.14), pivots[leg] * at(0, -0.12, 0), color)
		end
		pivots.tail = at(0, 0.44, -0.32)
		local long = if kitten then 0.36 else 0.2
		blob("tail", Vector3.new(0.1, long, 0.1), pivots.tail * at(0, long / 2, -0.04) * CFrame.Angles(if kitten then 0.2 else 0.7, 0, 0), if kitten then color else dark)
	end
	-- where it sits back from: its back legs
	pivots.hips = at(0, 0.24, -0.2)

	local inverse = {}
	for name, pivot in pivots do
		inverse[name] = pivot:Inverse()
	end
	-- each leg swings opposite to its neighbour; the front ones stay upright when it sits
	local legs = {}
	for i = 1, 4 do
		local group = `leg{i}`
		if pivots[group] then
			table.insert(legs, {
				group = group,
				front = kind ~= "duckling" and i <= 2,
				offset = (if i % 2 == 0 then math.pi else 0) + (if i > 2 then math.pi else 0),
			})
		end
	end

	model.WorldPivot = CFrame.identity
	return { model = model, pieces = pieces, pivots = pivots, inverse = inverse, legs = legs, kind = kind, head = head }
end

export type Pose = {
	bob: number, -- how far the body bobs up (studs)
	sit: number, -- 0 standing to 1 sitting
	roll: number, -- the duckling's waddle
	stride: number, -- 0 standing still to 1 trotting along
	phase: number, -- where the legs are in their swing
	wag: number, -- the tail's turn
}

-- Where each of the pet's parts goes, standing at `root` (its feet, facing its -Z) in the pose
-- `p`. Adds them to `parts` and `cframes`, ready for workspace:BulkMoveTo.
local legTurns: { [string]: CFrame } = {} -- reused for every pet, every time

function PetBuilder.pose(pet: Pet, root: CFrame, p: Pose, parts: { BasePart }, cframes: { CFrame })
	local pivots, inverse = pet.pivots, pet.inverse
	-- sitting tips the body back on its back legs; the head tips forward a little to look ahead
	local sitTilt = if pet.kind == "duckling" then 0 else 0.35 * p.sit
	local body = root * CFrame.new(0, p.bob, 0) * pivots.hips * CFrame.Angles(sitTilt, 0, p.roll) * inverse.hips
	local headTurn = pivots.head * CFrame.Angles(-sitTilt * 0.7, 0, 0) * inverse.head
	local tailTurn = pivots.tail * CFrame.Angles(0, p.wag, 0) * inverse.tail
	-- the legs go with the body; the front ones turn back the other way, so they stay upright
	for _, leg in pet.legs do
		local swing = math.sin(p.phase + leg.offset) * 0.8 * p.stride - (if leg.front then sitTilt else 0)
		legTurns[leg.group] = body * pivots[leg.group] * CFrame.Angles(swing, 0, 0) * inverse[leg.group]
	end
	for _, piece in pet.pieces do
		local group = piece.group
		local cf
		if group == "head" then
			cf = body * headTurn * piece.rest
		elseif group == "tail" then
			cf = body * tailTurn * piece.rest
		elseif group == "body" then
			cf = body * piece.rest
		else
			cf = legTurns[group] * piece.rest
		end
		table.insert(parts, piece.part)
		table.insert(cframes, cf)
	end
end

-- Puts the pet straight into a pose (for a single pet, like the shop's picture).
function PetBuilder.place(pet: Pet, root: CFrame, p: Pose)
	local parts, cframes = {}, {}
	PetBuilder.pose(pet, root, p, parts, cframes)
	for i, part in parts do
		part.CFrame = cframes[i]
	end
end

-- A pet standing still, for pictures.
PetBuilder.STANDING = { bob = 0, sit = 0, roll = 0, stride = 0, phase = 0, wag = 0 } :: Pose

return PetBuilder
