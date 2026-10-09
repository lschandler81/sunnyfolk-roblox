-- Fishing at Home Pond, Lily Pond and Puddles' pond (Config.FISHING, Config.FISHING_PONDS),
-- from the web game's fishing.js. Each player's screen (client/Fishing) shows the rod, the
-- bobber and the splash; the server decides everything that counts, with the FishAction remote:
--
--   FishAction("cast", pond)  pond is 1 to #Config.FISHING_PONDS, and you must be by it. The
--     server picks when a fish will bite: Config.FISHING.FIRST_BITE seconds until you've caught
--     your first fish, and between BITE_MIN and BITE_MAX after that. Returns (true, seconds
--     until the bite).
--   FishAction("reel")  catches the fish only while it's biting: from its bite until
--     BITE_SECONDS later (and LAG more, for the trip). Too soon or too late and it swims off,
--     with a new wait, so tapping fast catches nothing extra. The server picks which fish, from
--     the ones in that pond; one that isn't in your book yet bites more often. Returns (true,
--     fish id, coins), or (false, "soon" or "away", seconds until the next bite), or (false,
--     "a kind message").
--   FishAction("stop")  puts the rod away.
--
-- Every catch is counted in the player's Fish Book (PlayerData fishBook) and goes back in the
-- water. A fish new to the book pays Config.FISHING.NEW_COINS, so catching the same fish again
-- and again earns nothing. While someone's fishing, their Fishing attribute says where their
-- bobber is (a Vector3), so everyone's screen can draw their rod and line.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Config = require(Shared.Config)
local Analytics = require(script.Parent.Analytics)
local Goals = require(script.Parent.Goals)
local PlayerData = require(script.Parent.PlayerData)
local RemoteGuard = require(script.Parent.RemoteGuard)

local Remotes = Shared:WaitForChild("Remotes")

local F = Config.FISHING
local S = Config.STUDS
local SLACK = 6 -- studs further than the button shows, for a player who's just moved

local Fishing = {}

-- Who's fishing: which pond, when their fish bites (os.clock), and whether it's been caught.
type Line = { pond: number, biteAt: number, caught: boolean }
local lines: { [Player]: Line } = {}
local random = Random.new()

-- How far (flat, in studs) the player is from the middle of pond `i`, or nil without an animal.
local function gapTo(player: Player, i: number): number?
	local root = player.Character and player.Character.PrimaryPart
	if not root then
		return nil
	end
	local gap = root.Position - Config.FISHING_PONDS[i].centre
	return Vector3.new(gap.X, 0, gap.Z).Magnitude
end

-- Is the player close enough to fish in pond `i`?
local function near(player: Player, i: number): boolean
	local gap = gapTo(player, i)
	return gap ~= nil and gap <= (Config.FISHING_PONDS[i].r + F.REACH) * S + SLACK
end

-- Where the bobber lands: in the water, between the player and the pond's middle.
local function bobberAt(player: Player, i: number): Vector3
	local pond = Config.FISHING_PONDS[i]
	local root = (player.Character :: Model).PrimaryPart :: BasePart
	local flat = Vector3.new(root.Position.X - pond.centre.X, 0, root.Position.Z - pond.centre.Z)
	local away = if flat.Magnitude > 0.1 then flat.Unit else Vector3.zAxis
	local out = math.min(pond.r * S * (1 - F.BOBBER), math.max(flat.Magnitude - F.BOBBER_GAP, 0))
	return pond.centre + away * out + Vector3.new(0, F.WATER_Y, 0)
end

-- Seconds until the next bite: quick until they've caught their first fish.
local function nextBite(data: PlayerData.Data): number
	if next(data.fishBook.caught) == nil then
		return F.FIRST_BITE
	end
	return random:NextNumber(F.BITE_MIN, F.BITE_MAX)
end

-- Which fish bites in pond `i`: by weight, from the fish that live there, and those not in the
-- book yet more often.
local function pick(data: PlayerData.Data, i: number)
	local kind = Config.FISHING_PONDS[i].kind
	local here, total = {}, 0
	for _, fish in F.FISH do
		if fish.where == "any" or fish.where == kind then
			local weight = fish.weight * (if data.fishBook.caught[fish.id] then 1 else F.NEW_BOOST)
			table.insert(here, { fish = fish, weight = weight })
			total += weight
		end
	end
	local roll = random:NextNumber(0, total)
	for _, each in here do
		roll -= each.weight
		if roll <= 0 then
			return each.fish
		end
	end
	return here[#here].fish
end

local function stop(player: Player)
	lines[player] = nil
	if player.Parent then
		player:SetAttribute("Fishing", nil)
	end
end

local function action(player: Player, what: any, pond: any): (boolean, any, any)
	local data = PlayerData.get(player)
	if not data then
		return false, "Just a moment!"
	end
	local now = os.clock()

	if what == "cast" then
		if typeof(pond) ~= "number" or pond ~= pond or pond % 1 ~= 0 or not Config.FISHING_PONDS[pond] then
			return false, "Something went wrong. Please try again."
		end
		if not near(player, pond) then
			return false, "Walk a little closer to the water."
		end
		local seconds = nextBite(data)
		lines[player] = { pond = pond, biteAt = now + seconds, caught = false }
		player:SetAttribute("Fishing", bobberAt(player, pond))
		return true, seconds
	elseif what == "reel" then
		local line = lines[player]
		if not line or line.caught then
			return false, "Cast your line first!"
		end
		if not near(player, line.pond) then
			stop(player)
			return false, "Walk back to the water to fish."
		end
		-- too soon, or too late: it swims off, and another comes along later
		if now < line.biteAt or now > line.biteAt + F.BITE_SECONDS + F.LAG then
			local seconds = nextBite(data)
			local why = if now < line.biteAt then "soon" else "away"
			line.biteAt = now + seconds
			return false, why, seconds
		end
		local fish = pick(data, line.pond)
		local coins, balance = 0, nil
		PlayerData.update(player, function(d)
			local before = d.fishBook.caught[fish.id]
			d.fishBook.caught[fish.id] = (before or 0) + 1
			if not before then
				coins = F.NEW_COINS
				d.coins += coins
			end
			balance = d.coins
		end)
		if not balance then
			return false, "Something went wrong. Please try again."
		end
		line.caught = true
		if coins > 0 then
			Analytics.coinsEarned(player, coins, balance, `fishing:{fish.id}`)
		end
		Goals.event(player, "fish", fish.id)
		return true, fish.id, coins
	elseif what == "stop" then
		stop(player)
		return true
	end
	return false, "Something went wrong. Please try again."
end

function Fishing.start()
	Remotes.FishAction.OnServerInvoke = function(player, what, pond)
		if not RemoteGuard.allow(player, "Fish") then
			return false, "Just a moment!"
		end
		return action(player, what, pond)
	end
	-- a new animal (or none) puts the rod away; leaving forgets them
	local function watch(player: Player)
		player.CharacterRemoving:Connect(function()
			stop(player)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lines[player] = nil
	end)
end

return Fishing
