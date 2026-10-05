-- The wardrobe check: a fitting room for testing in Studio. When Config.WARDROBE_CHECK is on,
-- pressing Play builds rows of every imported animal wearing every hat, every piece of
-- clothing, every scarf colour and every held thing, each with a label, and you start
-- there instead of in town. The animals take turns walking, standing and waving, so you can
-- spot anything that pokes through or doesn't line up. Anything missing is listed in the
-- Output.
--
-- It only works in Studio, so it can't be left on by mistake for players.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Build = require(Shared.Build)
local Builder = require(Shared.CharacterBuilder)
local Config = require(Shared.Config)
local Looks = require(Shared.Looks)
local Models = require(Shared.Models)

local Wardrobe = {}

local ORIGIN = Vector3.new(0, 0, 1100) -- well away from the town
local SPACING = 7 -- studs between animals in a row
local ROW_GAP = 16 -- studs between rows
local ANIMALS = { "capybara", "bunny", "guineapig", "duck", "penguin", "frog" }

local function nameTag(model: Model, text: string)
	local root = model.PrimaryPart
	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.fromOffset(150, 40)
	tag.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)
	tag.MaxDistance = 45
	tag.LightInfluence = 0
	local words = Instance.new("TextLabel")
	words.Size = UDim2.fromScale(1, 1)
	words.BackgroundTransparency = 1
	words.Text = text
	words.Font = Enum.Font.FredokaOne
	words.TextScaled = true
	words.TextColor3 = Build.C.ink
	words.TextStrokeColor3 = Color3.new(1, 1, 1)
	words.TextStrokeTransparency = 0.3
	words.Parent = tag
	tag.Parent = root
end

-- Is there anything of `id` on this animal (in its Hat or Wear folder)?
local function wearing(model: Model, folderName: string, id: string): boolean
	local folder = model:FindFirstChild(folderName)
	if not folder then
		return false
	end
	for _, part in folder:GetChildren() do
		if string.sub(part.Name, 1, #id + 1) == id .. "_" then
			return true
		end
	end
	return false
end

-- Builds the fitting room, if it's turned on. Returns where players should start, or nil.
function Wardrobe.build(): CFrame?
	if not (Config.WARDROBE_CHECK and RunService:IsStudio()) then
		return nil
	end
	local folder = Instance.new("Folder")
	folder.Name = "WardrobeCheck"
	folder.Parent = Workspace

	local data = Looks.data
	local missing = {}
	local z = 0
	local widest = 0
	local function place(look, label: string, column: number): Model
		local at = CFrame.new(ORIGIN + Vector3.new(column * SPACING, 0, z)) -- facing the way in (-Z)
		local model = Builder.build(look, { cframe = at, name = label })
		model:SetAttribute("Showcase", true) -- Animator: walk on the spot, stand, wave
		;(model.PrimaryPart :: BasePart).Anchored = true
		nameTag(model, label)
		model.Parent = folder
		widest = math.max(widest, column)
		return model
	end

	for _, species in ANIMALS do
		if not Models.get(species) then
			continue
		end
		-- a row of hats
		for i, hat in data.hats do
			local model = place({ species = species, hat = hat.id }, `{species}: {hat.name}`, i - 1)
			if not wearing(model, "Hat", hat.id) then
				table.insert(missing, `{species} hat "{hat.id}"`)
			end
		end
		z += ROW_GAP
		-- a row of clothes, then the scarf in every colour
		local column = 0
		for _, item in data.clothes do
			if item.id ~= "scarf" then
				local model = place({ species = species, clothes = { item.id } }, `{species}: {item.name}`, column)
				if not wearing(model, "Wear", item.id) then
					table.insert(missing, `{species} clothes "{item.id}"`)
				end
				column += 1
			end
		end
		for _, hex in Looks.scarves() do
			local model = place({ species = species, clothes = { "scarf" }, scarf = hex }, `{species}: scarf {hex}`, column)
			if not wearing(model, "Wear", "scarf") then
				table.insert(missing, `{species} clothes "scarf"`)
			end
			column += 1
		end
		z += ROW_GAP
		-- a row of things to hold
		for i, item in data.held do
			local model = place({ species = species, held = { item.id } }, `{species}: {item.id}`, i - 1)
			if not wearing(model, "Wear", item.id) then
				table.insert(missing, `{species} held "{item.id}"`)
			end
		end
		z += ROW_GAP * 1.5
	end

	-- a floor to stand on
	Build.into(folder)
	local width = (widest + 2) * SPACING
	Build.block(Vector3.new(width + 20, 2, z + 30), CFrame.new(ORIGIN + Vector3.new(width / 2 - SPACING, -1, z / 2 - 10)), Build.C.grass)

	if #missing > 0 then
		warn(`Wardrobe check: {#missing} things are missing (is that animal's -hats or -clothes file imported?):\n  `
			.. table.concat(missing, "\n  "))
	else
		print("Wardrobe check: every hat, piece of clothing and held thing is there.")
	end
	-- start at the front, looking along the rows
	return CFrame.lookAt(ORIGIN + Vector3.new(-SPACING * 2, 0, -14), ORIGIN + Vector3.new(SPACING * 4, 0, 10))
end

return Wardrobe
