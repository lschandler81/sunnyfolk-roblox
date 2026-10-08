-- Biscuit's Cafe, at the end of the Cafe road (Config.CAFE), from the web game's cafe.
--
--   * Cafe.build() makes the place itself, once, when the town is built: a clearing with the
--     cafe (a striped awning and its sign), the counter with its four stations (a cocoa
--     machine, a cake stand, a griddle and a soup pot, each with its dish in front, so you can
--     match it by its picture), a wash-up tub for dirty plates, Chef Pepper's stove, six tables
--     with chairs and umbrellas, a menu board, planters, lamps, trees and flowers.
--   * Cafe.start() runs the shifts. There's one shift at a time, and up to MAX_HELPERS helpers
--     share it. The server picks every visitor and what they'd like, and checks every pick-up
--     and every serve (the CafeAction remote): that you're helping, close enough, carrying the
--     right thing, and that the visitor is sitting down waiting. A visitor who's eaten leaves
--     their dirty plates, and that table takes nobody new until a helper has cleared them and
--     carried them to the wash-up tub. The shift ends once every order is served and every
--     plate washed. Every helper is paid for every order served, and for finishing, up to
--     Config.CAFE.COINS_PER_HOUR an hour (kept in the save, so a new server doesn't start the
--     hour again). Nothing ever fails: there's no
--     timer, and a visitor waits until they're served.
--
-- What everyone's screens need (client/Cafe) is kept in attributes, so the server makes no
-- models per player or per visitor: on Workspace.CafeShift (Active, Served, Total, and
-- Table1 to Table6 as "food|visitor|state", where state is "come", "wait", "eat" or "dirty"),
-- and on each helper's Player (CafeHelper, and CafeCarry: the food they're carrying, or
-- "dirty" for dirty plates).
--
-- CafeAction(what, which): what is "start" (or join the shift that's on), "stop", "pick"
-- (which = a station, 1 to 4), "serve" or "clear" (which = a table, 1 to 6), or "wash".
-- Returns (true, extra) or (false, "a kind message"); a serve with the wrong food returns (false, "wrong").
-- CafeNews (server to player only): ("served", table, coins), ("joined", name),
-- ("done", coins, served), ("left").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Build = require(Shared.Build)
local CafeFood = require(Shared.CafeFood)
local Config = require(Shared.Config)
local Analytics = require(script.Parent.Parent.Analytics)
local Goals = require(script.Parent.Parent.Goals)
local PlayerData = require(script.Parent.Parent.PlayerData)
local RemoteGuard = require(script.Parent.Parent.RemoteGuard)

local Remotes = Shared:WaitForChild("Remotes")

local K = Config.CAFE
local C = Build.C
local S = Config.STUDS
local DECOR = Build.DECOR

local Cafe = {}

---------------------------------------------------------------- the place

local at = Config.cafeAt

-- A striped market umbrella over a table, like the web game's: a pole, eight tilted panels in
-- two colours and a little ball on top. All walk-through.
local function umbrella(base: CFrame, color: Color3)
	Build.cylinder(0.05 * S, 2.4 * S, base * CFrame.new(0, 1.2 * S, 0), C.cream, DECOR)
	for i = 0, 7 do
		local a = (i + 0.5) / 8 * math.pi * 2
		local panel = base * CFrame.new(0, 2.4 * S, 0) * CFrame.Angles(0, a, 0) * CFrame.new(0, -0.22 * S, 0.68 * S) * CFrame.Angles(0.34, 0, 0)
		Build.block(Vector3.new(1.12, 0.06, 1.45) * S, panel, if i % 2 == 0 then color else C.cream, DECOR)
	end
	Build.ball(0.16 * S, base * CFrame.new(0, 2.68 * S, 0), color, DECOR)
end

-- The four stations on the counter, left to right (`base` is the counter top's middle).
local function stations(base: CFrame)
	local function u(i: number, x: number, y: number, z: number): CFrame
		return base * CFrame.new((K.STATION_X[i] + x) * S, y * S, (z - 0.1) * S)
	end
	-- the cocoa machine, with its spout and a cup under it
	Build.block(Vector3.new(0.9, 1.0, 0.7) * S, u(1, 0, 0.5, 0), C.teal)
	Build.block(Vector3.new(0.95, 0.12, 0.75) * S, u(1, 0, 1.04, 0), C.tealDeep, DECOR)
	Build.cylinder(0.06 * S, 0.2 * S, u(1, 0, 0.55, 0.38) * CFrame.Angles(math.pi / 2, 0, 0), Color3.fromHex("#8aa0a8"), DECOR)
	Build.cylinder(0.14 * S, 0.2 * S, u(1, 0, 0.12, 0.38), C.cream, DECOR)
	-- the cake stand, with a cake under a glass dome
	Build.cylinder(0.1 * S, 0.3 * S, u(2, 0, 0.15, 0), C.white, DECOR)
	Build.cylinder(0.5 * S, 0.05 * S, u(2, 0, 0.32, 0), C.white, DECOR)
	Build.cylinder(0.38 * S, 0.32 * S, u(2, 0, 0.5, 0), Color3.fromHex("#f7e2b0"), DECOR)
	Build.cylinder(0.4 * S, 0.06 * S, u(2, 0, 0.68, 0), Color3.fromHex("#fbd85a"), DECOR)
	Build.ball(0.16 * S, u(2, 0, 0.76, 0), C.yuzu, DECOR)
	Build.blob(Vector3.new(1.0, 0.9, 1.0) * S, u(2, 0, 0.55, 0), Color3.fromHex("#e8f6f8"),
		{ CanCollide = false, Transparency = 0.6, Material = Enum.Material.Glass, CastShadow = false })
	-- the griddle, with pancakes on it
	Build.block(Vector3.new(1.1, 0.12, 0.8) * S, u(3, 0, 0.06, 0), Color3.fromHex("#3b4448"))
	for i = 0, 2 do
		Build.cylinder(0.25 * S, 0.07 * S, u(3, 0, 0.15 + i * 0.075, 0), Color3.fromHex("#e2a860"), DECOR)
	end
	Build.cylinder(0.18 * S, 0.02 * S, u(3, 0, 0.37, 0), Color3.fromHex("#fbd85a"), DECOR)
	-- the soup pot on a little stove, with two handles
	Build.block(Vector3.new(1.0, 0.18, 0.8) * S, u(4, 0, 0.09, 0), Color3.fromHex("#4a4f52"))
	Build.cylinder(0.38 * S, 0.5 * S, u(4, 0, 0.43, 0), Color3.fromHex("#b8c4c8"), DECOR)
	Build.cylinder(0.33 * S, 0.02 * S, u(4, 0, 0.67, 0), Color3.fromHex("#f0a050"), DECOR)
	for _, side in { -1, 1 } do
		Build.block(Vector3.new(0.1, 0.08, 0.16) * S, u(4, side * 0.42, 0.55, 0), Color3.fromHex("#8a9498"), DECOR)
	end
end

-- Builds the Cafe. Call it while the town is being built (it goes in the town's folder).
function Cafe.build()
	-- a lighter clearing, a path in from the road, and a terrace in front of the counter
	local ground = Build.cylinder((K.radius - 1) * S, 0.06, at(0, 0) * CFrame.new(0, 0.03, 0), Color3.fromHex("#c2e0a2"), DECOR)
	local folder = ground.Parent
	local inFrom = K.COUNTER_Z + 2
	Build.block(Vector3.new(3 * S, 0.1, (K.radius - inFrom) * S), at(0, (K.radius + inFrom) / 2) * CFrame.new(0, 0.07, 0), C.path, DECOR)
	Build.block(Vector3.new(15 * S, 0.1, 3.4 * S), at(0, K.COUNTER_Z + 1.6) * CFrame.new(0, 0.07, 0), C.path, DECOR)

	-- the cafe, its door facing the way in
	Build.house(at(0, -14), {
		w = 10,
		d = 5,
		h = 3.4,
		wall = C.cream,
		roof = C.teal,
		awning = C.coral,
		door = C.coral,
		label = "Biscuit's Cafe",
		sign = C.teal,
		yard = false,
	})

	-- the counter, with coral and cream stripes along its front and the stations on top
	local counter = at(0, K.COUNTER_Z)
	Build.block(Vector3.new(12.4, 1.05, 1.1) * S, counter * CFrame.new(0, 0.52 * S, 0), Color3.fromHex("#f3dcae"))
	Build.block(Vector3.new(12.8, 0.14, 1.4) * S, counter * CFrame.new(0, 1.1 * S, 0), C.wood)
	for i = 0, 5 do
		Build.block(Vector3.new(1.9, 0.6, 0.04) * S, counter * CFrame.new((-5.2 + i * 2.08) * S, 0.55 * S, 0.57 * S),
			if i % 2 == 1 then C.coral else C.cream, DECOR)
	end
	local top = counter * CFrame.new(0, 1.17 * S, 0)
	stations(top)
	-- each station's dish at the front of the counter, a little bigger than real, so you can see
	-- which station makes what
	for i, id in K.STATIONS do
		local dish = CafeFood.model(id, 1.6)
		dish:PivotTo(top * CFrame.new(K.STATION_X[i] * S, 0, 0.45 * S))
		dish.Parent = folder
	end

	-- the wash-up tub, just past the counter's left end: a stand, a tub of bubbly water and a tap
	local wash = at(K.WASH_X, K.COUNTER_Z)
	Build.block(Vector3.new(1.4, 1.05, 1.1) * S, wash * CFrame.new(0, 0.52 * S, 0), C.skyBlue)
	Build.block(Vector3.new(1.5, 0.12, 1.2) * S, wash * CFrame.new(0, 1.1 * S, 0), C.wood, DECOR)
	local tub = CafeFood.tub()
	tub:PivotTo(wash * CFrame.new(0, 1.16 * S, 0))
	tub.Parent = folder

	-- Chef Pepper's kitchen corner: a big stove with two pots on it
	local stove = at(8.2, -10.5, -math.pi / 2)
	Build.block(Vector3.new(2.4, 1.0, 1.1) * S, stove * CFrame.new(0, 0.5 * S, 0), Color3.fromHex("#4a4f52"))
	Build.block(Vector3.new(2.5, 0.1, 1.2) * S, stove * CFrame.new(0, 1.04 * S, 0), Color3.fromHex("#6a7074"), DECOR)
	for _, x in { -0.6, 0.6 } do
		Build.cylinder(0.33 * S, 0.45 * S, stove * CFrame.new(x * S, 1.3 * S, 0), if x < 0 then C.coral else Color3.fromHex("#b8c4c8"), DECOR)
	end

	-- the tables: each with a chair on its outer side (facing the table), and most with an umbrella
	for i, spot in K.TABLES do
		local tx, tz = spot[1], spot[2]
		local side = if tx > 0 then 1 else -1
		local tableAt = Config.cafeTable(i)
		Build.cylinder(0.95 * S, 0.1 * S, tableAt * CFrame.new(0, 0.95 * S, 0), C.white)
		Build.cylinder(0.12 * S, 0.9 * S, tableAt * CFrame.new(0, 0.45 * S, 0), C.tealDeep)
		Build.cylinder(0.48 * S, 0.08 * S, tableAt * CFrame.new(0, 0.04 * S, 0), C.tealDeep, DECOR)
		local chair = at(tx + side * K.CHAIR, tz, -side * math.pi / 2)
		Build.block(Vector3.new(0.8, 0.1, 0.75) * S, chair * CFrame.new(0, 0.48 * S, 0), C.wood)
		Build.block(Vector3.new(0.8, 0.75, 0.1) * S, chair * CFrame.new(0, 0.85 * S, -0.36 * S), C.wood)
		for _, leg in { { -0.33, -0.3 }, { 0.33, -0.3 }, { -0.33, 0.3 }, { 0.33, 0.3 } } do
			Build.block(Vector3.new(0.08, 0.48, 0.08) * S, chair * CFrame.new(leg[1] * S, 0.24 * S, leg[2] * S), C.tealDeep, DECOR)
		end
		if (i - 1) % 3 ~= 2 then
			umbrella(tableAt * CFrame.new(0, 0.95 * S, 0), if (i - 1) % 2 == 1 then C.coral else C.teal)
		end
	end

	-- the menu: an A-frame chalkboard by the way in
	local board = at(3.2, 16, 0.3)
	local tall, splay = 1.25, 0.38
	local tilt = math.atan2(splay, tall)
	local length = math.sqrt(tall * tall + splay * splay)
	for _, face in { 0, math.pi } do
		local side = board * CFrame.Angles(0, face, 0)
		-- (leaning in at the top, so the two boards meet like an A)
		local slate = Build.block(Vector3.new(0.94, length, 0.05) * S, side * CFrame.new(0, tall / 2 * S, splay / 2 * S) * CFrame.Angles(-tilt, 0, 0),
			Color3.fromHex("#34403e"))
		Build.label(slate, "Menu", Color3.fromHex("#f6d36a"), nil, Enum.NormalId.Back)
		Build.block(Vector3.new(0.94, 0.06, 0.1) * S, side * CFrame.new(0, 0.03 * S, splay * S), C.woodDark, DECOR)
	end
	Build.block(Vector3.new(1.0, 0.08, 0.12) * S, board * CFrame.new(0, (tall + 0.02) * S, 0), C.woodDark, DECOR)

	-- planters, lamps and trees round the edge
	for _, spot in { { -12, -6 }, { 12, -6 }, { -13, 4 }, { 13, 4 } } do
		Build.planter(at(spot[1], spot[2], math.atan2(-spot[1], -spot[2])), 2.4, 1)
	end
	for _, spot in { { -3, 14 }, { -11, -11 }, { 11, -11 } } do
		Build.lamp(at(spot[1], spot[2]))
	end
	for _, spot in { { -17, -9, 1.1 }, { 17, -9, 1.0 }, { -18, 8, 1.0 }, { 17.5, 9, 1.2 }, { -9, 19, 0.9 } } do
		Build.tree(at(spot[1], spot[2]), spot[3], spot[1] > 0)
	end
	-- flowers round the edge, leaving the way in clear (and not behind the cafe)
	for i = 0, 69 do
		local a = i / 70 * math.pi * 2
		local r = K.radius - 2.6 + math.sin(i * 5) * 0.6
		local x, z = math.sin(a) * r, math.cos(a) * r
		local wayIn = z > K.radius - 8 and math.abs(x) < 4.5
		local behind = math.abs(x) < 7 and z < -12
		if not (wayIn or behind) then
			Build.flower(at(x, z), Build.FLOWERS[i % 4 + 1], (0.3 + (i % 3) * 0.08) * S)
		end
	end
end

---------------------------------------------------------------- the shift

type Order = { food: string, visitor: number, state: string, since: number }
type Shift = {
	helpers: { Player },
	tables: { [number]: Order },
	served: number,
	spawned: number,
	nextAt: number,
	earned: { [Player]: number }, -- coins each helper has had from this shift
}

local shift: Shift? = nil
local state: Folder -- Workspace.CafeShift, which everyone's screens read
local random = Random.new()

-- Puts the shift where everyone's screens can see it.
local function show()
	local s = shift
	state:SetAttribute("Active", s ~= nil)
	state:SetAttribute("Served", if s then s.served else 0)
	state:SetAttribute("Total", K.ORDERS)
	for i = 1, #K.TABLES do
		local order = s and s.tables[i]
		state:SetAttribute(`Table{i}`, if order then `{order.food}|{order.visitor}|{order.state}` else nil)
	end
end

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- How far (studs, along the ground) the player is from `spot`, or infinity.
local function distance(player: Player, spot: Vector3): number
	local root = player.Character and player.Character.PrimaryPart
	return if root then flat(root.Position, spot) else math.huge
end

local function inCafe(player: Player, extra: number): boolean
	return distance(player, Config.cafeFrame().Position) <= (K.radius + extra) * S
end

-- Gives `coins` from the cafe, up to what's left of this hour's cap. Returns how many it gave.
local function pay(player: Player, coins: number, source: string): number
	local given, balance = 0, 0
	PlayerData.update(player, function(d)
		local now = os.time()
		if now - d.cafe.hourStart >= K.HOUR then
			d.cafe.hourStart = now
			d.cafe.hourCoins = 0
		end
		given = math.clamp(K.COINS_PER_HOUR - d.cafe.hourCoins, 0, coins)
		d.cafe.hourCoins += given
		d.coins += given
		balance = d.coins
	end)
	if given > 0 then
		Analytics.coinsEarned(player, given, balance, source)
	end
	return given
end

-- Clears a player's helping (what they carry, and being a helper).
local function clear(player: Player)
	player:SetAttribute("CafeHelper", nil)
	player:SetAttribute("CafeCarry", nil)
end

local function stopShift()
	local s = shift
	if not s then
		return
	end
	shift = nil
	for _, helper in s.helpers do
		clear(helper)
	end
	show()
end

-- A helper leaves the shift (they keep what they've earned). The shift stops when nobody's left.
local function leave(player: Player, tell: boolean)
	local s = shift
	local index = s and table.find(s.helpers, player)
	if not (s and index) then
		return
	end
	table.remove(s.helpers, index)
	s.earned[player] = nil
	clear(player)
	if tell and player.Parent then
		Remotes.CafeNews:FireClient(player, "left")
	end
	if #s.helpers == 0 then
		stopShift()
	end
end

-- Is the shift done: every order served, every table cleared, and every plate washed?
local function allDone(s: Shift): boolean
	if s.served < K.ORDERS then
		return false
	end
	for i = 1, #K.TABLES do
		if s.tables[i] then
			return false
		end
	end
	for _, helper in s.helpers do
		if helper:GetAttribute("CafeCarry") == "dirty" then
			return false
		end
	end
	return true
end

-- The shift is done: everyone helping gets the finishing coins, the shift is counted in their
-- save (and their goals), and it's over.
local function finish(s: Shift)
	-- (over first, so nothing below can leave it stuck at the last order)
	local helpers = table.clone(s.helpers)
	stopShift()
	for _, helper in helpers do
		local coins = (s.earned[helper] or 0) + pay(helper, K.FINISH_COINS, "cafe:shift")
		PlayerData.update(helper, function(d)
			d.cafe.shifts += 1
		end)
		Goals.event(helper, "cafe")
		Analytics.cafeShift(helper, s.served, #helpers)
		Remotes.CafeNews:FireClient(helper, "done", coins, s.served)
	end
end

-- Every half a second: helpers who've wandered off leave, visitors sit down and finish eating,
-- and a new one comes in when there's room.
local function tick()
	local s = shift
	if not s then
		return
	end
	for _, helper in table.clone(s.helpers) do
		if not helper.Parent or not inCafe(helper, K.LEAVE) then
			leave(helper, true)
		end
	end
	if shift ~= s then
		return -- everyone left
	end
	local now = os.clock()
	local waiting, free = 0, {}
	for i = 1, #K.TABLES do
		local order = s.tables[i]
		if order and order.state == "come" and now - order.since >= K.ARRIVE_SECONDS then
			order.state, order.since = "wait", now
		elseif order and order.state == "eat" and now - order.since >= K.EAT_SECONDS then
			-- they've gone, leaving their dirty plates
			order.state, order.since = "dirty", now
		end
		if not order then
			table.insert(free, i)
		elseif order.state == "come" or order.state == "wait" then
			waiting += 1
		end
	end
	if s.spawned < K.ORDERS and waiting < Config.cafeWaiting(#s.helpers) and now >= s.nextAt and #free > 0 then
		s.spawned += 1
		s.nextAt = now + K.NEXT_SECONDS
		s.tables[free[random:NextInteger(1, #free)]] = {
			food = K.STATIONS[random:NextInteger(1, #K.STATIONS)],
			visitor = random:NextInteger(1, 1000000), -- picks how the visitor looks (client/Cafe)
			state = "come",
			since = now,
		}
	end
	show()
	-- (someone carrying the last plates may have left)
	if allDone(s) then
		finish(s)
	end
end

-- A whole number from `low` to `high`, or nil.
local function whole(value: any, low: number, high: number): number?
	if typeof(value) ~= "number" or value ~= value or value % 1 ~= 0 or value < low or value > high then
		return nil
	end
	return value
end

local function action(player: Player, what: any, which: any): (boolean, any)
	local data = PlayerData.get(player)
	if not data then
		return false, "Just a moment!"
	end
	if data.sun < K.SUN then
		return false, `The Cafe opens when you have {K.SUN} sunshine.`
	end
	local s = shift
	local helping = s ~= nil and table.find(s.helpers, player) ~= nil

	if what == "start" then
		if helping then
			return true, "helping"
		end
		if not inCafe(player, 0) then
			return false, "Walk a little closer to Biscuit."
		end
		if s then
			if #s.helpers >= K.MAX_HELPERS then
				return false, "Biscuit has lots of helpers just now. Try again soon!"
			end
			for _, helper in s.helpers do
				Remotes.CafeNews:FireClient(helper, "joined", player.DisplayName)
			end
			table.insert(s.helpers, player)
			s.earned[player] = 0
			player:SetAttribute("CafeHelper", true)
			show()
			return true, "joined"
		end
		shift = {
			helpers = { player },
			tables = {},
			served = 0,
			spawned = 0,
			nextAt = os.clock() + K.FIRST_SECONDS,
			earned = { [player] = 0 },
		}
		player:SetAttribute("CafeHelper", true)
		show()
		return true, "started"
	elseif what == "stop" then
		leave(player, false)
		return true, nil
	end

	if not (s and helping) then
		return false, "Ask Biscuit for a shift first."
	end
	if what == "pick" then
		local i = whole(which, 1, #K.STATIONS)
		if not i then
			return false, "Something went wrong. Please try again."
		end
		if distance(player, Config.cafeStation(i).Position) > K.PICK_REACH then
			return false, "Walk a little closer to the counter."
		end
		if player:GetAttribute("CafeCarry") == "dirty" then
			return false, "Wash up the dirty plates first!"
		end
		player:SetAttribute("CafeCarry", K.STATIONS[i])
		return true, K.STATIONS[i]
	elseif what == "serve" then
		local i = whole(which, 1, #K.TABLES)
		if not i then
			return false, "Something went wrong. Please try again."
		end
		local order = s.tables[i]
		if not (order and order.state == "wait") then
			return false, "Nobody's waiting there just now."
		end
		if distance(player, Config.cafeTable(i).Position) > K.SERVE_REACH then
			return false, "Walk a little closer to the table."
		end
		if player:GetAttribute("CafeCarry") ~= order.food then
			return false, "wrong"
		end
		player:SetAttribute("CafeCarry", nil)
		order.state, order.since = "eat", os.clock()
		s.served += 1
		-- everyone helping gets paid for it, whoever served it
		for _, helper in s.helpers do
			local given = pay(helper, K.ORDER_COINS, "cafe:order")
			s.earned[helper] = (s.earned[helper] or 0) + given
			Remotes.CafeNews:FireClient(helper, "served", i, given)
		end
		show()
		return true, nil
	elseif what == "clear" then
		local i = whole(which, 1, #K.TABLES)
		if not i then
			return false, "Something went wrong. Please try again."
		end
		local order = s.tables[i]
		if not (order and order.state == "dirty") then
			return false, "There's nothing to clear there."
		end
		if distance(player, Config.cafeTable(i).Position) > K.SERVE_REACH then
			return false, "Walk a little closer to the table."
		end
		-- (only with empty paws, so nobody loses an order they're carrying)
		if player:GetAttribute("CafeCarry") ~= nil then
			return false, "Your paws are full! Take that first."
		end
		s.tables[i] = nil
		player:SetAttribute("CafeCarry", "dirty")
		show()
		return true, nil
	elseif what == "wash" then
		if player:GetAttribute("CafeCarry") ~= "dirty" then
			return false, "There's nothing to wash up."
		end
		if distance(player, Config.cafeWash().Position) > K.PICK_REACH then
			return false, "Walk a little closer to the wash-up tub."
		end
		player:SetAttribute("CafeCarry", nil)
		if allDone(s) then
			finish(s)
		end
		return true, nil
	end
	return false, "Something went wrong. Please try again."
end

function Cafe.start()
	state = Instance.new("Folder")
	state.Name = "CafeShift"
	state.Parent = Workspace
	show()

	-- CafeNews only goes from the server to players; anything a player sends on it is ignored.
	Remotes.CafeNews.OnServerEvent:Connect(function() end)
	Remotes.CafeAction.OnServerInvoke = function(player, what, which)
		if not RemoteGuard.allow(player, "Cafe") then
			return false, "Just a moment!"
		end
		return action(player, what, which)
	end
	Players.PlayerRemoving:Connect(function(player)
		leave(player, false)
	end)
	task.spawn(function()
		while true do
			task.wait(K.CHECK_SECONDS)
			tick()
		end
	end)
end

return Cafe
