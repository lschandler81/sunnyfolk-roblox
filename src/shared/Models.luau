-- Finds the character models imported from assets/characters (see docs/roblox-studio.md)
-- inside ReplicatedStorage.SunnyfolkModels.
--
-- Each .glb file is looked up by its file name ("capybara-hats") or the name of its top group
-- ("CapybaraHats"), ignoring capitals, dashes and spaces, so it doesn't matter exactly how
-- Studio named the imported model. It also works out whether Studio turned the model round
-- or resized it while importing, so CharacterBuilder can put that right.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MeshLayout = require(script.Parent.MeshLayout)

local Models = {}

export type File = {
	meshes: { [string]: MeshPart }, -- "Head_detail" -> the imported MeshPart
	unturn: CFrame, -- undoes any turn Studio gave the model when it was imported
	scale: number, -- multiply the imported sizes by this to get studs
}

local folder = ReplicatedStorage:WaitForChild("SunnyfolkModels")
local cache: { [string]: File | false } = {}
local warned: { [string]: boolean } = {}

local function simple(name: string): string
	return string.lower((string.gsub(name, "[^%w]", "")))
end

local function centre(m): Vector3
	return Vector3.new(m[1], m[2], m[3])
end

-- A rotation that's within a few degrees of a whole number of quarter turns becomes exact.
local function tidyTurn(turn: CFrame): CFrame
	local _, _, _, a, b, c, d, e, f, g, h, i = turn:GetComponents()
	local values = { a, b, c, d, e, f, g, h, i }
	for n, v in values do
		local r = math.round(v)
		if math.abs(v - r) > 0.1 then
			return turn -- not a neat turn; keep it as it is
		end
		values[n] = r
	end
	return CFrame.new(0, 0, 0, table.unpack(values))
end

-- Compares where the meshes ended up with where they were exported, to find any turn and
-- resizing Studio applied to the whole model.
local function measure(fileKey: string, meshes: { [string]: MeshPart }): (CFrame, number)
	local layout = MeshLayout[fileKey].meshes
	local names = {}
	for name in meshes do
		table.insert(names, name)
	end
	table.sort(names)
	if #names < 3 then
		return CFrame.identity, 1
	end
	-- three meshes spread well apart
	local p0 = names[1]
	local p1, far = names[2], -1
	for _, name in names do
		local d = (centre(layout[name]) - centre(layout[p0])).Magnitude
		if d > far then
			p1, far = name, d
		end
	end
	local p2, wide = names[3], -1
	local along = centre(layout[p1]) - centre(layout[p0])
	for _, name in names do
		local w = (centre(layout[name]) - centre(layout[p0])):Cross(along).Magnitude
		if w > wide then
			p2, wide = name, w
		end
	end
	if far < 0.3 or wide < 0.05 then
		return CFrame.identity, 1
	end

	local function frame(a: Vector3, b: Vector3): CFrame
		local x = a.Unit
		local y = a:Cross(b).Unit
		return CFrame.fromMatrix(Vector3.zero, x, y, x:Cross(y))
	end
	local wasA = centre(layout[p1]) - centre(layout[p0])
	local wasB = centre(layout[p2]) - centre(layout[p0])
	local nowA = meshes[p1].Position - meshes[p0].Position
	local nowB = meshes[p2].Position - meshes[p0].Position
	if nowA.Magnitude < 1e-4 or nowA:Cross(nowB).Magnitude < 1e-6 then
		return CFrame.identity, 1
	end
	local turn = tidyTurn(frame(nowA, nowB) * frame(wasA, wasB):Inverse())
	return turn:Inverse(), wasA.Magnitude / nowA.Magnitude
end

local function countOf(t: { [string]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

-- How far an imported copy's mesh sizes are from the current file's (0 is a perfect match).
-- Sizes are compared smallest-to-largest, so a turned import still matches.
local function misfit(fileKey: string, meshes: { [string]: MeshPart }, scale: number): number
	local layout = MeshLayout[fileKey].meshes
	local total, n = 0, 0
	for name, mesh in meshes do
		local m = layout[name]
		local want = { m[4], m[5], m[6] }
		local have = { mesh.Size.X * scale, mesh.Size.Y * scale, mesh.Size.Z * scale }
		table.sort(want)
		table.sort(have)
		for i = 1, 3 do
			total += math.abs(have[i] - want[i]) / math.max(want[i], 0.05)
		end
		n += 1
	end
	return if n > 0 then total / n else math.huge
end

-- One model file's meshes, or nil if it hasn't been imported yet.
function Models.get(fileKey: string): File?
	local cached = cache[fileKey]
	if cached ~= nil then
		return cached or nil
	end

	local layout = MeshLayout[fileKey]
	if not layout then
		warn(`Sunnyfolk: there's no model file called "{fileKey}" in assets/characters`)
		cache[fileKey] = false
		return nil
	end

	-- Every imported copy of this model. If there's more than one (say, an old import left
	-- next to a new one), use the copy whose shapes best match the current file.
	local wanted = { [simple(fileKey)] = true, [simple(layout.root)] = true }
	local candidates = {}
	for _, container in folder:GetDescendants() do
		if (container:IsA("Model") or container:IsA("Folder")) and wanted[simple(container.Name)] then
			local meshes = {}
			local count = 0
			for _, mesh in container:GetDescendants() do
				if mesh:IsA("MeshPart") and layout.meshes[mesh.Name] and not meshes[mesh.Name] then
					meshes[mesh.Name] = mesh
					count += 1
				end
			end
			-- skip a container that's just inside another copy we've already got
			local inside = false
			for _, other in candidates do
				if container:IsDescendantOf(other.container) then
					inside = true
				end
			end
			if count > 0 and not inside then
				local unturn, scale = measure(fileKey, meshes)
				table.insert(candidates, {
					container = container,
					file = { meshes = meshes, unturn = unturn, scale = scale },
					misfit = misfit(fileKey, meshes, scale) + (if count < countOf(layout.meshes) then 1 else 0),
				})
			end
		end
	end
	table.sort(candidates, function(a, b)
		return a.misfit < b.misfit
	end)
	local found: File? = if candidates[1] then candidates[1].file else nil
	if #candidates > 1 then
		local ignored = {}
		for i = 2, #candidates do
			table.insert(ignored, candidates[i].container:GetFullName())
		end
		warn(`Sunnyfolk: there's more than one "{fileKey}" model. Using {candidates[1].container:GetFullName()}, which matches`
			.. ` assets/characters/{fileKey}.glb best. You can delete: {table.concat(ignored, ", ")}`)
	end

	if not found and not warned[fileKey] then
		warned[fileKey] = true
		warn(
			`Sunnyfolk: couldn't find the "{fileKey}" model in ReplicatedStorage.SunnyfolkModels. `
				.. `Import assets/characters/{fileKey}.glb as described in docs/roblox-studio.md. `
				.. "Using a stand-in until then."
		)
	end
	cache[fileKey] = found or false
	return found
end

-- Just the meshes of one model file, by name.
function Models.meshes(fileKey: string): { [string]: MeshPart }?
	local file = Models.get(fileKey)
	return file and file.meshes
end

return Models
