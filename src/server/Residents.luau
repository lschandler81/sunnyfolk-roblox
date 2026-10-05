-- The animals who live in the square (Config.RESIDENTS). Each one strolls about near their
-- home, and stops to face you when you talk to them. What they say is shown by
-- client/Talk; their looks and lines come from assets/characters/sunnyfolk.json.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Builder = require(Shared.CharacterBuilder)
local Config = require(Shared.Config)
local Looks = require(Shared.Looks)

local S = Config.STUDS
local TALK_PAUSE = 8 -- seconds a resident stays put after you talk to them

local Residents = {}

Residents.TAG = "SunnyfolkResident"

local random = Random.new()

local function prompt(parent: Instance, name: string, action: string, object: string, key: Enum.KeyCode, pad: Enum.KeyCode): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.Name = name
	p.ActionText = action
	p.ObjectText = object
	p.KeyboardKeyCode = key
	p.GamepadKeyCode = pad
	p.HoldDuration = 0
	p.MaxActivationDistance = 12
	p.RequiresLineOfSight = false
	p.Parent = parent
	return p
end

-- A spot near home to stroll to, keeping out of the fountain.
local function strollSpot(home: Vector3, radius: number): Vector3
	for _ = 1, 10 do
		local a = random:NextNumber(0, math.pi * 2)
		local spot = home + Vector3.new(math.cos(a), 0, math.sin(a)) * random:NextNumber(0, radius)
		if spot.Magnitude > (Config.FOUNTAIN_R + 1.5) * S then
			return spot
		end
	end
	return home
end

local function addResident(id: string, folder: Folder)
	local info = Looks.resident(id)
	if not info then
		warn(`Sunnyfolk: there's no resident called "{id}" in sunnyfolk.json`)
		return
	end
	local home = Config.fromWeb(info.home.at[1], info.home.at[2])
	local radius = info.home.r * S
	local at = CFrame.lookAt(home, Vector3.zero) -- facing the fountain

	local model = Builder.build(Looks.residentLook(info), { cframe = at, name = info.name })
	model:SetAttribute("DisplayName", info.name)
	model:SetAttribute("ResidentId", id)
	CollectionService:AddTag(model, Residents.TAG)

	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.WalkSpeed = Config.RESIDENT_WALK_SPEED
	for _, state in { Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Ragdoll, Enum.HumanoidStateType.Climbing } do
		humanoid:SetStateEnabled(state, false)
	end

	local root = model.PrimaryPart :: BasePart
	local chest = Instance.new("Attachment")
	chest.Name = "Prompts"
	chest.Position = Vector3.new(0, 0.6, 0)
	chest.Parent = root
	local talk = prompt(chest, "Talk", "Talk", info.name, Enum.KeyCode.E, Enum.KeyCode.ButtonX)
	if id == "clover" then
		prompt(chest, "HatShop", "Hat Shop", "Clover's", Enum.KeyCode.F, Enum.KeyCode.ButtonY)
	end

	model.Parent = folder
	root:SetNetworkOwner(nil)

	-- Stop and look at whoever's talking.
	local pausedUntil = 0
	talk.Triggered:Connect(function(player)
		local other = player.Character and player.Character.PrimaryPart
		pausedUntil = os.clock() + TALK_PAUSE
		humanoid:MoveTo(root.Position)
		if other then
			local target = Vector3.new(other.Position.X, root.Position.Y, other.Position.Z)
			if (target - root.Position).Magnitude > 0.1 then
				root.CFrame = CFrame.lookAt(root.Position, target)
			end
		end
	end)

	-- Stroll about now and then.
	task.spawn(function()
		while model.Parent do
			task.wait(random:NextNumber(3, 8))
			if os.clock() > pausedUntil and model.Parent then
				humanoid:MoveTo(strollSpot(home, radius))
			end
		end
	end)
end

function Residents.start(doors: { [string]: CFrame })
	local folder = Instance.new("Folder")
	folder.Name = "Residents"
	folder.Parent = Workspace
	for _, id in Config.RESIDENTS do
		addResident(id, folder)
	end

	-- You can also open the Hat Shop at its door.
	local door = doors.hats
	if door then
		local spot = Instance.new("Part")
		spot.Name = "HatShopDoor"
		spot.Anchored = true
		spot.CanCollide = false
		spot.CanQuery = false
		spot.CanTouch = false
		spot.Transparency = 1
		spot.Size = Vector3.new(4, 4, 1)
		spot.CFrame = door * CFrame.new(0, 3, -1.5)
		prompt(spot, "HatShop", "Look at hats", "Hat Shop", Enum.KeyCode.F, Enum.KeyCode.ButtonY)
		spot.Parent = folder
	end
end

return Residents
