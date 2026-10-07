-- Everyone's pets, drawn and moved on this player's own screen (Config.PETS). Each player's
-- pet is in their Pet attribute (from the server); this builds it (shared/PetBuilder) and
-- walks it along behind its owner: it trots after them, sits when they stop, wags its tail,
-- and pops back beside them if it falls far behind. (It can hop when they jump too, but that's
-- off: Config.PETS.HOP.)
--
-- Keeping it cheap with lots of players: there's no physics at all (the parts don't collide
-- and aren't moved by the physics engine), nothing is sent over the network as pets walk, all
-- the pets' parts are moved together in one workspace:BulkMoveTo each frame, pets a little
-- way off are moved less often, and pets far away aren't shown.
--
-- In Studio, Config.PET_TEST_CROWD pretend pets walk round you, to check the frame rate.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Builder = require(Shared.CharacterBuilder)
local Config = require(Shared.Config)
local PetBuilder = require(Shared.PetBuilder)
local Ui = require(script.Parent.Ui)

local PETS = Config.PETS

local Pets = {}

type Walker = {
	owner: Player,
	saved: string, -- the Pet attribute it was built from
	pet: PetBuilder.Pet,
	tag: BillboardGui,
	spot: Vector3, -- where its feet are
	yaw: number,
	speed: number,
	phase: number,
	sit: number,
	still: number, -- seconds its owner has been standing still
	hop: number, -- how high it is in a hop
	rise: number, -- how fast it's going up (or down)
	ground: number, -- the height its owner stands at
	steady: number, -- seconds its owner has been neither rising nor falling
	waited: number, -- time since a far-away pet was last moved
	slot: number, -- which way round its owner it walks (the test crowd spreads out)
	shown: boolean,
	pose: PetBuilder.Pose, -- reused every frame
}

local walkers: { [any]: Walker } = {} -- keyed by player (or a number, for the test crowd)
local folder: Folder

local function nameTag(pet: PetBuilder.Pet, name: string): BillboardGui
	local tag = Ui.new("BillboardGui", {
		Size = UDim2.fromOffset(110, 24),
		StudsOffsetWorldSpace = Vector3.new(0, 1.6, 0),
		MaxDistance = PETS.NAME_DISTANCE,
		LightInfluence = 0,
		Adornee = pet.head,
		Parent = pet.model,
	})
	Ui.text({
		Text = name,
		TextSize = 16,
		TextColor3 = Ui.colors.ink,
		TextStrokeColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0.2,
		Size = UDim2.fromScale(1, 1),
		Parent = tag,
	})
	return tag
end

-- Builds (or rebuilds) a pet from a Pet attribute. nil if it doesn't make sense.
local function make(owner: Player, saved: string, slot: number, old: Walker?): Walker?
	local ok, look = pcall(function()
		return HttpService:JSONDecode(saved)
	end)
	if not (ok and typeof(look) == "table" and PETS.KINDS[look.kind]) then
		return nil
	end
	local pet = PetBuilder.build(look)
	local name = PETS.NAMES[look.name] or PETS.NAMES[1]
	local walker: Walker = {
		owner = owner,
		saved = saved,
		pet = pet,
		tag = nameTag(pet, name),
		spot = if old then old.spot else Vector3.zero,
		yaw = if old then old.yaw else 0,
		speed = 0,
		phase = 0,
		sit = 0,
		still = 0,
		hop = 0,
		rise = 0,
		ground = if old then old.ground else 0,
		steady = 0,
		waited = 0,
		slot = slot,
		shown = false,
		pose = table.clone(PetBuilder.STANDING),
	}
	if not old then
		walker.spot = Vector3.new(0, -1000, 0) -- placed beside its owner on its first step
	end
	return walker
end

local function remove(key: any)
	local walker = walkers[key]
	if walker then
		walker.pet.model:Destroy()
		walkers[key] = nil
	end
end

-- Keeps a player's pet up to date with their Pet attribute.
local function watch(player: Player)
	local function refresh()
		local saved = player:GetAttribute("Pet")
		local old = walkers[player]
		if typeof(saved) ~= "string" then
			remove(player)
			return
		end
		if old and old.saved == saved then
			return
		end
		local walker = make(player, saved, 0, old)
		if old then
			old.pet.model:Destroy()
		end
		walkers[player] = walker
	end
	player:GetAttributeChangedSignal("Pet"):Connect(refresh)
	refresh()
end

-- Moves one pet along by `dt` seconds, behind `root` (its owner).
local function step(walker: Walker, root: BasePart, dt: number, now: number): (CFrame, PetBuilder.Pose)
	local velocity = root.AssemblyLinearVelocity
	local flatSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local feet = root.Position.Y - Builder.ROOT_HEIGHT
	-- Follow its owner's height only once they've stayed at it a moment: at the top of a jump
	-- they stop rising for an instant, and that mustn't count as standing up there.
	if math.abs(velocity.Y) < 1 then
		walker.steady += dt
	else
		walker.steady = 0
	end
	if walker.steady > PETS.STEADY or walker.spot.Y < -500 then
		walker.ground = feet
	end

	-- where it wants to be: behind its owner, a little to one side
	local back = -root.CFrame.LookVector * Vector3.new(1, 0, 1)
	if back.Magnitude < 0.01 then
		back = Vector3.new(0, 0, 1)
	end
	back = back.Unit
	local turn = CFrame.Angles(0, walker.slot, 0)
	local side = turn:VectorToWorldSpace(Vector3.new(back.Z, 0, -back.X))
	local behind = turn:VectorToWorldSpace(back)
	local target = Vector3.new(root.Position.X, walker.ground, root.Position.Z) + behind * PETS.BEHIND + side * PETS.SIDE

	local flat = Vector3.new(target.X - walker.spot.X, 0, target.Z - walker.spot.Z)
	local gap = flat.Magnitude
	if gap > PETS.CATCH_UP or walker.spot.Y < -500 then
		walker.spot = target -- fell far behind: pop back beside its owner
		gap = 0
	elseif gap > 0.3 then
		local speed = math.min(PETS.SPEED, gap * 3)
		local move = math.min(gap, speed * dt)
		walker.spot += flat.Unit * move
		walker.speed = speed
		local want = math.atan2(-flat.X, -flat.Z)
		local diff = (want - walker.yaw + math.pi) % (2 * math.pi) - math.pi
		walker.yaw += diff * math.min(1, dt * 10)
	else
		walker.speed = 0
	end
	walker.spot = Vector3.new(walker.spot.X, walker.ground, walker.spot.Z)

	-- sit once its owner has stood still a moment and it's caught up (not while either of them
	-- is in the air: jumping on the spot isn't standing still)
	local airborne = math.abs(velocity.Y) > 1 or walker.hop > 0
	if flatSpeed < 1 and gap < 1.5 and not airborne then
		walker.still += dt
	else
		walker.still = 0
	end
	local sitting = walker.still > PETS.SIT_AFTER
	if airborne then
		walker.sit = 0 -- straight up for a hop
	else
		walker.sit += ((if sitting then 1 else 0) - walker.sit) * math.min(1, dt * 6)
	end

	-- hop when its owner jumps
	if PETS.HOP > 0 and velocity.Y > 6 and walker.hop <= 0 then
		walker.rise = PETS.HOP
	end
	walker.rise -= PETS.GRAVITY * dt
	walker.hop = math.max(0, walker.hop + walker.rise * dt)
	if walker.hop <= 0 and walker.rise < 0 then
		walker.rise = 0
	end

	local stride = math.min(1, walker.speed / 10)
	walker.phase += dt * (3 + walker.speed * 0.9)
	local pose = walker.pose
	pose.bob = math.abs(math.sin(walker.phase)) * 0.14 * stride
	pose.sit = walker.sit
	pose.roll = if walker.pet.kind == "duckling" then math.sin(walker.phase) * 0.12 * stride else 0
	pose.stride = stride
	pose.phase = walker.phase
	pose.wag = math.sin(now * (if walker.speed > 1 then 14 else 8)) * (if walker.pet.kind == "kitten" then 0.25 else 0.6)
	return CFrame.new(walker.spot + Vector3.new(0, walker.hop, 0)) * CFrame.Angles(0, walker.yaw, 0), pose
end

function Pets.start()
	folder = Instance.new("Folder")
	folder.Name = "Pets"
	folder.Parent = Workspace

	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(remove)

	-- Studio only: a crowd of pretend pets round you, to check the frame rate
	if RunService:IsStudio() and PETS and Config.PET_TEST_CROWD > 0 then
		local me = Players.LocalPlayer
		for i = 1, Config.PET_TEST_CROWD do
			local kind = PETS.ORDER[(i - 1) % #PETS.ORDER + 1]
			local look = HttpService:JSONEncode({ kind = kind, color = (i - 1) % 3 + 1, name = (i - 1) % #PETS.NAMES + 1 })
			walkers[i] = make(me, look, i / Config.PET_TEST_CROWD * math.pi * 2, nil) :: Walker
		end
		print(`Pets: {Config.PET_TEST_CROWD} pretend pets for testing (Config.PET_TEST_CROWD)`)
	end

	-- the parts to move and where to, filled afresh each frame (the tables are reused)
	local parts: { BasePart } = {}
	local cframes: { CFrame } = {}
	RunService.RenderStepped:Connect(function(dt)
		local now = os.clock()
		local camera = Workspace.CurrentCamera
		local eye = if camera then camera.CFrame.Position else Vector3.zero
		table.clear(parts)
		table.clear(cframes)
		for _, walker in walkers do
			local character = walker.owner.Character
			local root = character and character.PrimaryPart
			-- hidden past FAR, and only shown again a little nearer
			local limit = if walker.shown then PETS.FAR else PETS.FAR - PETS.SHOW_AGAIN
			local far = root == nil or (root.Position - eye).Magnitude > limit
			if far then
				if walker.shown then
					walker.shown = false
					walker.pet.model.Parent = nil
				end
				continue
			end
			if not walker.shown then
				walker.shown = true
				walker.pet.model.Parent = folder
			end
			local gap = ((root :: BasePart).Position - eye).Magnitude
			local by = dt
			if gap > PETS.NEAR then
				-- a little way off: moving it less often looks the same, and costs less
				walker.waited += dt
				if walker.waited < PETS.FAR_STEP then
					continue
				end
				by = walker.waited
			end
			walker.waited = 0
			local at, pose = step(walker, root :: BasePart, by, now)
			PetBuilder.pose(walker.pet, at, pose, parts, cframes)
		end
		if #parts > 0 then
			Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end)
end

return Pets
