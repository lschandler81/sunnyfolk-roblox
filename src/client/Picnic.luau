-- A picnic on the blanket by the big yuzu tree (Config.PICNIC, server/Town). Its "Have a
-- picnic" button walks your animal onto a free spot on the blanket, turns it to face the
-- basket and the yuzus, and sits it down, using the "sit" emote, so everyone nearby sees you
-- sitting too (client/Emotes, server/Emotes). Walking off ends it, like any sit.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Config = require(Shared.Config)
local Animator = require(script.Parent.Animator)
local Hud = require(script.Parent.Hud)
local Ui = require(script.Parent.Ui)

local Remotes = Shared:WaitForChild("Remotes")
local player = Players.LocalPlayer

local S = Config.STUDS
local P = Config.PICNIC

local Picnic = {}

local sitting = false -- walking to a spot right now
local last = 0 -- when you last sat down (so a spam of taps doesn't use up the emotes' limit)

-- The free spot on the blanket nearest to `from` (or the nearest, if they're all taken).
local function spotFor(from: Vector3): Vector3
	local blanket = Config.picnicFrame()
	local best, bestScore = blanket.Position, math.huge
	for _, each in Config.PICNIC.SPOTS do
		local spot = (blanket * CFrame.new(each[1] * S, 0, each[2] * S)).Position
		local score = (spot - Vector3.new(from.X, spot.Y, from.Z)).Magnitude
		for _, other in Players:GetPlayers() do
			local root = other ~= player and other.Character and other.Character.PrimaryPart
			if root and (Vector3.new(root.Position.X, spot.Y, root.Position.Z) - spot).Magnitude < P.TAKEN then
				score += 1000 -- (taken: only if they all are)
			end
		end
		if score < bestScore then
			best, bestScore = spot, score
		end
	end
	return best
end

local function haveAPicnic()
	local character = player.Character
	local root = character and character.PrimaryPart
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	-- (not on the welcome screen, with a screen open, or just after sitting down)
	local hud = Hud.gui()
	if sitting or not (character and root and humanoid) or not (hud and hud.Enabled) or Ui.openScreens > 0
		or os.clock() - last < Config.EMOTE_WAIT then
		return
	end
	sitting = true
	local spot = spotFor(root.Position)
	humanoid:MoveTo(Vector3.new(spot.X, root.Position.Y, spot.Z))
	local finished = false
	local done = humanoid.MoveToFinished:Once(function()
		finished = true
	end)
	local started = os.clock()
	while not finished and os.clock() - started < P.WALK_SECONDS and character.Parent do
		task.wait(0.1)
	end
	done:Disconnect()
	-- a moment to stop, so the last step doesn't undo the sit
	started = os.clock()
	while character.Parent and os.clock() - started < P.SETTLE_SECONDS
		and Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude > 1 do
		task.wait(0.05)
	end
	sitting = false
	local here = root.Position
	if not character.Parent or (Vector3.new(here.X, spot.Y, here.Z) - spot).Magnitude > P.THERE then
		return -- (they walked off another way)
	end
	-- face the middle of the blanket (the basket and the yuzus), and sit down
	local middle = Config.picnicFrame().Position
	if (Vector3.new(middle.X, here.Y, middle.Z) - here).Magnitude > 0.1 then
		root.CFrame = CFrame.lookAt(here, Vector3.new(middle.X, here.Y, middle.Z))
	end
	root.AssemblyLinearVelocity = Vector3.zero
	last = os.clock()
	Animator.emote(character, "sit")
	Remotes.Emote:FireServer("sit")
end

function Picnic.start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name == "Picnic" then
			haveAPicnic()
		end
	end)
end

return Picnic
