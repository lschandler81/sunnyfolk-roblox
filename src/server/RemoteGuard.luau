-- Stops any one player asking the server for things too often (say, a script spamming "buy
-- this hat" hundreds of times a second). Each kind of request has a limit in
-- Config.REMOTE_LIMITS: at most `calls` in any `seconds`. Anything over the limit is quietly
-- ignored. In Studio, it says so in the Output, so you can see it working.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Sunnyfolk").Config)

local RemoteGuard = {}

type Limit = { calls: number, seconds: number }

-- When each player last asked for each thing: recent[player][name] = { times }
local recent: { [Player]: { [string]: { number } } } = {}
local lastNote: { [Player]: number } = {} -- so Studio's notes don't flood the Output

-- Is `player` allowed to ask for `name` now? Counts the request if so. `limit` defaults to
-- Config.REMOTE_LIMITS[name].
function RemoteGuard.allow(player: Player, name: string, limit: Limit?): boolean
	if not player.Parent then
		return false -- they've left; don't start keeping track of them again
	end
	local rule = limit or Config.REMOTE_LIMITS[name]
	if not rule then
		return true
	end
	local mine = recent[player]
	if not mine then
		mine = {}
		recent[player] = mine
	end
	local times = mine[name] or {}
	mine[name] = times
	local now = os.clock()
	-- forget requests older than the window
	while times[1] and now - times[1] > rule.seconds do
		table.remove(times, 1)
	end
	if #times >= rule.calls then
		if RunService:IsStudio() and now - (lastNote[player] or 0) > 1 then
			lastNote[player] = now
			print(`RemoteGuard: ignored {player.Name}'s {name} (more than {rule.calls} in {rule.seconds}s)`)
		end
		return false
	end
	table.insert(times, now)
	return true
end

Players.PlayerRemoving:Connect(function(player)
	recent[player] = nil
	lastNote[player] = nil
end)

return RemoteGuard
