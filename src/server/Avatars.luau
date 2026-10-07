-- Gives each player the animal they picked, and puts it in the town.
--
-- Players.CharacterAutoLoads is off (in default.project.json), so nobody gets a normal Roblox
-- avatar: the character appears when the player presses Play on the welcome screen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Builder = require(Shared.CharacterBuilder)
local Config = require(Shared.Config)
local Looks = require(Shared.Looks)
local Analytics = require(script.Parent.Analytics)
local PlayerData = require(script.Parent.PlayerData)
local RemoteGuard = require(script.Parent.RemoteGuard)

local Remotes = Shared:WaitForChild("Remotes")

local Avatars = {}

-- Where players appear. The wardrobe check moves this to its fitting room.
Avatars.spawnPoint = Config.SPAWN

-- Checks what a player picked on the welcome screen. nil if it doesn't make sense.
local function checkChoice(choice: any): PlayerData.Choice?
	if typeof(choice) ~= "table" or not table.find(Config.START_ANIMALS, choice.species) then
		return nil
	end
	-- (scarf == scarf is false for "not a number", which would get past math.clamp)
	local scarf = if typeof(choice.scarf) == "number" and choice.scarf == choice.scarf then math.floor(choice.scarf) else 1
	return {
		species = choice.species,
		coat = Looks.coat(choice.species, if typeof(choice.coat) == "string" then choice.coat else nil).id,
		scarf = math.clamp(scarf, 1, #Looks.scarves()),
	}
end

-- Where the feet go for someone standing where `character` is now.
local function standingAt(character: Model?): CFrame?
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) or root.Position.Y < -20 then
		return nil
	end
	local feet = root.Position - Vector3.new(0, Builder.ROOT_HEIGHT, 0)
	local facing = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	if facing.Magnitude < 0.01 then
		facing = Vector3.new(0, 0, -1)
	end
	return CFrame.lookAt(feet, feet + facing)
end

-- Builds (or rebuilds) a player's animal. A new animal appears where the old one stood.
function Avatars.spawn(player: Player, atStart: boolean?)
	local data = PlayerData.get(player)
	if not (data and data.look and player.Parent) then
		return
	end
	local old = player.Character
	local at = (not atStart and standingAt(old)) or Avatars.spawnPoint

	local character = Builder.build(Looks.playerLook(data.look, data.hat, data.wearing), { cframe = at, name = player.Name })
	character:SetAttribute("DisplayName", player.DisplayName)
	character:SetAttribute("UserId", player.UserId)
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
	for _, state in { Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Ragdoll } do
		humanoid:SetStateEnabled(state, false)
	end
	humanoid.Died:Connect(function()
		task.wait(2)
		if player.Character == character then
			Avatars.spawn(player, true)
		end
	end)

	if old then
		old:Destroy()
	end
	character.Parent = Workspace
	player.Character = character
	local root = character.PrimaryPart :: BasePart
	root:SetNetworkOwner(player)
end

function Avatars.start()
	local lastPlay: { [Player]: number } = {}

	-- The welcome screen's Play button (and "Change animal").
	Remotes.Play.OnServerEvent:Connect(function(player, choice)
		if not RemoteGuard.allow(player, "Play") then
			return
		end
		if os.clock() - (lastPlay[player] or 0) < 1 then
			return
		end
		lastPlay[player] = os.clock()
		local checked = checkChoice(choice)
		if checked then
			local changed, firstTime = false, false
			PlayerData.update(player, function(data)
				changed, firstTime = true, data.look == nil
				data.look = checked
			end)
			if changed then
				Analytics.step(player, Analytics.CHOSE_ANIMAL, firstTime)
			end
			Avatars.spawn(player, player.Character == nil)
		end
	end)

	-- Analytics: a player joining who has never picked an animal is a new player.
	PlayerData.onLoaded(function(player)
		local data = PlayerData.get(player)
		Analytics.step(player, Analytics.JOINED, data ~= nil and data.look == nil)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastPlay[player] = nil
		if player.Character then
			player.Character:Destroy()
		end
	end)

	-- Anyone who somehow ends up under the town goes back to the fountain.
	task.spawn(function()
		while true do
			task.wait(2)
			for _, player in Players:GetPlayers() do
				local root = player.Character and player.Character.PrimaryPart
				if root and root.Position.Y < -20 then
					Avatars.spawn(player, true)
				end
			end
		end
	end)
end

return Avatars
