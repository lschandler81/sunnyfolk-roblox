-- Makes every animal move: walking, breathing, looking around, blinking, nodding while it
-- talks and waving hello. It's the web game's src/chars/animate.js, worked out in the same
-- (web) units and turned into Roblox joint angles at the end.
--
-- It runs on each player's own computer, for every animal nearby, so it costs the server
-- nothing. Animals are found by their CharacterBuilder tag.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Builder = require(Shared.CharacterBuilder)
local Config = require(Shared.Config)

local S = Config.STUDS
local WALK_SPEED = 14 -- studs a second that counts as a normal walk
local ANIMATE = Config.ANIMATE -- how far away animals are animated, and how often

-- The web game's left arm (side -1) is Roblox's right arm: the models were turned round to
-- face -Z when they were exported.
local SIDES = {
	{ arm = "RightArm", leg = "RightLeg", side = -1 },
	{ arm = "LeftArm", leg = "LeftLeg", side = 1 },
}

type Rig = {
	model: Model,
	root: BasePart,
	joints: { [string]: Motor6D },
	eyes: { { part: BasePart, size: Vector3 } },
	rayParams: RaycastParams,
	phase: number,
	walk: number,
	air: number,
	look: number,
	lookT: number,
	lookTarget: number,
	blink: number,
	blinkT: number,
	eyesShut: boolean,
	talk: number,
	wave: number,
	offset: number, -- so showcase animals don't all move in step
	waited: number, -- time since a far-away animal was last updated
}

local Animator = {}
local rigs: { [Model]: Rig } = {}
local random = Random.new()

local function makeRig(model: Model): Rig?
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return nil
	end
	local joints = {}
	for _, partName in Builder.PARTS do
		local part = model:FindFirstChild(partName)
		local joint = part and part:FindFirstChild("Joint")
		if joint and joint:IsA("Motor6D") then
			joints[partName] = joint
		end
	end
	local eyes = {}
	for _, eyeName in { "RightEye", "LeftEye" } do
		local eye = model:FindFirstChild(eyeName)
		if eye and eye:IsA("BasePart") then
			table.insert(eyes, { part = eye, size = eye.Size })
		end
	end
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { model }
	rayParams.RespectCanCollide = true
	rayParams.CollisionGroup = Builder.COLLISION_GROUP
	return {
		model = model,
		root = root,
		joints = joints,
		eyes = eyes,
		rayParams = rayParams,
		phase = random:NextNumber(0, 6),
		walk = 0,
		air = 0,
		look = 0,
		lookT = 3,
		lookTarget = 0,
		blink = 0,
		blinkT = random:NextNumber(2, 5),
		eyesShut = false,
		talk = 0,
		wave = 0,
		offset = random:NextNumber(0, 12),
		waited = random:NextNumber(0, Config.ANIMATE.FAR_STEP), -- spread far-away updates out

	}
end

-- The pose of an arm that's holding something, in web units: { x, z, holding }.
local function armPose(model: Model, arm: string): (number, number, boolean)
	local pose = model:GetAttribute(arm .. "Pose")
	if typeof(pose) == "Vector2" then
		return -pose.X, -pose.Y, true
	end
	return 0, 0, false
end

local function setJoint(rig: Rig, partName: string, transform: CFrame)
	local joint = rig.joints[partName]
	if joint then
		joint.Transform = transform
	end
end

-- Web rotations (x, y, z) to a Roblox joint angle: x and z flip because the models face -Z.
local function angles(x: number, y: number, z: number): CFrame
	return CFrame.Angles(-x, y, -z)
end

local function step(rig: Rig, dt: number, time: number)
	local a = rig
	local velocity = rig.root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude / WALK_SPEED
	local reach = Builder.ROOT_SIZE.Y / 2 + Builder.HIP_HEIGHT + 0.6
	local grounded = Workspace:Raycast(rig.root.Position, Vector3.new(0, -reach, 0), rig.rayParams) ~= nil

	-- the wardrobe check's animals walk on the spot, stand still and wave, in turn
	if rig.model:GetAttribute("Showcase") then
		local beat = (time + rig.offset) % 12
		speed = if beat < 5 then 1 else 0
		grounded = true
		if beat >= 9 and beat < 9 + dt then
			a.wave = 1.6
		end
	end

	-- ease the walk in and out
	a.walk += (math.min(speed, 1.4) - a.walk) * math.min(1, dt * 10)
	a.phase += dt * (3 + 9 * math.min(speed, 1.6))
	local w = if grounded then a.walk else 0
	local s = math.sin(a.phase)
	local c = math.cos(a.phase)
	a.air += ((if grounded then 0 else 1) - a.air) * math.min(1, dt * 12)
	a.talk = math.max(0, a.talk - dt)
	a.wave = math.max(0, a.wave - dt)

	-- legs and arms swing opposite ways; an arm holding something keeps its pose
	local _, _, leftBusy = armPose(rig.model, "LeftArm")
	local waver = if leftBusy then 1 else 2 -- wave with the left arm, unless it's holding something
	for i, info in SIDES do
		local side = info.side
		local poseX, poseZ, holding = armPose(rig.model, info.arm)
		local k = if holding then 0.2 else 1
		local legX = s * 0.75 * w * side - a.air * 0.5
		local armX = poseX - s * 0.7 * w * side * k - a.air * 1.4 * k
		local armZ = poseZ + side * (0.08 + a.air * 0.5 * k + (1 - w) * math.sin(time * 2) * 0.03)
		if a.wave > 0 and i == waver then
			local up = math.min(1, a.wave * 4, (1.6 - a.wave) * 4)
			armX = -0.4 * up
			armZ = side * (2.4 * up + math.sin(time * 14) * 0.25 * up)
		end
		setJoint(rig, info.leg, angles(legX, 0, 0))
		setJoint(rig, info.arm, angles(armX, 0, armZ))
	end

	-- the body bobs and waddles as it walks, and breathes when it stands
	local breathe = math.sin(time * 2.2) * 0.015 * (1 - w)
	local bodyY = math.abs(c) * 0.09 * w + breathe
	local bodyX = 0.06 * w - a.air * 0.08
	local bodyZ = s * 0.07 * w
	setJoint(rig, "Torso", CFrame.new(0, bodyY * S, 0) * angles(bodyX, 0, bodyZ))

	-- the head looks around now and then, and nods while talking
	a.lookT -= dt
	if a.lookT < 0 then
		a.lookT = random:NextNumber(2, 6)
		a.lookTarget = if speed > 0.1 then 0 else random:NextNumber(-0.5, 0.5)
	end
	a.look += (a.lookTarget * (1 - w) - a.look) * math.min(1, dt * 3)
	local nod = if a.talk > 0 then math.sin(time * 16) * 0.06 else 0
	local headX = -math.abs(s) * 0.05 * w + math.sin(time * 1.3) * 0.02 * (1 - w) - a.air * 0.1 + nod
	setJoint(rig, "Head", angles(headX, a.look, 0))

	-- blink every few seconds by squashing the eyes flat
	a.blinkT -= dt
	if a.blinkT < 0 then
		a.blink = 0.14
		a.blinkT = random:NextNumber(2.5, 6.5)
	end
	a.blink = math.max(0, a.blink - dt)
	local shut = a.blink > 0
	if shut ~= a.eyesShut then
		a.eyesShut = shut
		for _, eye in rig.eyes do
			eye.part.Size = if shut then eye.size * Vector3.new(1, 0.12, 1) else eye.size
		end
	end
end

-- Nod along for a few seconds (while saying something).
function Animator.talk(model: Model, seconds: number)
	local rig = rigs[model]
	if rig then
		rig.talk = seconds
	end
end

-- A friendly wave.
function Animator.wave(model: Model)
	local rig = rigs[model]
	if rig then
		rig.wave = 1.6
	end
end

function Animator.start()
	local function added(instance: Instance)
		if instance:IsA("Model") and not rigs[instance] then
			-- the parts can arrive a moment after the model does
			task.defer(function()
				instance:WaitForChild("HumanoidRootPart", 10)
				if instance.Parent and CollectionService:HasTag(instance, Builder.TAG) then
					local rig = makeRig(instance)
					if rig then
						rigs[instance] = rig
					end
				end
			end)
		end
	end
	CollectionService:GetInstanceAddedSignal(Builder.TAG):Connect(added)
	CollectionService:GetInstanceRemovedSignal(Builder.TAG):Connect(function(instance)
		rigs[instance :: Model] = nil
	end)
	for _, instance in CollectionService:GetTagged(Builder.TAG) do
		added(instance)
	end

	RunService.PreSimulation:Connect(function(dt)
		local time = os.clock()
		local camera = Workspace.CurrentCamera
		for model, rig in rigs do
			if not model:IsDescendantOf(Workspace) then
				continue
			end
			local distance = if camera then (rig.root.Position - camera.CFrame.Position).Magnitude else 0
			if distance > ANIMATE.FAR then
				rig.waited = 0
				continue
			end
			if distance > ANIMATE.NEAR then
				-- far enough away that updating a little less often looks the same, and costs less
				rig.waited += dt
				if rig.waited < ANIMATE.FAR_STEP then
					continue
				end
				step(rig, rig.waited, time)
				rig.waited = 0
			else
				rig.waited = 0
				step(rig, dt, time)
			end
		end
	end)
end

return Animator
