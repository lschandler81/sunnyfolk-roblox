-- Emotes: waving, cheering, dancing and sitting, so friends can say hello without typing
-- (client/Emotes). The animation runs on each player's own screen; all the server does is pass
-- the emote's name on to the players near whoever did it, once it has checked the name is one
-- of Config.EMOTES and that they aren't sending them too fast (Config.REMOTE_LIMITS.Emote).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Config = require(Shared.Config)
local RemoteGuard = require(script.Parent.RemoteGuard)

local Remotes = Shared:WaitForChild("Remotes")

local Emotes = {}

function Emotes.start()
	Remotes.Emote.OnServerEvent:Connect(function(player, id)
		if not RemoteGuard.allow(player, "Emote") then
			return
		end
		if typeof(id) ~= "string" or not Config.emote(id) then
			return
		end
		local root = player.Character and player.Character.PrimaryPart
		if not root then
			return
		end
		-- to everyone else close enough to see it (the sender plays it on their own screen)
		for _, other in Players:GetPlayers() do
			local theirs = other ~= player and other.Character and other.Character.PrimaryPart
			if theirs and (theirs.Position - root.Position).Magnitude <= Config.EMOTE_RANGE then
				Remotes.Emote:FireClient(other, player, id)
			end
		end
	end)
end

return Emotes
