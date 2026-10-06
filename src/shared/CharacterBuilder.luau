-- Builds a Sunnyfolk animal from the imported models: the body, its colours, clothes, the
-- things it holds and its hat, joined up with Motor6Ds so it can walk (see Animator).
--
-- How the models fit together is explained in docs/characters.md. In short: every mesh was
-- exported standing at the origin, so MeshLayout says exactly where each one goes. Each body
-- part (Torso, Head, arms, legs, eyes) is its "<Part>_detail" mesh, renamed to the part's
-- name, with that part's other meshes welded to it.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Config = require(script.Parent.Config)
local Looks = require(script.Parent.Looks)
local MeshLayout = require(script.Parent.MeshLayout)
local Models = require(script.Parent.Models)

local Builder = {}

Builder.TAG = "SunnyfolkAnimal" -- every walking animal has this tag, so Animator can find it
Builder.COLLISION_GROUP = "Animals" -- every animal's collision group (see server/Main)

Builder.PARTS = { "Torso", "Head", "RightArm", "LeftArm", "RightLeg", "LeftLeg", "RightEye", "LeftEye" }
local JOINED_TO = {
	Torso = "HumanoidRootPart",
	Head = "Torso",
	RightArm = "Torso",
	LeftArm = "Torso",
	RightLeg = "HumanoidRootPart",
	LeftLeg = "HumanoidRootPart",
	RightEye = "Head",
	LeftEye = "Head",
}

-- The invisible box the animal walks around in. Its bottom floats HIP_HEIGHT above the ground.
Builder.ROOT_SIZE = Vector3.new(2.4, 2.4, 2.4)
Builder.ROOT_HEIGHT = 2.6
Builder.HIP_HEIGHT = Builder.ROOT_HEIGHT - Builder.ROOT_SIZE.Y / 2

export type Look = {
	species: string, -- "capybara", "bunny", ...
	body: string?, -- which body model, if not the species' own ("guineapig-grumpy")
	coat: string?, -- a coat id from sunnyfolk.json
	colors: { [string]: string }?, -- colours by role ("fur" = "#c48550"), on top of the coat
	scarf: string?, -- the scarf's colour
	clothes: { string }?,
	held: { string }?,
	hat: string?,
}

export type Options = {
	cframe: CFrame?, -- where the feet go (facing -Z of this CFrame)
	viewport: boolean?, -- for a picture in a ViewportFrame: everything anchored, no Humanoid
	name: string?,
}

---------------------------------------------------------------- helpers

-- An optional list, or an empty one.
local function list<T>(items: { T }?): { T }
	return items or {}
end

local function centreOf(m): Vector3
	return Vector3.new(m[1], m[2], m[3])
end

local function settle(part: BasePart, anchored: boolean)
	part.Anchored = anchored
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
end

local scaleWarned: { [string]: boolean } = {}
local counted: { [string]: boolean } = {} -- animals already counted in Studio's Output

-- A copy of one imported mesh, the right size, at its rest place relative to `at`.
local function copyMesh(fileKey: string, file: Models.File, name: string, at: CFrame, anchored: boolean): MeshPart
	local template = file.meshes[name]
	local mesh = template:Clone()
	for _, child in mesh:GetChildren() do
		if child:IsA("JointInstance") or child:IsA("WeldConstraint") then
			child:Destroy()
		end
	end
	if math.abs(file.scale - 1) > 0.05 and not scaleWarned[fileKey] then
		scaleWarned[fileKey] = true
		warn(`Sunnyfolk: the "{fileKey}" model was imported at a different size. The game puts it right,`
			.. " but next time set the importer's scale unit to Stud.")
	end
	mesh.Size = template.Size * file.scale
	-- `unturn` undoes any turn Studio gave the whole model on import
	mesh.CFrame = at * CFrame.new(centreOf(MeshLayout[fileKey].meshes[name])) * file.unturn * template.CFrame.Rotation
	mesh.Name = name
	settle(mesh, anchored)
	-- If the palette texture came in as a SurfaceAppearance, also give it to TextureID, so
	-- pictures in a ViewportFrame show the eyes and cheeks too.
	if mesh.TextureID == "" then
		local look = mesh:FindFirstChildOfClass("SurfaceAppearance")
		if look then
			pcall(function()
				mesh.TextureID = (look :: any).ColorMap
			end)
		end
	end
	return mesh
end

-- Colours a mesh by its kind: "<Part>_fur" takes the fur colour and so on. "detail" meshes
-- keep their palette texture, and "glass" ones are see-through.
local function paint(mesh: MeshPart, kind: string, colors: { [string]: Color3 })
	if kind == "detail" then
		return
	elseif kind == "glass" then
		mesh.Transparency = 0.65
		return
	end
	local color = colors[kind]
	if color then
		for _, child in mesh:GetChildren() do
			if child:IsA("SurfaceAppearance") then
				child:Destroy()
			end
		end
		mesh.Color = color
		mesh.Material = Enum.Material.SmoothPlastic
	end
end

-- Every colour role for this look: the animal's own colours, then its coat, then any extras.
local function colorsFor(look: Look): { [string]: Color3 }
	local colors = {}
	local animal = Looks.animal(look.species)
	if animal then
		for role, hex in animal.roles do
			colors[role] = Looks.color(hex)
		end
		if look.coat then
			for role, hex in Looks.coat(look.species, look.coat).colors do
				colors[role] = Looks.color(hex)
			end
		end
	end
	for role, hex in pairs(look.colors or {}) do
		colors[role] = Looks.color(hex)
	end
	colors.scarf = Looks.color(look.scarf or Looks.scarves()[1])
	return colors
end

-- Welds `part` onto one of the model's body parts, keeping the two where they were exported
-- relative to each other. `part` must be at its rest place, relative to the model's feet.
local function attach(model: Model, partName: string, part: BasePart): boolean
	local main = model:FindFirstChild(partName)
	if not (main and main:IsA("BasePart")) then
		return false
	end
	local offset = (main:GetAttribute("Rest") :: CFrame):Inverse() * part.CFrame
	part.CFrame = main.CFrame * offset
	local weld = Instance.new("Weld")
	weld.Part0 = main
	weld.Part1 = part
	weld.C0 = offset
	weld.Parent = part
	return true
end

local function isAnchored(model: Model): boolean
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root ~= nil and root.Anchored
end

-- A round stand-in body, used until the real models have been imported into Studio.
local function standIn(model: Model, at: CFrame, colors: { [string]: Color3 }, anchored: boolean)
	local fur = colors.fur or Color3.fromHex("#c98b52")
	local shapes = {
		Torso = { Vector3.new(0, 2.3, 0), Vector3.new(3, 3.2, 2.8), fur },
		Head = { Vector3.new(0, 4.3, -0.3), Vector3.new(2.6, 2.4, 2.4), fur },
		RightEye = { Vector3.new(0.55, 4.5, -1.45), Vector3.new(0.35, 0.45, 0.2), Color3.fromHex("#2b2622") },
		LeftEye = { Vector3.new(-0.55, 4.5, -1.45), Vector3.new(0.35, 0.45, 0.2), Color3.fromHex("#2b2622") },
	}
	for name, shape in shapes do
		local part = Instance.new("Part")
		part.Name = name
		part.Shape = Enum.PartType.Ball
		part.Size = shape[2]
		part.Color = shape[3]
		part.Material = Enum.Material.SmoothPlastic
		part.CFrame = at * CFrame.new(shape[1])
		part:SetAttribute("Rest", CFrame.new(shape[1]))
		settle(part, anchored)
		part.Parent = model
	end
end

---------------------------------------------------------------- building

-- Clothes and held things all live in the "<species>-clothes" model.
local function addWear(model: Model, look: Look, colors: { [string]: Color3 }, anchored: boolean)
	local wanted = {}
	for _, id in list(look.clothes) do
		wanted[id] = true
	end
	for _, id in list(look.held) do
		wanted[id] = true
	end
	if next(wanted) == nil then
		return
	end

	local fileKey = look.species .. "-clothes"
	local file = Models.get(fileKey)
	if file then
		local folder = Instance.new("Folder")
		folder.Name = "Wear"
		folder.Parent = model
		for name in file.meshes do
			-- "<id>_<Part>_<kind>", like "raincoat-blue_LeftArm_detail"
			local id, partName, kind = string.match(name, "^(.-)_(%w+)_(%w+)$")
			if id and partName and kind and wanted[id] then
				local mesh = copyMesh(fileKey, file, name, CFrame.identity, anchored)
				paint(mesh, kind, colors)
				-- Scarves and bandanas sit inside the body's own shadow, so theirs adds nothing.
				-- Bigger things (coats, backpacks, things held out in front) keep theirs.
				local item = Looks.clothes(id)
				if item and item.slot == "neck" then
					mesh.CastShadow = false
				end
				if attach(model, partName, mesh) then
					mesh.Parent = folder
				end
			end
		end
	end

	-- Raincoats and the space suit cover the tummy patch.
	for _, id in list(look.clothes) do
		local item = Looks.clothes(id)
		local torso = model:FindFirstChild("Torso")
		local belly = torso and torso:FindFirstChild("Torso_belly")
		if item and item.covers and belly and belly:IsA("BasePart") then
			belly.Transparency = 1
		end
	end

	-- An arm holding something stays up in front (Animator reads this).
	for _, id in list(look.held) do
		local item = Looks.held(id)
		if item and item.armPose then
			model:SetAttribute(item.arm .. "Pose", Vector2.new(item.armPose.x, item.armPose.z))
		end
	end
end

-- Builds an animal. It isn't parented anywhere: put it where you want it.
function Builder.build(look: Look, options: Options?): Model
	local opts: Options = options or {}
	local at = opts.cframe or CFrame.identity
	local viewport = opts.viewport == true
	local species = look.species
	local bodyKey = look.body or species
	local colors = colorsFor(look)

	local model = Instance.new("Model")
	model.Name = opts.name or species
	model:SetAttribute("Species", species)

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Builder.ROOT_SIZE
	root.Transparency = 1
	root.CFrame = at * CFrame.new(0, Builder.ROOT_HEIGHT, 0)
	root.Anchored = viewport
	root.CanCollide = not viewport
	root.CanTouch = false
	root:SetAttribute("Rest", CFrame.new(0, Builder.ROOT_HEIGHT, 0))
	root.Parent = model
	model.PrimaryPart = root

	-- the body: one main mesh per part, with that part's other meshes welded on
	local body = Models.get(bodyKey)
	if body then
		for _, partName in Builder.PARTS do
			local mainName = partName .. "_detail"
			if body.meshes[mainName] then
				local main = copyMesh(bodyKey, body, mainName, at, viewport)
				main.Name = partName
				-- Only the coloured "fur" meshes cast the animal's shadow. The detail meshes (eyes,
				-- cheeks and the outline) are the same shape, a touch bigger, so theirs adds nothing.
				main.CastShadow = false
				main:SetAttribute("Rest", at:Inverse() * main.CFrame)
				main.Parent = model
			end
		end
		for name in body.meshes do
			local partName, kind = string.match(name, "^(%w+)_(%w+)$")
			if partName and kind and kind ~= "detail" then
				local mesh = copyMesh(bodyKey, body, name, CFrame.identity, viewport)
				paint(mesh, kind, colors)
				if attach(model, partName, mesh) then
					mesh.Parent = model:FindFirstChild(partName)
				end
			end
		end
	else
		standIn(model, at, colors, viewport)
	end

	-- joints, at the pivots from sunnyfolk.json
	local animal = Looks.animal(species)
	for _, partName in Builder.PARTS do
		local part = model:FindFirstChild(partName) :: BasePart?
		local parent = model:FindFirstChild(JOINED_TO[partName]) :: BasePart?
		local pivot = animal and animal.pivots[partName]
		if part and parent and pivot then
			local pivotCFrame = at * CFrame.new(pivot[1], pivot[2], pivot[3])
			local joint = Instance.new("Motor6D")
			joint.Name = "Joint"
			joint.Part0 = parent
			joint.Part1 = part
			joint.C0 = parent.CFrame:ToObjectSpace(pivotCFrame)
			joint.C1 = part.CFrame:ToObjectSpace(pivotCFrame)
			joint.Parent = part
		end
	end

	addWear(model, look, colors, viewport)
	Builder.setHat(model, look.hat)

	if not viewport then
		root.CollisionGroup = Builder.COLLISION_GROUP
		local humanoid = Instance.new("Humanoid")
		humanoid.RigType = Enum.HumanoidRigType.R15
		humanoid.AutomaticScalingEnabled = false
		humanoid.HipHeight = Builder.HIP_HEIGHT
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.RequiresNeck = false
		humanoid.BreakJointsOnDeath = false
		humanoid.UseJumpPower = false
		humanoid.JumpHeight = Config.PLAYER_JUMP_HEIGHT
		humanoid.WalkSpeed = Config.PLAYER_WALK_SPEED
		humanoid.Parent = model
		-- players' computers get the whole animal at once, never half of it
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		CollectionService:AddTag(model, Builder.TAG)

		-- In Studio, say how big each kind of animal is, once (to keep an eye on how heavy they are)
		-- (the wardrobe check's animals are named "species: item", so they count once per body)
		local key = bodyKey .. "/" .. (if string.find(model.Name, ":") then "wardrobe" else model.Name)
		if RunService:IsStudio() and not counted[key] then
			counted[key] = true
			local things, meshes = 0, 0
			for _, thing in model:GetDescendants() do
				things += 1
				if thing:IsA("MeshPart") then
					meshes += 1
				end
			end
			print(`Animal count: {model.Name} ({bodyKey}) has {things} instances, {meshes} of them MeshParts`)
		end
	end

	return model
end

-- Puts a hat on (or takes it off, with nil). The hats are fitted to each animal's head.
function Builder.setHat(model: Model, hatId: string?)
	local old = model:FindFirstChild("Hat")
	if old then
		old:Destroy()
	end
	model:SetAttribute("Hat", hatId)
	if not hatId then
		return
	end

	local fileKey = `{model:GetAttribute("Species")}-hats`
	local file = Models.get(fileKey)
	if not file then
		return
	end
	local anchored = isAnchored(model)
	local folder = Instance.new("Folder")
	folder.Name = "Hat"
	for name in file.meshes do
		local id, kind = string.match(name, "^(.-)_(%w+)$")
		if id == hatId and kind then
			local mesh = copyMesh(fileKey, file, name, CFrame.identity, anchored)
			paint(mesh, kind, {})
			if attach(model, "Head", mesh) then
				mesh.Parent = folder
			end
		end
	end
	folder.Parent = model
end

-- Just a hat on its own, sitting on the origin (for shop shelves and pictures). nil if the
-- hats for that animal haven't been imported.
function Builder.hatModel(species: string, hatId: string): Model?
	local fileKey = species .. "-hats"
	local file = Models.get(fileKey)
	local layout = MeshLayout[fileKey]
	local main = layout and layout.meshes[hatId .. "_detail"]
	if not (file and main) then
		return nil
	end
	-- the bottom middle of the hat's box goes on the origin
	local base = centreOf(main) - Vector3.new(0, main[5] / 2, 0)
	local model = Instance.new("Model")
	model.Name = hatId
	for name in file.meshes do
		local id, kind = string.match(name, "^(.-)_(%w+)$")
		if id == hatId and kind then
			local mesh = copyMesh(fileKey, file, name, CFrame.new(-base), true)
			paint(mesh, kind, {})
			mesh.Parent = model
		end
	end
	model.WorldPivot = CFrame.identity
	return model
end

return Builder
