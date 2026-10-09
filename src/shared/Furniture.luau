-- Furniture for the inside of players' houses (Config.ROOM), from the web game's
-- home/furniture.js and home/home.js: the rules for where a piece fits, and building the
-- rooms, the stairs and the furniture from simple parts. Shared by the server, which checks
-- every change and builds your house while you're inside (server/Interiors), and your screen,
-- which shows a piece where it would go as you decorate (client/Decorator), so both always
-- agree on what fits.
--
-- Each room is a grid of floor tiles, counted across from its left side (x) and forward from
-- its back wall (z). A piece on the floor is saved as { id, x, z, r }: the tile at its back
-- left corner, and how many quarter turns it has (at 0 it faces the front of the room). A
-- piece on a wall is saved as { id, wall, s }: which wall ("back", "left" or "right"), and the
-- tile along it where it starts (from the left of the back wall, or the back of a side wall).
--
-- A player's whole inside (Interior) is the pieces they own (`have`, placed or not), the
-- wallpapers and floors they've bought (`styles`), and each room's wallpaper, floor and pieces.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Build = require(Shared.Build)
local Config = require(Shared.Config)

local R = Config.ROOM
local S = Config.STUDS
local C, DECOR = Build.C, Build.DECOR
local block, wedge, cylinder, ball, blob = Build.block, Build.wedge, Build.cylinder, Build.ball, Build.blob

local Furniture = {}

export type Piece = { id: string, name: string, price: number, w: number, d: number, layer: string, tall: number? }
export type RoomDef = {
	id: string,
	name: string,
	short: string,
	icon: string,
	w: number,
	d: number,
	x: number,
	z: number,
	up: boolean?,
	front: { number }?,
	doors: { [string]: { { number } } }?,
	clear: { { number } }?,
	hole: { number }?,
	noHang: { [string]: any }?, -- true for a whole wall, or a list of stretches
	stairs: boolean?,
}
export type Style = { id: string, name: string, color: string, price: number, trim: string?, line: string?, tiles: boolean? }
export type Spot = { id: string, x: number?, z: number?, r: number?, wall: string?, s: number? }
export type Room = { wall: string, floor: string, items: { Spot } }
export type Interior = { have: { [string]: number }, styles: { string }, rooms: { [string]: Room } }

local PIECES: { [string]: Piece } = {}
for _, piece in R.PIECES do
	PIECES[piece.id] = piece
end
local ROOMS: { [string]: RoomDef } = {}
for _, room in R.ROOMS do
	ROOMS[room.id] = room :: any
end
local SIDES = { back = true, left = true, right = true } -- the walls things can hang on

-- A piece of furniture by its id, or nil.
function Furniture.piece(id: any): Piece?
	return if typeof(id) == "string" then PIECES[id] else nil
end

-- A room by its id ("living", "kitchen", "bedroom"), or nil.
function Furniture.room(id: any): RoomDef?
	return if typeof(id) == "string" then ROOMS[id] else nil
end

-- A wallpaper (`kind` "wall") or floor ("floor") by its id, or nil.
function Furniture.style(kind: any, id: any): Style?
	local list = if kind == "wall" then R.WALLS elseif kind == "floor" then R.FLOORS else nil
	for _, style in list or {} do
		if style.id == id then
			return style :: any
		end
	end
	return nil
end

---------------------------------------------------------------- what fits

-- How many tiles across and deep a floor piece covers, turned `r` quarter turns.
function Furniture.footprint(piece: Piece, r: number?): (number, number)
	if (r or 0) % 2 == 1 then
		return piece.d, piece.w
	end
	return piece.w, piece.d
end

-- How many tiles long one of a room's walls is.
function Furniture.wallLength(room: RoomDef, wall: string): number
	return if wall == "back" or wall == "front" then room.w else room.d
end

-- Do the stretches from a1 to a2 and from b1 to b2 overlap?
local function overlap(a1: number, a2: number, b1: number, b2: number): boolean
	return a1 < b2 and b1 < a2
end

-- Can `spot` go in the room, among the pieces already there (`items`, leaving out the one at
-- `skip`, the piece being moved)? Floor pieces stay inside the room, off the doorways and
-- stairs, and off other pieces on the same layer (a rug can go under a table). Wall pieces
-- stay on a wall, off the doorways and off each other. `spot` must be a checked one
-- (Furniture.check).
function Furniture.fits(room: RoomDef, items: { Spot }, spot: Spot, skip: number?): boolean
	local piece = Furniture.piece(spot.id)
	if not piece then
		return false
	end
	if piece.layer == "wall" then
		local wall, s = spot.wall :: string, spot.s :: number
		local noHang = room.noHang and room.noHang[wall]
		if not SIDES[wall] or noHang == true then
			return false
		end
		for _, stretch in if typeof(noHang) == "table" then noHang else {} do
			if overlap(s, s + piece.w, stretch[1], stretch[1] + stretch[2]) then
				return false
			end
		end
		if s < 0 or s + piece.w > Furniture.wallLength(room, wall) then
			return false
		end
		for _, gap in (room.doors and room.doors[wall]) or {} do
			if overlap(s, s + piece.w, gap[1], gap[1] + gap[2]) then
				return false
			end
		end
		for i, other in items do
			local otherPiece = Furniture.piece(other.id)
			if i ~= skip and otherPiece and otherPiece.layer == "wall" and other.wall == wall
				and overlap(s, s + piece.w, other.s :: number, (other.s :: number) + otherPiece.w) then
				return false
			end
		end
		return true
	end
	local x, z = spot.x :: number, spot.z :: number
	local w, d = Furniture.footprint(piece, spot.r)
	if x < 0 or z < 0 or x + w > room.w or z + d > room.d then
		return false
	end
	for _, area in room.clear or {} do
		if overlap(x, x + w, area[1], area[1] + area[3]) and overlap(z, z + d, area[2], area[2] + area[4]) then
			return false
		end
	end
	for i, other in items do
		local otherPiece = Furniture.piece(other.id)
		if i ~= skip and otherPiece and otherPiece.layer == piece.layer then
			local ow, od = Furniture.footprint(otherPiece, other.r)
			if overlap(x, x + w, other.x :: number, (other.x :: number) + ow)
				and overlap(z, z + d, other.z :: number, (other.z :: number) + od) then
				return false
			end
		end
	end
	return true
end

-- A whole number from `low` to `high`, or nil.
local function whole(value: any, low: number, high: number): number?
	if typeof(value) ~= "number" or value ~= value or value % 1 ~= 0 or value < low or value > high then
		return nil
	end
	return value
end

-- A tidy copy of a spot (from a save, or sent by a player's screen), or nil if it isn't a real
-- piece in a sensible place. It doesn't say whether it fits a room: see Furniture.fits.
function Furniture.check(spot: any): Spot?
	if typeof(spot) ~= "table" then
		return nil
	end
	local piece = Furniture.piece(spot.id)
	if not piece then
		return nil
	end
	if piece.layer == "wall" then
		local s = whole(spot.s, 0, 100)
		if s and typeof(spot.wall) == "string" and SIDES[spot.wall] then
			return { id = piece.id, wall = spot.wall, s = s }
		end
		return nil
	end
	local x, z, r = whole(spot.x, 0, 100), whole(spot.z, 0, 100), whole(spot.r, 0, 3)
	if x and z and r then
		return { id = piece.id, x = x, z = z, r = r }
	end
	return nil
end

-- A free spot for a new piece: as near the middle of the room as it fits (or along a wall,
-- for a wall piece), or nil if there's nowhere.
function Furniture.findSpot(room: RoomDef, items: { Spot }, id: string): Spot?
	local piece = Furniture.piece(id)
	if not piece then
		return nil
	end
	if piece.layer == "wall" then
		for _, wall in { "back", "left", "right" } do
			for s = 0, Furniture.wallLength(room, wall) - piece.w do
				local spot = { id = id, wall = wall, s = s }
				if Furniture.fits(room, items, spot) then
					return spot
				end
			end
		end
		return nil
	end
	for _, r in { 0, 1 } do
		local w, d = Furniture.footprint(piece, r)
		local midX, midZ = math.floor((room.w - w) / 2 + 0.5), math.floor((room.d - d) / 2 + 0.5)
		for ring = 0, math.max(room.w, room.d) do
			for dx = -ring, ring do
				for dz = -ring, ring do
					if math.max(math.abs(dx), math.abs(dz)) == ring then
						local spot = { id = id, x = midX + dx, z = midZ + dz, r = r }
						if Furniture.fits(room, items, spot) then
							return spot
						end
					end
				end
			end
		end
	end
	return nil
end

---------------------------------------------------------------- what you own

-- How many of a piece are placed in all the rooms.
function Furniture.placed(interior: Interior, id: string): number
	local count = 0
	for _, room in interior.rooms do
		for _, spot in room.items do
			if spot.id == id then
				count += 1
			end
		end
	end
	return count
end

-- How many of a piece are owned but not placed yet (ready to place).
function Furniture.free(interior: Interior, id: string): number
	return (interior.have[id] or 0) - Furniture.placed(interior, id)
end

-- How many pieces are owned in all.
function Furniture.owned(interior: Interior): number
	local count = 0
	for _, n in interior.have do
		count += n
	end
	return count
end

-- Can this wallpaper or floor be used? The free ones always; the others once bought.
function Furniture.hasStyle(interior: Interior, kind: string, id: any): boolean
	local style = Furniture.style(kind, id)
	return style ~= nil and (style.price == 0 or table.find(interior.styles, style.id) ~= nil)
end

-- A new house: the free wallpaper and floor in every room, and its first piece (Config.ROOM.START).
function Furniture.blank(): Interior
	local interior: Interior = { have = {}, styles = {}, rooms = {} }
	for _, room in R.ROOMS do
		local items = {}
		for _, spot in R.START[room.id] or {} do
			table.insert(items, table.clone(spot))
			interior.have[spot.id] = (interior.have[spot.id] or 0) + 1
		end
		interior.rooms[room.id] = { wall = R.WALLS[1].id, floor = R.FLOORS[1].id, items = items }
	end
	return interior
end

-- Only keeps what makes sense from a saved inside: pieces and styles that exist, no more owned
-- than Config.ROOM.MAX_OWNED, and placed pieces that are owned and fit (one that doesn't fit is
-- put away, not lost). Nothing saved yet gives a new house.
function Furniture.tidy(saved: any): Interior
	if typeof(saved) ~= "table" then
		return Furniture.blank()
	end
	local interior: Interior = { have = {}, styles = {}, rooms = {} }
	local total = 0
	if typeof(saved.have) == "table" then
		for _, piece in R.PIECES do
			local count = saved.have[piece.id]
			if typeof(count) == "number" and count == count and count >= 1 and count ~= math.huge then
				count = math.min(math.floor(count), R.MAX_OWNED - total)
				if count > 0 then
					interior.have[piece.id] = count
					total += count
				end
			end
		end
	end
	if typeof(saved.styles) == "table" then
		for _, id in saved.styles do
			local style = Furniture.style("wall", id) or Furniture.style("floor", id)
			if style and style.price > 0 and not table.find(interior.styles, style.id) then
				table.insert(interior.styles, style.id)
			end
		end
	end
	local rooms = if typeof(saved.rooms) == "table" then saved.rooms else {}
	for _, def in R.ROOMS do
		local old = if typeof(rooms[def.id]) == "table" then rooms[def.id] else {}
		local room: Room = {
			wall = if Furniture.hasStyle(interior, "wall", old.wall) then old.wall else R.WALLS[1].id,
			floor = if Furniture.hasStyle(interior, "floor", old.floor) then old.floor else R.FLOORS[1].id,
			items = {},
		}
		interior.rooms[def.id] = room
		if typeof(old.items) == "table" then
			for _, each in old.items do
				local spot = Furniture.check(each)
				if spot and #room.items < R.MAX_PIECES and Furniture.free(interior, spot.id) > 0
					and Furniture.fits(def :: any, room.items, spot) then
					table.insert(room.items, spot)
				end
			end
		end
	end
	return interior
end

---------------------------------------------------------------- where things are

-- Puts things at (x, y, z) web units from `at`.
local function put(at: CFrame, x: number, y: number, z: number): CFrame
	return at * CFrame.new(x * S, y * S, z * S)
end

-- A size in web units, in studs.
local function size(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z) * S
end

-- The middle of a room, on top of its floor, in a house whose middle is `house`.
function Furniture.roomFrame(house: CFrame, room: RoomDef): CFrame
	return put(house, room.x, if room.up then R.UPSTAIRS else 0, room.z)
end

-- Where a piece goes in a room whose middle is `roomAt`: the middle of its tiles on the floor,
-- turned to face its way; or the middle of where it hangs, facing out from its wall.
function Furniture.spotFrame(roomAt: CFrame, room: RoomDef, spot: Spot): CFrame
	local piece = Furniture.piece(spot.id) :: Piece
	if piece.layer == "wall" then
		local along = (spot.s :: number) + piece.w / 2
		if spot.wall == "left" then
			return put(roomAt, -room.w / 2, R.WALL_Y, -room.d / 2 + along) * CFrame.Angles(0, math.pi / 2, 0)
		elseif spot.wall == "right" then
			return put(roomAt, room.w / 2, R.WALL_Y, -room.d / 2 + along) * CFrame.Angles(0, -math.pi / 2, 0)
		end
		return put(roomAt, -room.w / 2 + along, R.WALL_Y, -room.d / 2)
	end
	local w, d = Furniture.footprint(piece, spot.r)
	return put(roomAt, -room.w / 2 + (spot.x :: number) + w / 2, 0, -room.d / 2 + (spot.z :: number) + d / 2)
		* CFrame.Angles(0, (spot.r or 0) * math.pi / 2, 0)
end

-- Which room a point is in (upstairs only when it's up at the bedroom's floor), or nil (on the
-- stairs, or outside).
function Furniture.roomAt(house: CFrame, position: Vector3): RoomDef?
	local here = house:PointToObjectSpace(position) / S
	local upstairs = here.Y > R.UPSTAIRS - 1
	for _, room in R.ROOMS do
		if math.abs(here.X - room.x) <= room.w / 2 + 0.3 and math.abs(here.Z - room.z) <= room.d / 2 + 0.3
			and (room.up == true) == upstairs then
			return room :: any
		end
	end
	return nil
end

-- Where you stand when you come in: just inside the living room's front door, facing in.
function Furniture.entrance(house: CFrame): CFrame
	local living = ROOMS.living
	-- (a CFrame with no turn faces -Z, which is into the room)
	return put(Furniture.roomFrame(house, living), 0, 0, living.d / 2 - 1.6)
end

-- Just inside the living room's front door, on the floor (where the Go outside button is).
function Furniture.frontDoor(house: CFrame): CFrame
	local living = ROOMS.living
	local front = living.front or { 0, 0 }
	return put(Furniture.roomFrame(house, living), -living.w / 2 + front[1] + front[2] / 2, 0, living.d / 2 - 0.6)
end

---------------------------------------------------------------- building the furniture

local WOOD = Color3.fromHex("#c08a5a")
local WOOD_DARK = Color3.fromHex("#8f5f3a")
local CORAL_LIGHT = Color3.fromHex("#f79a7f")
local SHEET = Color3.fromHex("#fff6e6")
local POT = Color3.fromHex("#d27b56")
local POT_RIM = Color3.fromHex("#bf6a48")
local IRON = Color3.fromHex("#4a4f5c")
local IRON_DARK = Color3.fromHex("#3a3e48")
local GLOW = Color3.fromHex("#ffb04a")
local BULB = Color3.fromHex("#fff1b8")
local SKY = Color3.fromHex("#cdeefa")
local BOOKS = { C.coral, C.teal, C.yellow, C.lilac, C.skyBlue, C.leaf }

-- Each piece, built round `at`: the middle of its tiles on the floor (or the middle of where it
-- hangs on its wall), facing +Z. Sizes are the web game's.
local MAKE: { [string]: (CFrame) -> () } = {}

MAKE.bed = function(at)
	block(size(1.9, 0.45, 2.8), put(at, 0, 0.225, 0), WOOD, DECOR)
	blob(size(1.8, 0.32, 2.7), put(at, 0, 0.55, 0), SHEET, DECOR)
	blob(size(1.86, 0.3, 1.8), put(at, 0, 0.62, 0.45), C.coral, DECOR) -- the quilt
	blob(size(1.1, 0.26, 0.55), put(at, 0, 0.78, -0.95), C.white, DECOR) -- the pillow
	blob(size(1.95, 1.3, 0.22), put(at, 0, 0.75, -1.38), WOOD, DECOR) -- the headboard
	ball(0.24 * S, put(at, 0, 1.28, -1.3), C.yellow, DECOR)
end

MAKE.rug = function(at)
	cylinder(1.42 * S, 0.04 * S, put(at, 0, 0.02, 0), CORAL_LIGHT, DECOR)
	cylinder(1.05 * S, 0.04 * S, put(at, 0, 0.035, 0), C.cream, DECOR)
	cylinder(0.62 * S, 0.04 * S, put(at, 0, 0.05, 0), C.coral, DECOR)
end

MAKE.armchair = function(at)
	blob(size(1.5, 0.55, 1.4), put(at, 0, 0.3, 0.05), C.teal, DECOR)
	blob(size(1.3, 0.22, 1.1), put(at, 0, 0.6, 0.15), C.cream, DECOR) -- the cushion
	blob(size(1.55, 1.1, 0.45), put(at, 0, 0.8, -0.55), C.teal, DECOR) -- the back
	for _, side in { -1, 1 } do
		blob(size(0.36, 0.6, 1.3), put(at, 0.62 * side, 0.6, 0.05), C.teal, DECOR)
	end
end

MAKE.bookshelf = function(at)
	block(size(1.8, 1.9, 0.6), put(at, 0, 0.95, -0.12), WOOD, DECOR)
	for shelf, y in { 0.42, 1.02, 1.6 } do
		block(size(1.6, 0.5, 0.1), put(at, 0, y + 0.02, 0.13), WOOD_DARK, DECOR)
		for i = 0, 2 do
			local tall = 0.36 + ((i + shelf) % 3) * 0.04
			block(size(0.3, tall, 0.36), put(at, -0.5 + i * 0.42, y - 0.21 + tall / 2, 0.02), BOOKS[(shelf * 2 + i) % #BOOKS + 1], DECOR)
		end
	end
end

MAKE.plant = function(at)
	cylinder(0.27 * S, 0.45 * S, put(at, 0, 0.225, 0), POT, DECOR)
	cylinder(0.31 * S, 0.08 * S, put(at, 0, 0.45, 0), POT_RIM, DECOR)
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2
		-- each leaf leans out from the middle
		blob(size(0.24, 0.62, 0.12), put(at, math.sin(a) * 0.12, 0.78, math.cos(a) * 0.12) * CFrame.Angles(0, a, 0) * CFrame.Angles(0.45, 0, 0),
			if i % 2 == 1 then C.leaf else C.leafDark, DECOR)
	end
end

MAKE.stove = function(at)
	block(size(1.5, 1.0, 0.75), put(at, 0, 0.55, -0.05), IRON, DECOR)
	block(size(1.6, 0.12, 0.85), put(at, 0, 1.1, -0.05), IRON_DARK, DECOR)
	block(size(0.8, 0.5, 0.06), put(at, 0, 0.52, 0.33), Color3.fromHex("#2a2d35"), DECOR) -- the little window
	blob(size(0.5, 0.36, 0.1), put(at, 0, 0.5, 0.36), GLOW, { CanCollide = false, Material = Enum.Material.Neon }) -- the fire
	cylinder(0.12 * S, 1.4 * S, put(at, 0.45, 1.85, -0.2), IRON_DARK, DECOR) -- the chimney pipe
end

MAKE.table = function(at)
	cylinder(0.85 * S, 0.12 * S, put(at, 0, 0.78, 0), WOOD, DECOR)
	cylinder(0.14 * S, 0.72 * S, put(at, 0, 0.38, 0), WOOD_DARK, DECOR)
	cylinder(0.48 * S, 0.08 * S, put(at, 0, 0.04, 0), WOOD_DARK, DECOR)
	cylinder(0.15 * S, 0.22 * S, put(at, 0.3, 0.95, 0.1), C.cream, DECOR) -- a vase
	ball(0.2 * S, put(at, 0.3, 1.1, 0.1), C.coral, DECOR) -- with a flower
end

MAKE.stool = function(at)
	blob(size(0.76, 0.22, 0.76), put(at, 0, 0.55, 0), C.coral, DECOR)
	for i = 0, 2 do
		local a = i / 3 * math.pi * 2
		cylinder(0.05 * S, 0.48 * S, put(at, math.sin(a) * 0.24, 0.24, math.cos(a) * 0.24), WOOD_DARK, DECOR)
	end
end

MAKE.wardrobe = function(at)
	block(size(1.7, 2.2, 0.7), put(at, 0, 1.15, -0.1), C.teal, DECOR)
	block(size(1.8, 0.14, 0.8), put(at, 0, 2.3, -0.1), C.tealDeep, DECOR)
	block(size(0.04, 1.9, 0.04), put(at, 0, 1.15, 0.26), C.tealDeep, DECOR) -- between the doors
	for _, side in { -1, 1 } do
		ball(0.12 * S, put(at, 0.15 * side, 1.2, 0.28), C.yellow, DECOR)
	end
end

MAKE.lamp = function(at)
	cylinder(0.32 * S, 0.08 * S, put(at, 0, 0.04, 0), WOOD_DARK, DECOR)
	cylinder(0.04 * S, 1.6 * S, put(at, 0, 0.85, 0), WOOD_DARK, DECOR)
	ball(0.26 * S, put(at, 0, 1.62, 0), BULB, { CanCollide = false, Material = Enum.Material.Neon })
	cylinder(0.3 * S, 0.45 * S, put(at, 0, 1.75, 0), C.cream, DECOR) -- the shade
end

MAKE.petBed = function(at)
	cylinder(0.45 * S, 0.22 * S, put(at, 0, 0.11, 0), CORAL_LIGHT, DECOR)
	cylinder(0.33 * S, 0.08 * S, put(at, 0, 0.2, 0), C.cream, DECOR) -- the cushion
	ball(0.18 * S, put(at, 0.24, 0.3, 0.24), C.yellow, DECOR) -- a ball to play with
end

-- A painting of a sunny meadow, in a wooden frame.
MAKE.picture = function(at)
	block(size(1.5, 1.2, 0.1), put(at, 0, 0, 0.05), WOOD, DECOR)
	block(size(1.3, 1.0, 0.04), put(at, 0, 0, 0.11), SKY, DECOR)
	block(size(1.3, 0.3, 0.03), put(at, 0, -0.35, 0.13), C.leaf, DECOR)
	blob(size(0.8, 0.4, 0.02), put(at, 0.25, -0.25, 0.135), C.leafLight, DECOR) -- a hill
	ball(0.28 * S, put(at, -0.35, 0.22, 0.13), C.yellow, DECOR) -- the sun
	for _, x in { -0.42, -0.02 } do
		ball(0.1 * S, put(at, x, -0.32, 0.15), C.coral, DECOR)
	end
end

-- Builds a piece at `at` (see MAKE), as a Model. It has one invisible "Hit" part over it:
-- what you bump into (for floor pieces) and what a tap finds when you pick it up to move it.
function Furniture.build(id: string, at: CFrame): Model
	local piece = PIECES[id]
	local model = Instance.new("Model")
	model.Name = id
	Build.into(model)
	MAKE[id](at)
	local hit = { Name = "Hit", Transparency = 1, CastShadow = false, CanQuery = true }
	if piece.layer == "floor" then
		local tall = piece.tall or 1
		block(size(piece.w - 0.24, tall, piece.d - 0.24), put(at, 0, tall / 2, 0), C.white, hit)
	elseif piece.layer == "rug" then
		hit.CanCollide = false
		block(size(piece.w, 0.1, piece.d), put(at, 0, 0.05, 0), C.white, hit)
	else
		hit.CanCollide = false
		block(size(piece.w * 0.8, 1.3, 0.25), put(at, 0, 0, 0.12), C.white, hit)
	end
	model.WorldPivot = at
	return model
end

---------------------------------------------------------------- building the rooms

local CAP = Color3.fromHex("#8a5a36") -- the wooden tops of the walls
local RAIL = Color3.fromHex("#fff6e6") -- the rail along the panelling
local MAT = Color3.fromHex("#e7b36d")
local INVISIBLE = { Transparency = 1, CastShadow = false }

-- Starts a Model called "Wall" in `shell` for the next parts: a tall thing your screen fades
-- to see-through when it's between the camera and your animal (client/Decorator).
local function wallModel(shell: Model)
	local wall = Instance.new("Model")
	wall.Name = "Wall"
	wall.Parent = shell
	Build.into(wall)
end

-- A tall wall along one side of a room, with gaps for its doorways: wallpaper, a panelled lower
-- part with a rail on the inside, and a wooden cap along the top. The back and front walls
-- reach over the corners; the side walls reach from the back to the front one. Each stretch of
-- wall is its own "Wall" model (see wallModel). The living room's front wall has the front door
-- painted on its inside (you go out with the "Go outside" button there, client/Decorator).
local function tallWall(shell: Model, at: CFrame, room: RoomDef, side: string, paper: Color3, trim: Color3, floor: Color3)
	local W, D, H = room.w, room.d, R.WALL_H
	local length = Furniture.wallLength(room, side)
	-- a point `along` the wall (tiles from its start), `out` from its inside face, `y` up
	local function on(along: number, out: number, y: number): CFrame
		if side == "left" then
			return put(at, -W / 2 - out, y, -D / 2 + along) * CFrame.Angles(0, math.pi / 2, 0)
		elseif side == "right" then
			return put(at, W / 2 + out, y, -D / 2 + along) * CFrame.Angles(0, -math.pi / 2, 0)
		elseif side == "front" then
			return put(at, -W / 2 + along, y, D / 2 + out) * CFrame.Angles(0, math.pi, 0)
		end
		return put(at, -W / 2 + along, y, -D / 2 - out)
	end
	local gaps = table.clone((room.doors and room.doors[side]) or {})
	table.sort(gaps, function(a, b)
		return a[1] < b[1]
	end)
	local across = side == "back" or side == "front"
	local runs, from = {}, if across then -0.3 else 0
	for _, gap in gaps do
		if gap[1] > from then
			table.insert(runs, { from, gap[1] })
		end
		from = gap[1] + gap[2]
		-- a bit of floor across the doorway, to the next room's
		block(size(gap[2], 0.2, 0.3), on(gap[1] + gap[2] / 2, 0.15, -0.1), floor)
	end
	local to = length + 0.3
	if to > from then
		table.insert(runs, { from, to })
	end
	for _, run in runs do
		local a, b = run[1], run[2]
		wallModel(shell)
		block(size(b - a, H, 0.3), on((a + b) / 2, 0.15, H / 2), paper)
		block(size(b - a + 0.1, 0.14, 0.4), on((a + b) / 2, 0.15, H + 0.07), CAP, DECOR)
		-- the panelling only shows inside the room, and stops either side of the front door
		local door = if side == "front" then room.front else nil
		local stretches = if door
			then { { math.max(a, 0), door[1] + 0.2 }, { door[1] + door[2] - 0.2, math.min(b, length) } }
			else { { math.max(a, 0), math.min(b, length) } }
		for _, stretch in stretches do
			local inA, inB = stretch[1], stretch[2]
			if inB > inA then
				block(size(inB - inA, 1.0, 0.04), on((inA + inB) / 2, -0.02, 0.5), trim, DECOR)
				block(size(inB - inA, 0.09, 0.09), on((inA + inB) / 2, -0.045, 1.0), RAIL, DECOR)
			end
		end
	end
	local door = if side == "front" then room.front else nil
	if door then
		-- the front door, with its frame and a knob
		local middle = door[1] + door[2] / 2
		block(size(door[2] - 0.4, 2.25, 0.05), on(middle, -0.02, 1.125), WOOD_DARK, DECOR)
		block(size(door[2] - 0.6, 2.1, 0.08), on(middle, -0.05, 1.05), C.coral, DECOR)
		ball(0.16 * S, on(middle + 0.45, -0.12, 1.05), C.yellow, DECOR)
	end
	Build.into(shell)
end

-- The stairs up the living room's right side (Config.ROOM.STAIRS): steps on an invisible ramp,
-- a banister on the open side, and a landing at the top reaching across to the bedroom door.
local function stairs(at: CFrame, room: RoomDef)
	local st = R.STAIRS
	local up = R.UPSTAIRS
	local inside = -room.w / 2 + st.x -- the open side, towards the middle of the room
	local mid = inside + st.w / 2
	local run = st.bottom - st.top
	-- what you walk up (a wedge rises towards its own +Z, so it's turned to rise towards the back)
	wedge(size(st.w, up, run), put(at, mid, up / 2, (st.bottom + st.top) / 2) * CFrame.Angles(0, math.pi, 0), C.white, INVISIBLE)
	local step = run / st.steps
	for i = 1, st.steps do
		local tall = up * (i - 0.5) / st.steps
		block(size(st.w, tall, step), put(at, mid, tall / 2, st.bottom - (i - 0.5) * step), if i % 2 == 0 then WOOD else WOOD_DARK, DECOR)
	end
	-- a cupboard under the top, holding up the bedroom floor where the stairs arrive
	local back = -room.d / 2
	block(size(st.w, up - 0.2, st.top - back), put(at, mid, (up - 0.2) / 2, (st.top + back) / 2), WOOD_DARK)
	-- the banister: a sloping rail on posts. An invisible wall under its higher part stops
	-- anyone falling off (the bottom steps are left open, so you can step on from the side).
	-- Upstairs, the bedroom's own banister carries on round the hole (see buildRoom).
	local slope = math.atan(up / run)
	local long = math.sqrt(run * run + up * up)
	local rail = put(at, inside + 0.06, up / 2 + 0.9, (st.bottom + st.top) / 2) * CFrame.Angles(slope, 0, 0)
	block(size(0.12, 0.12, long), rail, WOOD_DARK, DECOR)
	local open = st.guardFrom -- how far up the stairs (0 to 1) the invisible wall starts
	local guardMid = (open + 1) / 2
	block(size(0.1, 1.2, long * (1 - open)), put(at, inside + 0.06, guardMid * up + 0.6, st.bottom - guardMid * run) * CFrame.Angles(slope, 0, 0), C.white, INVISIBLE)
	for _, t in { 0.04, 0.5, 0.96 } do
		cylinder(0.05 * S, 0.9 * S, put(at, inside + 0.06, t * up + 0.45, st.bottom - t * run), WOOD_DARK, DECOR)
	end
end

-- Calls `lay(x1, x2, z1, z2)` for each part of a room's floor (tiles from its back left): the
-- whole floor, or four pieces round its stairs `hole` (empty pieces are left out).
local function aroundHole(room: RoomDef, lay: (number, number, number, number) -> ())
	local W, D, hole = room.w, room.d, room.hole
	local pieces = if hole
		then {
			{ 0, hole[1], 0, D }, -- left of the hole
			{ hole[1] + hole[3], W, 0, D }, -- right of it
			{ hole[1], hole[1] + hole[3], 0, hole[2] }, -- behind it
			{ hole[1], hole[1] + hole[3], hole[2] + hole[4], D }, -- in front of it
		}
		else { { 0, W, 0, D } }
	for _, piece in pieces do
		if piece[2] > piece[1] and piece[4] > piece[3] then
			lay(piece[1], piece[2], piece[3], piece[4])
		end
	end
end

-- Builds a room with its wallpaper and floor (`state`, from the player's Interior), round
-- `at` (Furniture.roomFrame), as a Model: like the web game's room with its roof off, so you
-- can see in from above, and walls all round (your screen fades the ones in the camera's way).
-- Its furniture is built separately (Furniture.build).
function Furniture.buildRoom(room: RoomDef, state: Room, at: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "Shell"
	Build.into(model)
	local wallStyle = Furniture.style("wall", state.wall) or (R.WALLS[1] :: any)
	local floorStyle = Furniture.style("floor", state.floor) or (R.FLOORS[1] :: any)
	local paper, trim = Color3.fromHex(wallStyle.color), Color3.fromHex(wallStyle.trim)
	local ground, line = Color3.fromHex(floorStyle.color), Color3.fromHex(floorStyle.line)
	local W, D = room.w, room.d

	-- the floor (round the stairs' hole, upstairs), on a stone base downstairs; upstairs it sits
	-- on the walls below
	aroundHole(room, function(x1, x2, z1, z2)
		block(size(x2 - x1, 0.2, z2 - z1), put(at, -W / 2 + (x1 + x2) / 2, -0.1, -D / 2 + (z1 + z2) / 2), ground)
		-- planks (lines one way) or tiles (both ways)
		for i = x1 + 1, x2 - 1 do
			block(size(0.04, 0.02, z2 - z1), put(at, -W / 2 + i, 0.005, -D / 2 + (z1 + z2) / 2), line, DECOR)
		end
		if floorStyle.tiles then
			for j = z1 + 1, z2 - 1 do
				block(size(x2 - x1, 0.02, 0.04), put(at, -W / 2 + (x1 + x2) / 2, 0.005, -D / 2 + j), line, DECOR)
			end
		end
	end)
	if not room.up then
		block(size(W + 0.6, 0.3, D + 0.6), put(at, 0, -0.25, 0), C.stone)
	end
	local hole = room.hole
	if hole then
		-- a banister along the hole's open side, carrying on from the stairs' one, with an
		-- invisible wall under it so nobody falls down the stairwell
		local x = -W / 2 + hole[1] - 0.06
		local z1, z2 = -D / 2 + hole[2], -D / 2 + hole[2] + hole[4]
		block(size(0.12, 0.12, z2 - z1), put(at, x, 0.9, (z1 + z2) / 2), WOOD_DARK, DECOR)
		block(size(0.1, 1.2, z2 - z1), put(at, x, 0.6, (z1 + z2) / 2), C.white, INVISIBLE)
		for _, z in { z1 + 0.06, (z1 + z2) / 2, z2 - 0.1 } do
			cylinder(0.05 * S, 0.9 * S, put(at, x, 0.45, z), WOOD_DARK, DECOR)
		end
	end

	for _, side in { "back", "left", "right", "front" } do
		tallWall(model, at, room, side, paper, trim, ground)
	end

	local front = room.front
	if front then
		-- a doormat inside the front door
		blob(size(1.6, 0.06, 0.8), put(at, -W / 2 + front[1] + front[2] / 2, 0.02, D / 2 - 0.5), MAT, DECOR)
	end
	if room.stairs then
		stairs(at, room)
	end
	return model
end

-- The lawn round a house whose middle is `house`, with invisible walls at its edges and trees
-- along the back, as a Model.
function Furniture.buildLawn(house: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "Lawn"
	Build.into(model)
	local lawn = R.LAWN
	block(size(lawn.w, 0.4, lawn.d), put(house, lawn.x, -0.32, lawn.z), C.grass)
	for _, side in { -1, 1 } do
		block(size(lawn.w, 6, 0.5), put(house, lawn.x, 3, lawn.z + side * lawn.d / 2), C.white, INVISIBLE)
		block(size(0.5, 6, lawn.d), put(house, lawn.x + side * lawn.w / 2, 3, lawn.z), C.white, INVISIBLE)
	end
	local back = lawn.z - lawn.d / 2 + 3
	for i, x in { -16, -4, 9, 20 } do
		Build.tree(put(house, x, -0.12, back + (i % 2)), 1.1)
	end
	for _, x in { -18, 21 } do
		Build.bush(put(house, x, -0.12, 6), 1.2)
	end
	return model
end

return Furniture
