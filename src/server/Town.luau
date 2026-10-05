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

local function lamp(at: CFrame)
	cylinder(0.34 * S, 0.25 * S, at * CFrame.new(0, 0.125 * S, 0), C.tealDeep)
	cylinder(0.09 * S, 2.3 * S, at * CFrame.new(0, 1.25 * S, 0), C.tealDeep)
	cylinder(0.18 * S, 0.12 * S, at * CFrame.new(0, 2.4 * S, 0), C.tealDeep)
	local glow = blob(Vector3.new(0.5, 0.56, 0.5) * S, at * CFrame.new(0, 2.75 * S, 0), C.cream)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromHex("#ffe9b8")
	light.Range = 16
	light.Brightness = 0.7
	light.Parent = glow
	blob(Vector3.new(0.8, 0.3, 0.8) * S, at * CFrame.new(0, 3.12 * S, 0), C.tealDeep)
	ball(0.14 * S, at * CFrame.new(0, 3.3 * S, 0), C.tealDeep, DECOR)
end

-- A string of little flags sagging between two points.
local function bunting(a: Vector3, b: Vector3)
	local n = 12
	local sag = 0.7 * S
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
	-- the basin: a stone floor and a low round wall
	cylinder(3.2 * S, 0.3 * S, o * CFrame.new(0, 0.15 * S, 0), C.stone)
	local n = 32
	local wallR = 3.05 * S
	for i = 0, n - 1 do
		local a = (i / n) * math.pi * 2
		local at = CFrame.Angles(0, a, 0) * CFrame.new(0, 0, wallR)
		local width = 2 * math.pi * wallR / n * 1.15
		block(Vector3.new(width, 0.75 * S, 0.5 * S), at * CFrame.new(0, 0.42 * S, 0), C.stone)
		block(Vector3.new(width * 1.05, 0.12 * S, 0.62 * S), at * CFrame.new(0, 0.82 * S, 0), C.stoneDark)
	end
	-- the water
	cylinder(2.86 * S, 0.1 * S, o * CFrame.new(0, 0.58 * S, 0), C.water, { CanCollide = false, Transparency = 0.1, Reflectance = 0.1 })
	-- the middle: a column, the upper bowl and a giant stone yuzu on top
	cylinder(0.42 * S, 1.5 * S, o * CFrame.new(0, 1.0 * S, 0), C.stone)
	cylinder(1.4 * S, 0.4 * S, o * CFrame.new(0, 1.95 * S, 0), C.stone)
	cylinder(1.22 * S, 0.06 * S, o * CFrame.new(0, 2.16 * S, 0), C.water, { CanCollide = false, Reflectance = 0.1 })
	cylinder(0.2 * S, 0.6 * S, o * CFrame.new(0, 2.4 * S, 0), C.stone)
	local yuzu = ball(0.9 * S, o * CFrame.new(0, 2.95 * S, 0), C.yuzu)
	cylinder(0.04 * S, 0.2 * S, o * CFrame.new(0, 3.45 * S, 0), C.woodDark, DECOR)
	blob(Vector3.new(0.36, 0.06, 0.18) * S, o * CFrame.new(0.17 * S, 3.48 * S, 0) * CFrame.Angles(0, 0, 0.4), C.leaf, DECOR)
	-- water falling from the upper bowl into the basin
	cylinder(1.5 * S, 1.5 * S, o * CFrame.new(0, 1.38 * S, 0), C.waterLight, { CanCollide = false, CanQuery = false, Transparency = 0.6, CastShadow = false })
	-- and a little spray from the top
	local spout = Instance.new("Attachment")
	spout.Position = Vector3.new(0, 0.5 * S, 0)
	spout.Parent = yuzu
	local spray = Instance.new("ParticleEmitter")
	spray.Color = ColorSequence.new(Color3.fromHex("#e9fbff"), C.water)
	spray.Size = NumberSequence.new(0.35, 0.12)
	spray.Transparency = NumberSequence.new(0.1, 1)
	spray.Lifetime = NumberRange.new(0.8, 1.1)
	spray.Speed = NumberRange.new(9, 12)
	spray.SpreadAngle = Vector2.new(22, 22)
	spray.Acceleration = Vector3.new(0, -30, 0)
	spray.Rate = 45
	spray.LightEmission = 0.3
	spray.Parent = spout
end

---------------------------------------------------------------- shops

-- A cosy house with its front door facing +Z of `at`. Sizes are in web units. Returns the
-- spot just outside the front door.
local function house(at: CFrame, o: { w: number, d: number, h: number, wall: Color3, roof: Color3, door: Color3, awning: Color3?, label: string?, sign: Color3? }): CFrame
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
	block(Vector3.new(0.6, 1.3, 0.6) * S, at * CFrame.new(w * 0.25, top + 1.2 * S, -d * 0.15), C.stoneDark)
	block(Vector3.new(0.75, 0.18, 0.75) * S, at * CFrame.new(w * 0.25, top + 1.9 * S, -d * 0.15), C.stone)

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
	for _, side in { -1, 1 } do
		fence(at * CFrame.new(side * (w / 2 + 1.4 * S), 0, 0.6 * S) * CFrame.Angles(0, math.pi / 2, 0), 4.4)
		bush(at * CFrame.new(side * (w / 2 - 0.4 * S), 0, front + 0.6 * S), 0.8)
	end
	mailbox(at * CFrame.new(w / 2 + 0.6 * S, 0, front + 1.3 * S), o.roof)
	barrel(at * CFrame.new(-w / 2 - 0.4 * S, 0, front + 1.1 * S))

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

---------------------------------------------------------------- the square

local function plaza()
	-- the grass, then the paving in rings
	block(Vector3.new(1200, 4, 1200), CFrame.new(0, -2, 0), C.grass)
	local function ring(radius: number, top: number, color: Color3)
		cylinder(radius * S, 0.1, CFrame.new(0, top - 0.05, 0), color, { CanCollide = false })
	end
	ring(Config.PLAZA_R + 0.6, 0.1, C.stoneDark)
	ring(Config.PLAZA_R, 0.14, C.plaza)
	ring(7.7, 0.17, C.creamDeep)
	ring(7.4, 0.2, C.plazaLight)
	ring(4.8, 0.23, C.creamDeep)
	ring(4.2, 0.26, C.plaza)

	-- the roads out of town, each with lamps and bunting where it leaves the plaza
	for _, road in Config.ROADS do
		local from, to = Config.PLAZA_R - 0.5, Config.EDGE_R + 1
		local middle = Config.polar(road.angle, (from + to) / 2)
		block(Vector3.new(3.6 * S, 0.1, (to - from) * S), yawAt(middle + Vector3.new(0, 0.05, 0), Config.faceIn(road.angle)), C.path, { CanCollide = false })
		local ends = {}
		for _, side in { -1, 1 } do
			local spot = Config.polar(road.angle + side * 13, Config.PLAZA_R + 0.4)
			lamp(CFrame.new(spot))
			table.insert(ends, spot + Vector3.new(0, 2.55 * S, 0))
		end
		bunting(ends[1], ends[2])
		gate(yawAt(Config.polar(road.angle, Config.EDGE_R - 0.5), Config.faceIn(road.angle)), road.name, Color3.fromHex(road.color))
	end

	-- benches round the plaza, and flower planters in front of the shops
	for i = 0, 4 do
		local a = 36 + i * 72
		for _, side in { -1, 1 } do
			bench(yawAt(Config.polar(a + side * 16, Config.PLAZA_R - 1.4), Config.faceIn(a + side * 16)))
		end
		if a ~= 180 then
			planter(yawAt(Config.polar(a, Config.PLAZA_R + 2.2), Config.faceIn(a)), 3.2, 1.1)
		end
	end
end

local function shops(): { [string]: CFrame }
	local doors = {}
	for _, shop in Config.SHOPS do
		local at = yawAt(Config.polar(shop.angle, Config.SHOP_DIST), Config.faceIn(shop.angle))
		doors[shop.id] = house(at, {
			w = 6,
			d = 4.6,
			h = 3.1,
			wall = Color3.fromHex(shop.wall),
			roof = Color3.fromHex(shop.roof),
			door = Color3.fromHex(shop.door),
			awning = Color3.fromHex(shop.awning),
			label = shop.label,
			sign = Color3.fromHex(shop.sign),
		})
		if shop.id == "hats" then
			-- three hats on show beside the door, next to where Clover stands
			for i, hatId in { "flowers", "party", "sunhat" } do
				hatStand(at * CFrame.new(-(1.1 + i * 1.1) * S, 0, 4.6 * S), hatId)
			end
		elseif not shop.open then
			local sign = block(Vector3.new(1.6, 0.5, 0.06) * S, doors[shop.id] * CFrame.new(0, 1.35 * S, -0.7 * S) * CFrame.Angles(0, math.pi, 0), C.cream, DECOR)
			label(sign, "Opening soon!", C.ink, C.cream)
		end
	end
	return doors
end

local function lawns()
	-- the big yuzu tree, a picnic and a notice board on the south lawn
	tree(CFrame.new(Config.polar(158, 22)), 1.6, true)
	local picnic = yawAt(Config.polar(180, 16.5) + Vector3.new(2.5 * S, 0, 0), 0.3)
	for i = 0, 3 do
		for j = 0, 3 do
			local color = if (i + j) % 2 == 1 then C.coral else C.cream
			block(Vector3.new(0.6, 0.04, 0.6) * S, picnic * CFrame.new((-0.9 + i * 0.6) * S, 0.06 * S, (-0.9 + j * 0.6) * S), color, DECOR)
		end
	end
	block(Vector3.new(0.7, 0.45, 0.5) * S, picnic * CFrame.new(0.4 * S, 0.3 * S, 0.2 * S), C.wood)
	ball(0.32 * S, picnic * CFrame.new(-0.5 * S, 0.2 * S, -0.3 * S), C.yuzu, DECOR)
	ball(0.32 * S, picnic * CFrame.new(-0.25 * S, 0.2 * S, -0.5 * S), C.yuzu, DECOR)

	local board = yawAt(Config.polar(200, 14.5), Config.faceIn(195))
	for _, side in { -1, 1 } do
		cylinder(0.1 * S, 2.2 * S, board * CFrame.new(side * 1.1 * S, 1.1 * S, 0), C.woodDark)
	end
	block(Vector3.new(2.6, 1.5, 0.15) * S, board * CFrame.new(0, 1.5 * S, 0), C.wood)
	block(Vector3.new(2.8, 0.2, 0.4) * S, board * CFrame.new(0, 2.35 * S, 0), C.coral)
	for i = 0, 3 do
		local paper = { C.cream, C.white, C.yellow, C.skyBlue }
		block(Vector3.new(0.5, 0.6, 0.02) * S, board * CFrame.new((-0.85 + i * 0.57) * S, (1.5 + (i % 2) * 0.1) * S, 0.09 * S) * CFrame.Angles(0, 0, random:NextNumber(-0.1, 0.1)), paper[i + 1], DECOR)
	end

	signpost(Config.polar(122, 12.6))

	-- trees on the lawns between the shops and the roads
	local function nearAny(angle: number, list: { number }, gap: number): boolean
		for _, a in list do
			local diff = math.abs((angle - a + 180) % 360 - 180)
			if diff < gap then
				return true
			end
		end
		return false
	end
	local roadAngles, shopAngles = {}, {}
	for _, road in Config.ROADS do
		table.insert(roadAngles, road.angle)
	end
	for _, shop in Config.SHOPS do
		table.insert(shopAngles, shop.angle)
	end
	for _ = 1, 14 do
		local angle = random:NextNumber(0, 360)
		if not nearAny(angle, roadAngles, 9) and not nearAny(angle, shopAngles, 16) and not nearAny(angle, { 158 }, 12) then
			tree(CFrame.new(Config.polar(angle, random:NextNumber(25, 31))), random:NextNumber(0.9, 1.3))
		end
	end
end

-- The hedge round the edge of town, with woods and hills beyond, and an invisible wall so
-- nobody wanders off.
local function edge()
	local r = Config.EDGE_R
	local around = math.floor(2 * math.pi * r / 2.2)
	for i = 0, around - 1 do
		local angle = i / around * 360
		local spot = Config.polar(angle, r + 0.8 + random:NextNumber(-0.3, 0.3))
		bush(yawAt(spot, random:NextNumber(0, 6)), random:NextNumber(1.0, 1.4), if i % 2 == 0 then C.leaf else C.leafDark)
	end
	local walls = 40
	for i = 0, walls - 1 do
		local angle = (i + 0.5) / walls * 360
		local width = 2 * math.pi * r * S / walls * 1.1
		block(Vector3.new(width, 60, 2), yawAt(Config.polar(angle, r + 0.3) + Vector3.new(0, 30, 0), Config.faceIn(angle)), C.leaf, {
			Transparency = 1,
			CanQuery = false,
			Name = "Edge",
		})
	end
	for _ = 1, 70 do
		local spot = Config.polar(random:NextNumber(0, 360), random:NextNumber(r + 3, r + 30))
		tree(CFrame.new(spot), random:NextNumber(1.0, 1.8), random:NextNumber() < 0.2)
	end
	for _ = 1, 16 do
		local spot = Config.polar(random:NextNumber(0, 360), random:NextNumber(r + 40, r + 80))
		local size = random:NextNumber(60, 140)
		blob(Vector3.new(size, size * 0.45, size), CFrame.new(spot), if random:NextNumber() < 0.5 then C.grassDark else C.leafLight, DECOR)
	end
end

local function sky()
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.3
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
	local doors = shops()
	lawns()
	edge()
	sky()
	folder.Parent = Workspace
	return { doors = doors }
end

return Town
