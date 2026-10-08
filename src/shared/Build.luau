-- The building blocks of Sunnyfolk's world, shared by the server (which builds the town and
-- players' houses) and each player's computer (which shows a preview of a house as you
-- design it): parts in the Sunnyfolk colours, and props like lamps, benches, trees and houses.
--
-- Sizes are in web-game units times S (2.8 studs), so they're easy to compare with the web
-- game's src/world/props.js.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Sunnyfolk").Config)

local S = Config.STUDS

local C = {
	grass = Color3.fromHex("#a4d38a"),
	grassDark = Color3.fromHex("#8cc47a"),
	path = Color3.fromHex("#eed9ad"),
	plaza = Color3.fromHex("#f2e2bf"),
	plazaLight = Color3.fromHex("#f6e9cc"),
	stone = Color3.fromHex("#c9c2b2"),
	stoneDark = Color3.fromHex("#a59f91"),
	cream = Color3.fromHex("#f7e8c8"),
	creamDeep = Color3.fromHex("#e6d0a4"),
	white = Color3.fromHex("#ffffff"),
	teal = Color3.fromHex("#2f8a7c"),
	tealDeep = Color3.fromHex("#1f5f57"),
	coral = Color3.fromHex("#f07055"),
	yellow = Color3.fromHex("#f6c64a"),
	yuzu = Color3.fromHex("#f7c844"),
	yellowLight = Color3.fromHex("#fde08a"),
	lilac = Color3.fromHex("#d9b3dc"),
	skyBlue = Color3.fromHex("#9cc3d8"),
	leaf = Color3.fromHex("#6fa057"),
	leafDark = Color3.fromHex("#4f8446"),
	leafLight = Color3.fromHex("#8cbf63"),
	wood = Color3.fromHex("#b57b4a"),
	woodDark = Color3.fromHex("#8a5a36"),
	soil = Color3.fromHex("#7a5a3a"),
	water = Color3.fromHex("#8fd3e0"),
	waterLight = Color3.fromHex("#d9f6f4"),
	ink = Color3.fromHex("#2b2622"),
}
local FLOWERS = { C.coral, C.yellow, C.white, C.lilac }
local BUNTING = { C.coral, C.yellow, C.teal, C.cream, C.lilac }

local Build = {}

Build.C = C
Build.FLOWERS = FLOWERS

-- Where new parts go. Call Build.into(folder) before building.
local folder: Instance? = nil
function Build.into(parent: Instance)
	folder = parent
end

-- The same "random" trees and flowers every time.
local random = Random.new(7)
Build.random = random

---------------------------------------------------------------- parts

type Props = { [string]: any }

-- Parts smaller than Config.SHADOW_SIZE cast no shadow (see Config).
local SHADOW_SIZE = Config.SHADOW_SIZE

local function part(className: string, size: Vector3, cframe: CFrame, color: Color3, props: Props?): BasePart
	local p = Instance.new(className) :: BasePart
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanTouch = false -- nothing in the town uses touch events, so don't make physics watch for them
	if math.max(size.X, size.Y, size.Z) < SHADOW_SIZE then
		p.CastShadow = false
	end
	for key, value in pairs(props or {}) do
		(p :: any)[key] = value
	end
	-- Things you walk through aren't checked by raycasts either, unless something asks for it.
	-- (It saves physics work; nothing in the game needs to hit them.)
	if not p.CanCollide and not (props and props.CanQuery ~= nil) then
		p.CanQuery = false
	end
	p.Parent = folder
	return p
end

local function block(size: Vector3, cframe: CFrame, color: Color3, props: Props?): BasePart
	return part("Part", size, cframe, color, props)
end

local function wedge(size: Vector3, cframe: CFrame, color: Color3, props: Props?): BasePart
	return part("WedgePart", size, cframe, color, props)
end

-- A cylinder standing upright, centred on `cframe`.
local function cylinder(radius: number, height: number, cframe: CFrame, color: Color3, props: Props?): BasePart
	local p = block(Vector3.new(height, radius * 2, radius * 2), cframe * CFrame.Angles(0, 0, math.pi / 2), color, props)
	;(p :: Part).Shape = Enum.PartType.Cylinder
	return p
end

-- A flat disc facing along Z (a round window), centred on `cframe`.
local function disc(radius: number, thickness: number, cframe: CFrame, color: Color3, props: Props?): BasePart
	local p = block(Vector3.new(thickness, radius * 2, radius * 2), cframe * CFrame.Angles(0, math.pi / 2, 0), color, props)
	;(p :: Part).Shape = Enum.PartType.Cylinder
	return p
end

local function ball(diameter: number, cframe: CFrame, color: Color3, props: Props?): BasePart
	local p = block(Vector3.one * diameter, cframe, color, props)
	;(p :: Part).Shape = Enum.PartType.Ball
	return p
end

-- A squashed ball (leafy tree tops, bushes, hills).
local function blob(size: Vector3, cframe: CFrame, color: Color3, props: Props?): BasePart
	local p = block(size, cframe, color, props)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

local DECOR = { CanCollide = false } -- small things you walk straight through

-- Writing on the front (-Z) face of a part.
local function label(target: BasePart, text: string, textColor: Color3, background: Color3?, face: Enum.NormalId?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	local words = Instance.new("TextLabel")
	words.Size = UDim2.fromScale(1, 1)
	words.BackgroundTransparency = if background then 0 else 1
	words.BackgroundColor3 = background or C.cream
	words.Text = text
	words.TextColor3 = textColor
	words.Font = Enum.Font.FredokaOne
	words.TextScaled = true
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.06, 0)
	padding.PaddingRight = UDim.new(0.06, 0)
	padding.PaddingTop = UDim.new(0.12, 0)
	padding.PaddingBottom = UDim.new(0.12, 0)
	padding.Parent = words
	words.Parent = gui
	gui.Parent = target
end

local function yawAt(position: Vector3, yaw: number): CFrame
	return CFrame.new(position) * CFrame.Angles(0, yaw, 0)
end

---------------------------------------------------------------- props

local function flower(at: CFrame, color: Color3, height: number)
	cylinder(0.025 * S, height, at * CFrame.new(0, height / 2, 0), C.leafDark, DECOR)
	blob(Vector3.new(0.2, 0.14, 0.2) * S, at * CFrame.new(0, height, 0), color, DECOR)
end

-- Lamps are taller than the web game's, so the bunting between them hangs well above
-- everyone's heads (and hats).
local LAMP_H = 4.2 -- web units up to the middle of the lamp

local function lamp(at: CFrame)
	local post = LAMP_H - 0.6
	cylinder(0.34 * S, 0.25 * S, at * CFrame.new(0, 0.125 * S, 0), C.tealDeep)
	cylinder(0.1 * S, post * S, at * CFrame.new(0, (0.2 + post / 2) * S, 0), C.tealDeep)
	cylinder(0.18 * S, 0.12 * S, at * CFrame.new(0, (LAMP_H - 0.35) * S, 0), C.tealDeep)
	-- The lamp head has no light in it: the town is always in daylight, where a light barely
	-- shows but still costs phones work every frame.
	blob(Vector3.new(0.5, 0.56, 0.5) * S, at * CFrame.new(0, LAMP_H * S, 0), C.cream)
	blob(Vector3.new(0.8, 0.3, 0.8) * S, at * CFrame.new(0, (LAMP_H + 0.37) * S, 0), C.tealDeep)
	ball(0.14 * S, at * CFrame.new(0, (LAMP_H + 0.55) * S, 0), C.tealDeep, DECOR)
end

-- A string of little flags sagging between two points.
local function bunting(a: Vector3, b: Vector3)
	local n = 8
	local sag = 0.5 * S
	local points = {}
	for i = 0, n do
		local t = i / n
		table.insert(points, a:Lerp(b, t) - Vector3.new(0, math.sin(t * math.pi) * sag, 0))
	end
	for i = 1, n do
		local p, q = points[i], points[i + 1]
		block(Vector3.new(0.08, 0.08, (q - p).Magnitude), CFrame.lookAt((p + q) / 2, q), C.woodDark, DECOR)
		if i > 1 then
			local along = (q - p).Unit
			local flag = 0.42 * S
			local at = CFrame.lookAt(p, p + along:Cross(Vector3.yAxis)) * CFrame.new(0, -flag * 0.7, 0)
			block(Vector3.new(flag, flag, 0.05), at * CFrame.Angles(0, 0, math.rad(45)), BUNTING[(i % #BUNTING) + 1], DECOR)
		end
	end
end

local function bench(at: CFrame)
	for _, z in { -0.18, 0.06 } do
		block(Vector3.new(2.0, 0.1, 0.22) * S, at * CFrame.new(0, 0.52 * S, z * S), C.wood)
	end
	block(Vector3.new(2.0, 0.34, 0.08) * S, at * CFrame.new(0, 0.92 * S, -0.3 * S) * CFrame.Angles(-0.15, 0, 0), C.wood)
	for _, x in { -0.8, 0.8 } do
		block(Vector3.new(0.1, 0.52, 0.1) * S, at * CFrame.new(x * S, 0.26 * S, 0.05 * S), C.tealDeep, DECOR)
		block(Vector3.new(0.1, 0.9, 0.1) * S, at * CFrame.new(x * S, 0.45 * S, -0.28 * S), C.tealDeep, DECOR)
	end
end

local function planter(at: CFrame, w: number, d: number)
	block(Vector3.new(w, 0.5, d) * S, at * CFrame.new(0, 0.25 * S, 0), C.wood)
	block(Vector3.new(w - 0.15, 0.08, d - 0.15) * S, at * CFrame.new(0, 0.5 * S, 0), C.soil, DECOR)
	local n = math.round(w * 3)
	for i = 0, n - 1 do
		local x = -w / 2 + 0.25 + (i / (n - 1)) * (w - 0.5)
		local z = random:NextNumber(-0.5, 0.5) * (d - 0.4)
		flower(at * CFrame.new(x * S, 0.5 * S, z * S), FLOWERS[(i % #FLOWERS) + 1], random:NextNumber(0.25, 0.45) * S)
	end
end

local function bush(at: CFrame, s: number, color: Color3?)
	blob(Vector3.new(1.3, 0.9, 1.1) * s * S, at * CFrame.new(0, 0.4 * s * S, 0), color or C.leaf, DECOR)
	blob(Vector3.new(0.8, 0.7, 0.8) * s * S, at * CFrame.new(0.45 * s * S, 0.35 * s * S, 0.25 * s * S), C.leafLight, DECOR)
end

local function tree(at: CFrame, s: number, fruit: boolean?)
	cylinder(0.24 * s * S, 1.6 * s * S, at * CFrame.new(0, 0.8 * s * S, 0), C.woodDark)
	blob(Vector3.new(2.3, 1.9, 2.3) * s * S, at * CFrame.new(0, 2.5 * s * S, 0), C.leaf, DECOR)
	blob(Vector3.new(1.5, 1.3, 1.5) * s * S, at * CFrame.new(0.75 * s * S, 2.1 * s * S, 0.35 * s * S), C.leafLight, DECOR)
	blob(Vector3.new(1.4, 1.2, 1.4) * s * S, at * CFrame.new(-0.6 * s * S, 3.05 * s * S, -0.25 * s * S), C.leafDark, DECOR)
	if fruit then
		for i = 0, 5 do
			local a = i * 1.1 + 0.3
			local p = Vector3.new(math.cos(a) * 1.08, 2.1 + (i % 3) * 0.35, math.sin(a) * 1.08) * s * S
			ball(0.28 * s * S, at * CFrame.new(p), C.yuzu, DECOR)
		end
	end
end

local function fence(at: CFrame, length: number)
	local n = math.max(2, math.round(length / 0.6))
	for i = 0, n - 1 do
		local x = -length / 2 + (i / (n - 1)) * length
		block(Vector3.new(0.14, 0.8, 0.1) * S, at * CFrame.new(x * S, 0.4 * S, 0), C.cream)
	end
	for _, y in { 0.3, 0.6 } do
		block(Vector3.new(length, 0.08, 0.06) * S, at * CFrame.new(0, y * S, -0.06 * S), C.cream, DECOR)
	end
end

local function mailbox(at: CFrame, color: Color3)
	cylinder(0.06 * S, 1.1 * S, at * CFrame.new(0, 0.55 * S, 0), C.woodDark)
	blob(Vector3.new(0.42, 0.38, 0.6) * S, at * CFrame.new(0, 1.25 * S, 0), color)
	block(Vector3.new(0.04, 0.22, 0.08) * S, at * CFrame.new(0.23 * S, 1.38 * S, 0.1 * S), C.yellow, DECOR)
end

local function barrel(at: CFrame)
	cylinder(0.4 * S, 0.9 * S, at * CFrame.new(0, 0.45 * S, 0), C.wood)
	for _, y in { 0.18, 0.72 } do
		cylinder(0.42 * S, 0.06 * S, at * CFrame.new(0, y * S, 0), C.woodDark, DECOR)
	end
end

---------------------------------------------------------------- houses

type HouseOptions = {
	w: number,
	d: number,
	h: number,
	wall: Color3,
	roof: Color3,
	door: Color3,
	awning: Color3?,
	label: string?,
	sign: Color3?,
	chimney: boolean?, -- default true
	yard: boolean?, -- fences, bushes, a mailbox and a barrel; default true
	windows: { number }?, -- how far up the wall each row of windows is (0 to 1); default one row
}

local function house(at: CFrame, o: HouseOptions): CFrame
	local w, d, h = o.w * S, o.d * S, o.h * S
	local base = 0.35 * S
	block(Vector3.new(w + 0.3 * S, base, d + 0.3 * S), at * CFrame.new(0, base / 2, 0), C.stone)
	block(Vector3.new(w, h, d), at * CFrame.new(0, base + h / 2, 0), o.wall)

	-- the roof: two chunky slabs, with the triangles under them filled in
	local pitch = 0.62
	local half = w / 2 + 0.45 * S
	local slab = half / math.cos(pitch)
	local top = base + h
	for _, side in { -1, 1 } do
		local y = top + math.tan(pitch) * half / 2 - 0.05 * S
		block(Vector3.new(slab, 0.28 * S, d + 0.9 * S), at * CFrame.new(side * half / 2, y, 0) * CFrame.Angles(0, 0, -side * pitch), o.roof)
	end
	local gable = math.tan(pitch) * w / 2
	wedge(Vector3.new(d, gable, w / 2), at * CFrame.fromMatrix(Vector3.new(w / 4, top + gable / 2, 0), Vector3.zAxis, Vector3.yAxis), o.wall)
	wedge(Vector3.new(d, gable, w / 2), at * CFrame.fromMatrix(Vector3.new(-w / 4, top + gable / 2, 0), -Vector3.zAxis, Vector3.yAxis), o.wall)
	if o.chimney ~= false then
		block(Vector3.new(0.6, 1.3, 0.6) * S, at * CFrame.new(w * 0.25, top + 1.2 * S, -d * 0.15), C.stoneDark)
		block(Vector3.new(0.75, 0.18, 0.75) * S, at * CFrame.new(w * 0.25, top + 1.9 * S, -d * 0.15), C.stone)
	end

	-- the front door, with a round top and a step
	local front = d / 2
	block(Vector3.new(1.2, 1.7, 0.16) * S, at * CFrame.new(0, base + 0.85 * S, front + 0.02 * S), o.door)
	disc(0.6 * S, 0.16 * S, at * CFrame.new(0, base + 1.7 * S, front + 0.02 * S), o.door)
	ball(0.14 * S, at * CFrame.new(0.4 * S, 1.25 * S, front + 0.12 * S), C.yellow, DECOR)
	block(Vector3.new(1.6, 0.14, 0.7) * S, at * CFrame.new(0, 0.07 * S, front + 0.45 * S), C.stone, DECOR)

	-- round windows with flower boxes on the front, square ones on the sides
	for _, side in { -1, 1 } do
		for _, row in ipairs(o.windows or { 0.55 }) do
			local x = side * (w / 2 - 1.0 * S)
			local y = base + h * row
			disc(0.58 * S, 0.06 * S, at * CFrame.new(x, y, front + 0.03 * S), C.white, DECOR)
			disc(0.5 * S, 0.1 * S, at * CFrame.new(x, y, front + 0.05 * S), C.skyBlue, DECOR)
			block(Vector3.new(1.0, 0.25, 0.3) * S, at * CFrame.new(x, y - 0.82 * S, front + 0.2 * S), C.wood, DECOR)
			for i = 0, 3 do
				ball(0.2 * S, at * CFrame.new(x - 0.36 * S + i * 0.24 * S, y - 0.66 * S, front + 0.2 * S), FLOWERS[i + 1], DECOR)
			end
			block(Vector3.new(0.1, 0.9, 0.9) * S, at * CFrame.new(side * (w / 2 + 0.02 * S), y, 0), C.skyBlue, DECOR)
			block(Vector3.new(0.14, 1.05, 0.12) * S, at * CFrame.new(side * (w / 2 + 0.04 * S), y, 0), C.white, DECOR)
			block(Vector3.new(0.14, 0.12, 1.05) * S, at * CFrame.new(side * (w / 2 + 0.04 * S), y, 0), C.white, DECOR)
		end
	end

	-- a striped awning
	if o.awning then
		local n = 6
		for i = 0, n - 1 do
			local x = -w / 2 + (i + 0.5) * (w / n)
			local color = if i % 2 == 1 then o.awning else C.cream
			block(Vector3.new(w / n, 0.1 * S, 1.2 * S), at * CFrame.new(x, base + h * 0.86, front + 0.55 * S) * CFrame.Angles(0.35, 0, 0), color, DECOR)
		end
	end

	-- the shop sign
	if o.label then
		local signW = math.min(o.w - 0.6, 3.2) * S
		local sign = block(Vector3.new(signW, signW / 4, 0.1 * S), at * CFrame.new(0, base + h * 0.86 + 0.75 * S, front + 0.2 * S) * CFrame.Angles(0, math.pi, 0), o.sign or C.teal, DECOR)
		label(sign, o.label, C.cream)
	end

	-- the yard: fences, bushes, a mailbox and a barrel
	if o.yard ~= false then
		for _, side in { -1, 1 } do
			fence(at * CFrame.new(side * (w / 2 + 1.4 * S), 0, 0.6 * S) * CFrame.Angles(0, math.pi / 2, 0), o.d - 0.2)
			bush(at * CFrame.new(side * (w / 2 - 0.4 * S), 0, front + 0.6 * S), 0.8)
		end
		mailbox(at * CFrame.new(w / 2 + 0.6 * S, 0, front + 1.3 * S), o.roof)
		barrel(at * CFrame.new(-w / 2 - 0.4 * S, 0, front + 1.1 * S))
	end

	return at * CFrame.new(0, 0, front + 1.1 * S)
end


Build.part = part
Build.block = block
Build.wedge = wedge
Build.cylinder = cylinder
Build.disc = disc
Build.ball = ball
Build.blob = blob
Build.label = label
Build.yawAt = yawAt
Build.flower = flower
Build.lamp = lamp
Build.bunting = bunting
Build.bench = bench
Build.planter = planter
Build.bush = bush
Build.tree = tree
Build.fence = fence
Build.mailbox = mailbox
Build.barrel = barrel
Build.house = house
Build.DECOR = DECOR
Build.SHADOW_SIZE = SHADOW_SIZE
Build.LAMP_H = LAMP_H

return Build
