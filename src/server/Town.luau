-- Builds the town square when the game starts: the grass, the paved plaza, the fountain, the
-- shops, lamps with bunting, benches, flower planters, trees, a signpost, and gates on the
-- roads to places that aren't built yet. It all goes in Workspace.Town.
--
-- Sizes and places follow the web game (src/world/hub.js and props.js). They're written in
-- web units times S, so they're easy to compare.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Builder = require(Shared.CharacterBuilder)
local Config = require(Shared.Config)

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

local Town = {}

local folder: Folder
local random = Random.new(7) -- the same "random" trees every time

---------------------------------------------------------------- parts

type Props = { [string]: any }

local function part(className: string, size: Vector3, cframe: CFrame, color: Color3, props: Props?): BasePart
	local p = Instance.new(className) :: BasePart
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(props or {}) do
		(p :: any)[key] = value
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
	local glow = blob(Vector3.new(0.5, 0.56, 0.5) * S, at * CFrame.new(0, LAMP_H * S, 0), C.cream)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromHex("#ffe9b8")
	light.Range = 16
	light.Brightness = 0.7
	light.Parent = glow
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

---------------------------------------------------------------- the fountain

local function fountain()
	local o = CFrame.identity
	local F = S * Config.FOUNTAIN_SCALE
	-- the basin: a stone floor and a low round wall
	cylinder(3.2 * F, 0.3 * F, o * CFrame.new(0, 0.15 * F, 0), C.stone)
	local n = 32
	local wallR = 3.05 * F
	for i = 0, n - 1 do
		local a = (i / n) * math.pi * 2
		local at = CFrame.Angles(0, a, 0) * CFrame.new(0, 0, wallR)
		local width = 2 * math.pi * wallR / n * 1.15
		block(Vector3.new(width, 0.75 * F, 0.5 * F), at * CFrame.new(0, 0.42 * F, 0), C.stone)
		block(Vector3.new(width * 1.05, 0.12 * F, 0.62 * F), at * CFrame.new(0, 0.82 * F, 0), C.stoneDark)
	end
	-- the water
	cylinder(2.86 * F, 0.1 * F, o * CFrame.new(0, 0.58 * F, 0), C.water, { CanCollide = false, Transparency = 0.1, Reflectance = 0.1 })
	-- the middle: a column, the upper bowl and a giant stone yuzu on top
	cylinder(0.42 * F, 1.5 * F, o * CFrame.new(0, 1.0 * F, 0), C.stone)
	cylinder(1.4 * F, 0.4 * F, o * CFrame.new(0, 1.95 * F, 0), C.stone)
	cylinder(1.22 * F, 0.06 * F, o * CFrame.new(0, 2.16 * F, 0), C.water, { CanCollide = false, Reflectance = 0.1 })
	cylinder(0.2 * F, 0.6 * F, o * CFrame.new(0, 2.4 * F, 0), C.stone)
	local yuzu = ball(0.9 * F, o * CFrame.new(0, 2.95 * F, 0), C.yuzu)
	cylinder(0.04 * F, 0.2 * F, o * CFrame.new(0, 3.45 * F, 0), C.woodDark, DECOR)
	blob(Vector3.new(0.36, 0.06, 0.18) * F, o * CFrame.new(0.17 * F, 3.48 * F, 0) * CFrame.Angles(0, 0, 0.4), C.leaf, DECOR)
	-- water falling from the upper bowl into the basin
	cylinder(1.5 * F, 1.5 * F, o * CFrame.new(0, 1.38 * F, 0), C.waterLight, { CanCollide = false, CanQuery = false, Transparency = 0.6, CastShadow = false })
	-- and a little spray from the top
	local spout = Instance.new("Attachment")
	spout.Position = Vector3.new(0, 0.5 * F, 0)
	spout.Parent = yuzu
	local spray = Instance.new("ParticleEmitter")
	spray.Color = ColorSequence.new(Color3.fromHex("#e9fbff"), C.water)
	spray.Size = NumberSequence.new(0.35, 0.12)
	spray.Transparency = NumberSequence.new(0.1, 1)
	spray.Lifetime = NumberRange.new(0.8, 1.1)
	spray.Speed = NumberRange.new(12, 16)
	spray.SpreadAngle = Vector2.new(22, 22)
	spray.Acceleration = Vector3.new(0, -30, 0)
	spray.Rate = 45
	spray.LightEmission = 0.3
	spray.Parent = spout
end

---------------------------------------------------------------- shops

-- A cosy house with its front door facing +Z of `at`. Sizes are in web units. Returns the
-- spot just outside the front door.
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
		local x = side * (w / 2 - 1.0 * S)
		local y = base + h * 0.55
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

-- A little round table with a hat on it, outside the Hat Shop.
local function hatStand(at: CFrame, hatId: string)
	cylinder(0.08 * S, 1.0 * S, at * CFrame.new(0, 0.5 * S, 0), C.tealDeep)
	cylinder(0.45 * S, 0.08 * S, at * CFrame.new(0, 1.04 * S, 0), C.cream)
	local hat = Builder.hatModel("capybara", hatId)
	if hat then
		hat:PivotTo(at * CFrame.new(0, 1.08 * S, 0) * CFrame.Angles(0, math.pi, 0))
		hat.Parent = folder
	end
end

-- A closed gate at the end of a road, for a place that's coming soon.
local function gate(at: CFrame, name: string, color: Color3)
	for _, side in { -1, 1 } do
		cylinder(0.24 * S, 4.2 * S, at * CFrame.new(side * 2.3 * S, 2.1 * S, 0), C.wood)
		ball(0.6 * S, at * CFrame.new(side * 2.3 * S, 4.35 * S, 0), color)
		bush(at * CFrame.new(side * 2.3 * S, 0, 0.5 * S), 0.7)
	end
	block(Vector3.new(5.4, 0.3, 0.4) * S, at * CFrame.new(0, 4.05 * S, 0), C.woodDark)
	local board = block(Vector3.new(3.6, 0.8, 0.12) * S, at * CFrame.new(0, 3.35 * S, 0.1 * S) * CFrame.Angles(0, math.pi, 0), C.cream)
	label(board, name, C.ink, C.cream)
	-- a ribbon across, and a little sign
	block(Vector3.new(4.4, 0.12, 0.06) * S, at * CFrame.new(0, 1.2 * S, 0), color)
	local soon = block(Vector3.new(1.8, 0.6, 0.08) * S, at * CFrame.new(0, 1.0 * S, 0.08 * S) * CFrame.Angles(0, math.pi, 0.05), color, DECOR)
	label(soon, "Opening soon!", C.cream)
end

-- The signpost: one board pointing down each road.
local function signpost(at: Vector3)
	local h = 4.3 * S
	cylinder(0.12 * S, h, CFrame.new(at + Vector3.new(0, h / 2, 0)), C.woodDark)
	ball(0.34 * S, CFrame.new(at + Vector3.new(0, h + 0.05 * S, 0)), C.coral, DECOR)
	bush(CFrame.new(at), 0.6)
	for i, road in Config.ROADS do
		local target = Config.polar(road.angle, 30)
		local dir = Vector3.new(target.X - at.X, 0, target.Z - at.Z).Unit
		local y = (3.85 - (i - 1) * 0.42) * S
		local centre = at + dir * 1.05 * S + Vector3.new(0, y, 0)
		local board = block(Vector3.new(2.0, 0.4, 0.08) * S, CFrame.fromMatrix(centre, dir, Vector3.yAxis), C.cream, DECOR)
		label(board, road.name, Color3.fromHex(road.color), C.cream, Enum.NormalId.Front)
		label(board, road.name, Color3.fromHex(road.color), C.cream, Enum.NormalId.Back)
	end
end

---------------------------------------------------------------- keeping space clear

-- Places scenery (trees, bushes, flowers, rocks) mustn't go: buildings, the plaza and paths.
local clear: { { at: Vector3, r: number } } = {}
local paths: { { a: Vector3, b: Vector3, w: number } } = {}

local function keepClear(at: Vector3, radius: number)
	table.insert(clear, { at = at, r = radius * S })
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Is `spot` at least `margin` web units from everything that needs space?
local function isClear(spot: Vector3, margin: number): boolean
	for _, c in clear do
		if flat(spot - c.at).Magnitude < c.r + margin * S then
			return false
		end
	end
	for _, p in paths do
		local along = p.b - p.a
		local t = math.clamp((spot - p.a):Dot(along) / along:Dot(along), 0, 1)
		if flat(spot - (p.a + along * t)).Magnitude < p.w / 2 + margin * S then
			return false
		end
	end
	return true
end

-- A flat strip of path on the grass from `a` to `b`, `width` web units wide.
local function footpath(a: Vector3, b: Vector3, width: number, top: number?)
	a, b = flat(a), flat(b)
	local length = (b - a).Magnitude
	local at = CFrame.lookAt((a + b) / 2, b) + Vector3.new(0, (top or 0.08) - 0.05, 0)
	block(Vector3.new(width * S, 0.1, length), at, C.path, { CanCollide = false })
	table.insert(paths, { a = a, b = b, w = width * S })
end

---------------------------------------------------------------- lawn things

local function flowerBed(at: CFrame, radius: number)
	cylinder(radius * S, 0.4 * S, at * CFrame.new(0, 0.2 * S, 0), C.stone)
	cylinder((radius - 0.15) * S, 0.06 * S, at * CFrame.new(0, 0.4 * S, 0), C.soil, DECOR)
	local n = math.round(radius * 7)
	for i = 1, n do
		local a = i * 2.4
		local r = math.sqrt(i / n) * (radius - 0.35)
		flower(at * CFrame.new(math.cos(a) * r * S, 0.4 * S, math.sin(a) * r * S), FLOWERS[(i % #FLOWERS) + 1], random:NextNumber(0.3, 0.5) * S)
	end
end

local function flowerPatch(at: Vector3)
	for i = 1, 6 do
		local a = random:NextNumber(0, math.pi * 2)
		local r = random:NextNumber(0, 1.3) * S
		flower(CFrame.new(at + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)), FLOWERS[(i % #FLOWERS) + 1], random:NextNumber(0.25, 0.45) * S)
	end
end

local function rock(at: Vector3, s: number)
	blob(Vector3.new(1.1, 0.6, 0.9) * s * S, CFrame.new(at + Vector3.new(0, 0.15 * s * S, 0)) * CFrame.Angles(0, random:NextNumber(0, 6), 0), C.stone)
end

-- A little pond with stones round the edge and lily pads.
local function pond(at: CFrame)
	cylinder(4.2 * S, 0.1, at * CFrame.new(0, 0.07, 0), C.water, { CanCollide = false, Reflectance = 0.05 })
	for i = 0, 17 do
		local s = random:NextNumber(0.7, 1.1)
		blob(Vector3.new(0.9, 0.45, 0.7) * s * S, at * CFrame.Angles(0, i / 18 * math.pi * 2, 0) * CFrame.new(0, 0.1 * S, 4.3 * S), C.stone, DECOR)
	end
	for i = 1, 6 do
		local a = random:NextNumber(0, math.pi * 2)
		local r = random:NextNumber(0.8, 3.2) * S
		local pad = at * CFrame.new(math.cos(a) * r, 0.14, math.sin(a) * r)
		cylinder(0.45 * S, 0.04, pad, C.leaf, DECOR)
		if i % 3 == 0 then
			ball(0.3 * S, pad * CFrame.new(0, 0.1 * S, 0), Color3.fromHex("#f6b8d0"), DECOR)
		end
	end
	for i = 0, 4 do
		local reedAt = at * CFrame.Angles(0, 2.2 + i * 0.25, 0) * CFrame.new(0, 0, 3.6 * S)
		cylinder(0.05 * S, 1.2 * S, reedAt * CFrame.new(0, 0.6 * S, 0), C.leafDark, DECOR)
		block(Vector3.new(0.12, 0.35, 0.12) * S, reedAt * CFrame.new(0, 1.2 * S, 0), C.woodDark, DECOR)
	end
	keepClear(at.Position, 5)
end

---------------------------------------------------------------- the square

local function plaza()
	-- the grass, then the paving in rings
	block(Vector3.new(1600, 4, 1600), CFrame.new(0, -2, 0), C.grass)
	local k = Config.PLAZA_R / 10
	local function ring(radius: number, top: number, color: Color3)
		cylinder(radius * k * S, 0.1, CFrame.new(0, top - 0.05, 0), color, { CanCollide = false })
	end
	ring(10.6, 0.1, C.stoneDark)
	ring(10, 0.14, C.plaza)
	ring(7.7, 0.17, C.creamDeep)
	ring(7.4, 0.2, C.plazaLight)
	ring(4.8, 0.23, C.creamDeep)
	ring(4.2, 0.26, C.plaza)
	-- spokes in the paving
	for i = 0, 19 do
		local inner, outer = 4.8 * k, 7.4 * k
		local mid = Config.polar(i * 18 + 9, (inner + outer) / 2)
		block(Vector3.new(0.25 * S, 0.1, (outer - inner) * S), yawAt(mid + Vector3.new(0, 0.17, 0), Config.faceIn(i * 18 + 9)), C.creamDeep, { CanCollide = false })
	end
	keepClear(Vector3.zero, Config.PLAZA_R + 2)

	-- lamps all round the edge, with bunting between them
	local lamps = {}
	for i = 0, 19 do
		local spot = Config.polar(i * 18 + 9, Config.PLAZA_R + 0.4)
		lamp(CFrame.new(spot))
		table.insert(lamps, spot + Vector3.new(0, (LAMP_H - 0.2) * S, 0))
	end
	for i = 1, #lamps do
		bunting(lamps[i], lamps[(i % #lamps) + 1])
	end

	-- benches in two rings, round flower beds, and planters in front of the shops
	for i = 0, 4 do
		local a = 36 + i * 72
		for _, side in { -1, 1 } do
			bench(yawAt(Config.polar(a + side * 18, 11), Config.faceIn(a + side * 18)))
			bench(yawAt(Config.polar(a + side * 12, Config.PLAZA_R - 1.6), Config.faceIn(a + side * 12)))
		end
		flowerBed(CFrame.new(Config.polar(a, 11)), 1.3)
		if a ~= 180 then
			planter(yawAt(Config.polar(a, Config.PLAZA_R + 2.2), Config.faceIn(a)), 3.2, 1.1)
		end
	end
end

-- The roads out of town, with street lamps, ending at gates.
local function roads()
	for _, road in Config.ROADS do
		footpath(Config.polar(road.angle, Config.PLAZA_R - 0.5), Config.polar(road.angle, Config.EDGE_R + 1), Config.ROAD_W, 0.1)
		gate(yawAt(Config.polar(road.angle, Config.EDGE_R - 0.5), Config.faceIn(road.angle)), road.name, Color3.fromHex(road.color))
	end
end

local function streetLamps()
	for _, road in Config.ROADS do
		for i, dist in { 26, 36, 46, 56, 64 } do
			local side = if i % 2 == 0 then 1 else -1
			local spot = Config.polar(road.angle, dist) + Config.polar(road.angle + 90 * side, Config.ROAD_W / 2 + 0.9)
			if isClear(spot, 0.4) then
				lamp(CFrame.new(spot))
				keepClear(spot, 1)
			end
		end
	end
end

local function shops(): { [string]: CFrame }
	local doors = {}
	for _, shop in Config.SHOPS do
		local at = yawAt(Config.polar(shop.angle, Config.SHOP_DIST), Config.faceIn(shop.angle))
		local door = house(at, {
			w = 6.5,
			d = 5,
			h = 3.4,
			wall = Color3.fromHex(shop.wall),
			roof = Color3.fromHex(shop.roof),
			door = Color3.fromHex(shop.door),
			awning = Color3.fromHex(shop.awning),
			label = shop.label,
			sign = Color3.fromHex(shop.sign),
		})
		doors[shop.id] = door
		footpath(Config.polar(shop.angle, Config.PLAZA_R), door.Position, 2.6)
		keepClear(at.Position, 7)
		if shop.id == "hats" then
			-- three hats on show beside the door, next to where Clover stands
			for i, hatId in { "flowers", "party", "sunhat" } do
				hatStand(at * CFrame.new(-(1.3 + i * 1.1) * S, 0, 4.6 * S), hatId)
			end
		elseif not shop.open then
			local sign = block(Vector3.new(1.6, 0.5, 0.06) * S, door * CFrame.new(0, 1.35 * S, -0.7 * S) * CFrame.Angles(0, math.pi, 0), C.cream, DECOR)
			label(sign, "Opening soon!", C.ink, C.cream)
		end
	end
	return doors
end

-- The library on the south lawn: a porch on columns, steps, and two giant books.
local function library()
	local L = Config.LIBRARY
	local at = yawAt(Config.polar(L.angle, L.dist), Config.faceIn(L.angle))
	local w, d = 9, 6
	local blue = Color3.fromHex("#4a5aa8")
	local door = house(at, { w = w, d = d, h = 4, wall = Color3.fromHex("#e6eef7"), roof = blue, door = C.coral, label = "Library", sign = blue, chimney = false, yard = false })
	local front = d / 2
	for _, side in { -1, 1 } do
		for _, x in { 1.3, w / 2 - 0.5 } do
			cylinder(0.22 * S, 3.4 * S, at * CFrame.new(side * x * S, 2.05 * S, (front + 1.0) * S), C.white)
		end
	end
	block(Vector3.new(w + 0.4, 0.3, 1.6) * S, at * CFrame.new(0, 3.9 * S, (front + 0.75) * S), blue)
	block(Vector3.new(w - 0.4, 0.18, 1.4) * S, at * CFrame.new(0, 0.09 * S, (front + 0.9) * S), C.stone, DECOR)
	for _, book in { { -1.9, C.coral, 0.3, 0.1 }, { 1.95, C.teal, -0.25, -0.12 } } do
		local bookAt = at * CFrame.new(book[1] * S, 0.8 * S, (front + 1.9) * S) * CFrame.Angles(0, book[3], book[4])
		block(Vector3.new(0.7, 0.9, 0.22) * S, bookAt, book[2])
		block(Vector3.new(0.62, 0.84, 0.24) * S, bookAt, C.cream, DECOR)
	end
	local sign = block(Vector3.new(1.6, 0.5, 0.06) * S, door * CFrame.new(1.8 * S, 1.2 * S, -0.4 * S) * CFrame.Angles(0, math.pi, 0), C.cream, DECOR)
	label(sign, "Opening soon!", C.ink, C.cream)
	footpath(Config.polar(L.angle, Config.PLAZA_R), door.Position, 2.6)
	keepClear(at.Position, 8)
end

-- A cottage beside a road, with a path to its door.
local function cottage(c)
	local at, roadPoint = Config.cottageAt(c)
	local door = house(at, {
		w = 4.6,
		d = 4.4,
		h = 2.9,
		wall = Color3.fromHex(c.wall),
		roof = Color3.fromHex(c.roof),
		door = Color3.fromHex(c.door),
		label = c.label,
		sign = if c.sign then Color3.fromHex(c.sign) else nil,
	})
	footpath(roadPoint, door.Position, 2.2)
	keepClear(at.Position, 6)
	if c.pond then
		pond(at * CFrame.new(-9.5 * S, 0, -1.5 * S))
	end
end

-- A round gazebo with a stepped roof, fairy lights and benches inside.
local function gazebo()
	local G = Config.GAZEBO
	local centre = Config.polar(G.angle, G.dist)
	local roadPoint = Config.polar(72, G.dist * math.cos(math.rad(G.angle - 72)))
	local at = CFrame.lookAt(centre, roadPoint) * CFrame.Angles(0, math.pi, 0) -- the way in faces the road
	local floor = 0.45 * S
	cylinder(4.6 * S, 0.2 * S, at * CFrame.new(0, 0.1 * S, 0), C.stone)
	cylinder(4.2 * S, 0.25 * S, at * CFrame.new(0, 0.325 * S, 0), C.cream)
	local postR = 3.7 * S
	for i = 0, 7 do
		local a = math.rad(22.5 + i * 45)
		cylinder(0.14 * S, 3.0 * S, at * CFrame.Angles(0, a, 0) * CFrame.new(0, floor + 1.5 * S, postR), C.white)
		if i ~= 7 then -- leave the way in open
			local mid = a + math.rad(22.5)
			local length = 2 * postR * math.sin(math.rad(22.5))
			for _, y in { 0.45, 0.9 } do
				block(Vector3.new(length, 0.1 * S, 0.1 * S), at * CFrame.Angles(0, mid, 0) * CFrame.new(0, floor + y * S, postR * math.cos(math.rad(22.5))), C.white, DECOR)
			end
		end
	end
	local tiers = { { 4.6, 0.3, 3.6, C.coral }, { 3.6, 0.45, 3.95, C.cream }, { 2.5, 0.45, 4.35, C.coral }, { 1.3, 0.45, 4.75, C.cream } }
	for _, t in tiers do
		cylinder(t[1] * S, t[2] * S, at * CFrame.new(0, t[3] * S, 0), t[4])
	end
	ball(0.7 * S, at * CFrame.new(0, 5.15 * S, 0), C.yellow)
	for i = 0, 15 do
		ball(0.18 * S, at * CFrame.Angles(0, i / 16 * math.pi * 2, 0) * CFrame.new(0, 3.38 * S, 4.5 * S), C.yellowLight, DECOR)
	end
	for _, a in { math.pi / 2, -math.pi / 2 } do
		bench(at * CFrame.Angles(0, a, 0) * CFrame.new(0, floor, 2.3 * S) * CFrame.Angles(0, math.pi, 0))
	end
	for i = 0, 3 do
		flowerBed(at * CFrame.Angles(0, math.rad(45 + i * 90), 0) * CFrame.new(0, 0, 6.3 * S), 1.1)
	end
	footpath(roadPoint, (at * CFrame.new(0, 0, 4.5 * S)).Position, 2.4)
	keepClear(centre, 8)
end

local function lawns()
	-- the big yuzu tree, a picnic and a notice board on the south lawn
	local yuzuTree = Config.polar(158, 33)
	tree(CFrame.new(yuzuTree), 1.8, true)
	keepClear(yuzuTree, 5)
	local picnic = yawAt(Config.polar(196, 26), 0.3)
	for i = 0, 3 do
		for j = 0, 3 do
			local color = if (i + j) % 2 == 1 then C.coral else C.cream
			block(Vector3.new(0.6, 0.04, 0.6) * S, picnic * CFrame.new((-0.9 + i * 0.6) * S, 0.06 * S, (-0.9 + j * 0.6) * S), color, DECOR)
		end
	end
	block(Vector3.new(0.7, 0.45, 0.5) * S, picnic * CFrame.new(0.4 * S, 0.3 * S, 0.2 * S), C.wood)
	ball(0.32 * S, picnic * CFrame.new(-0.5 * S, 0.2 * S, -0.3 * S), C.yuzu, DECOR)
	ball(0.32 * S, picnic * CFrame.new(-0.25 * S, 0.2 * S, -0.5 * S), C.yuzu, DECOR)
	keepClear(picnic.Position, 2.5)

	local board = yawAt(Config.polar(198, 20.5), Config.faceIn(195))
	for _, side in { -1, 1 } do
		cylinder(0.1 * S, 2.2 * S, board * CFrame.new(side * 1.1 * S, 1.1 * S, 0), C.woodDark)
	end
	block(Vector3.new(2.6, 1.5, 0.15) * S, board * CFrame.new(0, 1.5 * S, 0), C.wood)
	block(Vector3.new(2.8, 0.2, 0.4) * S, board * CFrame.new(0, 2.35 * S, 0), C.coral)
	for i = 0, 3 do
		local paper = { C.cream, C.white, C.yellow, C.skyBlue }
		block(Vector3.new(0.5, 0.6, 0.02) * S, board * CFrame.new((-0.85 + i * 0.57) * S, (1.5 + (i % 2) * 0.1) * S, 0.09 * S) * CFrame.Angles(0, 0, random:NextNumber(-0.1, 0.1)), paper[i + 1], DECOR)
	end
	keepClear(board.Position, 2.5)

	local post = Config.polar(126, 20.5)
	signpost(post)
	keepClear(post, 2)

	-- trees, bushes, flowers and rocks wherever there's room
	local function scatter(count: number, margin: number, place: (Vector3) -> ())
		local placed, tries = 0, 0
		while placed < count and tries < count * 12 do
			tries += 1
			local spot = Config.polar(random:NextNumber(0, 360), random:NextNumber(Config.PLAZA_R + 4, Config.EDGE_R - 3))
			if isClear(spot, margin) then
				place(spot)
				keepClear(spot, margin * 0.6)
				placed += 1
			end
		end
	end
	scatter(60, 2.6, function(spot)
		tree(CFrame.new(spot), random:NextNumber(0.9, 1.4), random:NextNumber() < 0.2)
	end)
	scatter(30, 1.4, function(spot)
		bush(yawAt(spot, random:NextNumber(0, 6)), random:NextNumber(0.8, 1.3))
	end)
	scatter(26, 1.2, flowerPatch)
	scatter(12, 1, function(spot)
		rock(spot, random:NextNumber(0.7, 1.5))
	end)
end

-- The hedge round the edge of town, with woods and hills beyond, and an invisible wall so
-- nobody wanders off.
local function edge()
	local r = Config.EDGE_R
	local around = math.floor(2 * math.pi * r / 3)
	for i = 0, around - 1 do
		local angle = i / around * 360
		local spot = Config.polar(angle, r + 0.8 + random:NextNumber(-0.3, 0.3))
		bush(yawAt(spot, random:NextNumber(0, 6)), random:NextNumber(1.2, 1.7), if i % 2 == 0 then C.leaf else C.leafDark)
	end
	local walls = 64
	for i = 0, walls - 1 do
		local angle = (i + 0.5) / walls * 360
		local width = 2 * math.pi * r * S / walls * 1.1
		block(Vector3.new(width, 60, 2), yawAt(Config.polar(angle, r + 0.3) + Vector3.new(0, 30, 0), Config.faceIn(angle)), C.leaf, {
			Transparency = 1,
			CanQuery = false,
			Name = "Edge",
		})
	end
	for _ = 1, 110 do
		local spot = Config.polar(random:NextNumber(0, 360), random:NextNumber(r + 3, r + 38))
		tree(CFrame.new(spot), random:NextNumber(1.1, 2.0), random:NextNumber() < 0.15)
	end
	for _ = 1, 18 do
		local spot = Config.polar(random:NextNumber(0, 360), random:NextNumber(r + 45, r + 100))
		local size = random:NextNumber(80, 180)
		blob(Vector3.new(size, size * 0.45, size), CFrame.new(spot), if random:NextNumber() < 0.5 then C.grassDark else C.leafLight, DECOR)
	end
end

local function sky()
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.22
	atmosphere.Offset = 0.1
	atmosphere.Color = Color3.fromHex("#cbeee3")
	atmosphere.Decay = Color3.fromHex("#9ccfc0")
	atmosphere.Glare = 0
	atmosphere.Haze = 0.8
	atmosphere.Parent = Lighting

	local clouds = Instance.new("Clouds")
	clouds.Cover = 0.55
	clouds.Density = 0.5
	clouds.Color = Color3.new(1, 1, 1)
	clouds.Parent = Workspace.Terrain

	local tint = Instance.new("ColorCorrectionEffect")
	tint.Saturation = 0.08
	tint.Contrast = 0.04
	tint.TintColor = Color3.fromHex("#fff8ee")
	tint.Parent = Lighting
end

---------------------------------------------------------------- building it all

-- Builds the town. Returns where the shop doors are, so the shopkeepers can stand by them.
function Town.build(): { doors: { [string]: CFrame } }
	-- The Baseplate template's floor and spawn pad aren't needed: the town has its own.
	for _, name in { "Baseplate", "SpawnLocation" } do
		local old = Workspace:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end

	folder = Instance.new("Folder")
	folder.Name = "Town"
	plaza()
	fountain()
	roads()
	local doors = shops()
	library()
	for _, c in Config.COTTAGES do
		cottage(c)
	end
	gazebo()
	streetLamps()
	lawns()
	edge()
	sky()
	folder.Parent = Workspace
	return { doors = doors }
end

return Town
