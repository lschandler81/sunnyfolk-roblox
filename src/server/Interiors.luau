-- The inside of players' houses (Config.ROOM, shared/Furniture): a living room, a kitchen and
-- a bedroom upstairs, to decorate with furniture bought with coins. Pressing "Go inside" at
-- your own front door (client/Homes) builds your house in a spot of its own, far from town,
-- and takes you in; "Go outside" takes you back to your door and takes the house down. Only
-- you can be in your house: anyone else found in it is sent back to the fountain. Your pet
-- comes in with you by itself (client/Pets keeps it beside you). Only you ever see your house:
-- it's built only while you're in it, and so far from everything that nobody else's screen
-- loads it.
--
-- Your screen (client/Decorator) asks for every change with the RoomAction remote, and the
-- server checks it all: the price and your coins, that you own the piece, that it fits
-- (Furniture.fits), and the number of pieces in each room. RoomAction(what, ...):
--   "enter"                            go in (you must be at your own front door)
--   "leave"                            go back out
--   "buy", kind, id, room              buy a piece ("piece") to place, or a wallpaper ("wall")
--                                      or floor ("floor"), which goes straight on that room
--   "place", room, spot                put out a piece you own that isn't placed yet
--   "move", room, index, spot          move a placed piece (its number in that room's list)
--   "putAway", room, index             put a placed piece away (you still own it)
--   "style", room, kind, id            use a wallpaper or floor you own in a room
-- Each returns true, or false and a kind message. What's in your house is shown to your
-- screen by your Interior attribute (server/PlayerData), and where your house is by your
-- Indoors attribute (the CFrame of its middle) while you're inside.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Builder = require(Shared.CharacterBuilder)
local Config = require(Shared.Config)
local Furniture = require(Shared.Furniture)
local Analytics = require(script.Parent.Analytics)
local Avatars = require(script.Parent.Avatars)
local Homes = require(script.Parent.Homes)
local PlayerData = require(script.Parent.PlayerData)
local RemoteGuard = require(script.Parent.RemoteGuard)

local Remotes = Shared:WaitForChild("Remotes")

local R = Config.ROOM
local SLOTS = Config.HOME.plots -- one house spot for each player on a server
local DOOR_WAIT = 1 -- seconds between going in and out
local STREAM_WAIT = 5 -- seconds to wait at most for Roblox to load where you're going

local Interiors = {}

-- Who's in their house: which spot it's in, where its middle is, and its parts (each room's
-- shell and its furniture).
type Visit = {
	slot: number,
	at: CFrame,
	model: Model,
	shells: { [string]: Model },
	pieces: { [string]: Folder },
}
local visits: { [Player]: Visit } = {}
local moving: { [Player]: boolean } = {} -- going in or out right now
local closing: { [number]: boolean } = {} -- house spots whose house is still being taken down
local lastDoor: { [Player]: number } = {}
local folder: Folder

local SORRY = "Something went wrong. Please try again."

-- The middle of house spot `slot`, in a row far from town.
local function slotFrame(slot: number): CFrame
	return CFrame.new(R.ORIGIN + Vector3.new((slot - (SLOTS + 1) / 2) * R.GAP, 0, 0))
end

local function freeSlot(): number?
	local taken = table.clone(closing)
	for _, visit in visits do
		taken[visit.slot] = true
	end
	for slot = 1, SLOTS do
		if not taken[slot] then
			return slot
		end
	end
	return nil
end

-- (Re)builds a room's walls and floor, with its wallpaper and floor.
local function buildShell(visit: Visit, room: Furniture.RoomDef, state: Furniture.Room)
	local old = visit.shells[room.id]
	if old then
		old:Destroy()
	end
	local shell = Furniture.buildRoom(room, state, Furniture.roomFrame(visit.at, room))
	shell.Parent = visit.model:FindFirstChild(room.id)
	visit.shells[room.id] = shell
end

-- (Re)builds a room's furniture. Each piece knows its room and its number in the room's list
-- (its Room and Index attributes), so your screen can tell the server which one you picked up.
local function buildPieces(visit: Visit, room: Furniture.RoomDef, state: Furniture.Room)
	local pieces = visit.pieces[room.id]
	pieces:ClearAllChildren()
	local roomAt = Furniture.roomFrame(visit.at, room)
	for index, spot in state.items do
		local model = Furniture.build(spot.id, Furniture.spotFrame(roomAt, room, spot))
		model:SetAttribute("Room", room.id)
		model:SetAttribute("Index", index)
		model.Parent = pieces
	end
end

-- Builds `player`'s whole house in spot `slot`.
local function buildHouse(player: Player, slot: number, interior: Furniture.Interior): Visit
	local at = slotFrame(slot)
	local model = Instance.new("Model")
	model.Name = tostring(player.UserId)
	-- always loaded on the owner's screen (and, being so far away, never on anyone else's)
	model.ModelStreamingMode = Enum.ModelStreamingMode.PersistentPerPlayer
	local visit: Visit = { slot = slot, at = at, model = model, shells = {}, pieces = {} }
	Furniture.buildLawn(at).Parent = model
	for _, room in R.ROOMS do
		local roomFolder = Instance.new("Folder")
		roomFolder.Name = room.id
		roomFolder.Parent = model
		local pieces = Instance.new("Folder")
		pieces.Name = "Pieces"
		pieces.Parent = roomFolder
		visit.pieces[room.id] = pieces
		local state = interior.rooms[room.id]
		buildShell(visit, room :: any, state)
		buildPieces(visit, room :: any, state)
	end
	model.Parent = folder
	model:AddPersistentPlayer(player)
	return visit
end

-- Moves a player's animal so its feet are at `feet`, once Roblox has loaded what's there.
local function moveTo(player: Player, feet: CFrame)
	pcall(function()
		player:RequestStreamAroundAsync(feet.Position, STREAM_WAIT)
	end)
	local character = player.Character
	if character and player.Parent then
		character:PivotTo(feet * CFrame.new(0, Builder.ROOT_HEIGHT, 0))
	end
end

-- Takes a player's house down. With `goOut`, they're taken back to their front door first.
local function leave(player: Player, goOut: boolean)
	local visit = visits[player]
	if not visit then
		return
	end
	visits[player] = nil
	if goOut then
		-- (the spot stays taken until its house is gone, so nobody else's is built on it)
		closing[visit.slot] = true
		moving[player] = true
		pcall(moveTo, player, Homes.doorOf(player) or Avatars.spawnPoint)
		moving[player] = nil
		closing[visit.slot] = nil
	end
	visit.model:Destroy()
	if player.Parent then
		player:SetAttribute("Indoors", nil)
	end
end

local function enter(player: Player): (boolean, string?)
	if visits[player] then
		return true
	end
	local data = PlayerData.get(player)
	if not (data and data.home) then
		return false, "Make a home first!"
	end
	local door = Homes.doorOf(player)
	local root = player.Character and player.Character.PrimaryPart
	if not (door and root) then
		return false, SORRY
	end
	if (root.Position - door.Position).Magnitude > R.DOOR_REACH then
		return false, "Walk up to your front door."
	end
	if player:GetAttribute("CafeHelper") then
		return false, "Finish your cafe shift first!"
	end
	local slot = freeSlot()
	if not slot then
		return false, SORRY
	end
	local built, visit = pcall(buildHouse, player, slot, data.interior)
	if not built then
		warn(`Sunnyfolk: couldn't build {player.Name}'s house: {visit}`)
		return false, SORRY
	end
	visits[player] = visit
	moving[player] = true
	pcall(moveTo, player, Furniture.entrance(visit.at))
	moving[player] = nil
	if visits[player] ~= visit then
		return false, SORRY -- (they left the game while it loaded)
	end
	player:SetAttribute("Indoors", visit.at)
	return true
end

-- Changes a player's Interior with `change(interior)`, which returns true if it changed it, or
-- false and why not. Everything is checked inside, so nothing can change in between.
local function change(player: Player, edit: (PlayerData.Data) -> (boolean, string?)): (boolean, string?)
	local ok, why = false, SORRY
	PlayerData.update(player, function(data)
		ok, why = edit(data)
	end)
	return ok, if ok then nil else why
end

local function buy(player: Player, visit: Visit, kind: any, id: any, roomId: any): (boolean, string?)
	if kind == "piece" then
		local piece = Furniture.piece(id)
		if not piece then
			return false, SORRY
		end
		local balance = 0
		local ok, why = change(player, function(data)
			local interior = data.interior
			if Furniture.free(interior, piece.id) > 0 then
				return false, "You've got one ready to place!"
			end
			if Furniture.owned(interior) >= R.MAX_OWNED then
				return false, "Your house is full of lovely things!"
			end
			if data.coins < piece.price then
				return false, `You need {piece.price - data.coins} more coins.`
			end
			data.coins -= piece.price
			interior.have[piece.id] = (interior.have[piece.id] or 0) + 1
			balance = data.coins
			return true
		end)
		if ok then
			Analytics.coinsSpent(player, piece.price, balance, `furniture:{piece.id}`)
		end
		return ok, why
	end
	-- a wallpaper or floor, put straight on the room you're decorating
	local style = Furniture.style(kind, id)
	local room = Furniture.room(roomId)
	if not (style and room) then
		return false, SORRY
	end
	local balance = 0
	local ok, why = change(player, function(data)
		local interior = data.interior
		if Furniture.hasStyle(interior, kind, style.id) then
			return false, "You've got that one already!"
		end
		if data.coins < style.price then
			return false, `You need {style.price - data.coins} more coins.`
		end
		data.coins -= style.price
		table.insert(interior.styles, style.id)
		;(interior.rooms[room.id] :: any)[kind] = style.id
		balance = data.coins
		return true
	end)
	if ok then
		Analytics.coinsSpent(player, style.price, balance, `{if kind == "wall" then "wallpaper" else "floor"}:{style.id}`)
		local data = PlayerData.get(player)
		if data then
			buildShell(visit, room, data.interior.rooms[room.id])
		end
	end
	return ok, why
end

-- Changes the furniture in one room with `edit(interior, items)`, then rebuilds that room's
-- furniture.
local function arrange(player: Player, visit: Visit, roomId: any, edit: (Furniture.Interior, { Furniture.Spot }) -> (boolean, string?)): (boolean, string?)
	local room = Furniture.room(roomId)
	if not room then
		return false, SORRY
	end
	local ok, why = change(player, function(data)
		return edit(data.interior, data.interior.rooms[room.id].items)
	end)
	if ok then
		local data = PlayerData.get(player)
		if data then
			buildPieces(visit, room, data.interior.rooms[room.id])
		end
	end
	return ok, why
end

local NO_ROOM = "There's no room there. Try somewhere else!"

local function action(player: Player, what: any, a: any, b: any, c: any): (boolean, string?)
	if what == "enter" or what == "leave" then
		if moving[player] or os.clock() - (lastDoor[player] or 0) < DOOR_WAIT then
			return false, "Just a moment!"
		end
		lastDoor[player] = os.clock()
		if what == "enter" then
			return enter(player)
		end
		leave(player, true)
		return true
	end

	-- everything else is decorating: only inside your own house
	local visit = visits[player]
	if not visit or moving[player] then
		return false, "Go inside your house to decorate."
	end
	if what == "buy" then
		return buy(player, visit, a, b, c)
	elseif what == "place" then
		local spot = Furniture.check(b)
		local room = Furniture.room(a)
		if not (spot and room) then
			return false, SORRY
		end
		return arrange(player, visit, a, function(interior, items)
			if Furniture.free(interior, spot.id) <= 0 then
				return false, SORRY
			end
			if #items >= R.MAX_PIECES then
				return false, "This room is full! Put something away first."
			end
			if not Furniture.fits(room, items, spot) then
				return false, NO_ROOM
			end
			table.insert(items, spot)
			return true
		end)
	elseif what == "move" then
		local spot = Furniture.check(c)
		local room = Furniture.room(a)
		if not (spot and room and typeof(b) == "number") then
			return false, SORRY
		end
		return arrange(player, visit, a, function(_, items)
			local old = items[b]
			if not old or old.id ~= spot.id then
				return false, SORRY
			end
			if not Furniture.fits(room, items, spot, b) then
				return false, NO_ROOM
			end
			items[b] = spot
			return true
		end)
	elseif what == "putAway" then
		if typeof(b) ~= "number" then
			return false, SORRY
		end
		return arrange(player, visit, a, function(_, items)
			if not items[b] then
				return false, SORRY
			end
			table.remove(items, b)
			return true
		end)
	elseif what == "style" then
		local room = Furniture.room(a)
		local style = Furniture.style(b, c)
		if not (room and style) then
			return false, SORRY
		end
		local ok, why = change(player, function(data)
			if not Furniture.hasStyle(data.interior, b, style.id) then
				return false, SORRY
			end
			;(data.interior.rooms[room.id] :: any)[b] = style.id
			return true
		end)
		local data = PlayerData.get(player)
		if ok and data then
			buildShell(visit, room, data.interior.rooms[room.id])
		end
		return ok, why
	end
	return false, SORRY
end

-- Is `root` on the lawn of the house at `at`?
local function inHouse(root: BasePart, at: CFrame): boolean
	local gap = root.Position - at.Position
	return Vector3.new(gap.X, 0, gap.Z).Magnitude <= R.FAR and gap.Y > -30
end

function Interiors.start()
	folder = Instance.new("Folder")
	folder.Name = "Houses"
	folder.Parent = Workspace

	Remotes.RoomAction.OnServerInvoke = function(player, what, a, b, c)
		if not RemoteGuard.allow(player, "Room") then
			return false, "Just a moment!"
		end
		if not PlayerData.get(player) then
			return false, "Just a moment!"
		end
		return action(player, what, a, b, c)
	end

	-- Every few seconds: a house whose owner has gone (they fell, or their animal went back to
	-- the fountain) is taken down, and anyone else in someone's house is sent to the fountain.
	task.spawn(function()
		while true do
			task.wait(R.CHECK_SECONDS)
			for player, visit in visits do
				local root = player.Character and player.Character.PrimaryPart
				if not moving[player] and not (root and inHouse(root, visit.at)) then
					leave(player, false)
				end
			end
			for _, player in Players:GetPlayers() do
				local root = player.Character and player.Character.PrimaryPart
				if root and not visits[player] and not moving[player] then
					for _, visit in visits do
						if inHouse(root, visit.at) then
							Avatars.spawn(player, true)
							break
						end
					end
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		leave(player, false)
		moving[player] = nil
		lastDoor[player] = nil
	end)
end

return Interiors
