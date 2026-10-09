-- Inside your house, on your screen (Config.ROOM, shared/Furniture, server/Interiors): going
-- in with the "Go inside" button at your front door (client/Homes) and out again with "Go
-- outside" by the living room's door, with the screen fading out and in; and decorating.
-- While you walk round inside, any wall between you and the camera fades to see-through, like
-- a dollhouse (Config.ROOM.CUTAWAY), so the tall walls never fill the screen; and while you're
-- downstairs, the bedroom above is hidden, so its floor never does either.
--
-- "Decorate" (it follows you round the house, so it's there in every room) opens the
-- decorating screen. The camera looks down into the room you're in, from the front, and a
-- card on the right shows:
--   * the rooms (Living room, Kitchen, Bedroom): pick one to look at it
--   * Furniture: a picture of each piece, with its price, or how many you have ready to place
--   * Walls & floor: the wallpapers and floors, for the room you're looking at
-- Picking a piece you have ready (or buying one) puts it in your paws: it floats over the room
-- on a green patch, coral where it won't fit. Tap the floor (or a wall, for a picture) to move
-- it there, and tap it again to put it down; or use Turn, Put away and Place it. Tap a piece
-- already in the room to pick it up and move it.
--
-- The round turn buttons (bottom left; L2 and R2 on a controller, Q and E on a keyboard) take
-- the camera round the room a quarter at a time, so you can see every wall: the walls on the
-- camera's side fade to see-through. Things you haven't enough coins for are greyed out.
--
-- With a controller: the ring moves round the card (A picks, B closes). Holding a piece, the
-- stick or D-pad moves it a tile at a time, A places it, X turns it, Y puts it away and B puts
-- it back. The shoulder buttons pick out the pieces already in the room, one at a time, and A
-- lifts the one picked out. On a keyboard, the arrow keys move a piece, R turns it and Enter
-- places it.
--
-- The server checks everything (the price, what you own, what fits); this screen only asks.

local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Builder = require(Shared.CharacterBuilder)
local Config = require(Shared.Config)
local Furniture = require(Shared.Furniture)
local Controls = require(script.Parent.Controls)
local Hud = require(script.Parent.Hud)
local Run = require(script.Parent.Run)
local Ui = require(script.Parent.Ui)

local Remotes = Shared:WaitForChild("Remotes")
local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local R = Config.ROOM
local S = Config.STUDS
local CARD = Vector2.new(320, 344) -- the decorating card, laid out for a landscape phone
local FITS = Color3.fromHex("#8fe39a") -- the patch under a piece that fits
local NO_FIT = Color3.fromHex("#f07055") -- and one that doesn't
local STICK = 0.6 -- how far the stick must be pushed to move a piece
local STICK_FIRST = 0.35 -- seconds before a piece moves again with the stick held
local STICK_AGAIN = 0.18 -- and then again after that
local PAD_KEYS = {
	[Enum.KeyCode.DPadLeft] = Vector2.new(-1, 0),
	[Enum.KeyCode.DPadRight] = Vector2.new(1, 0),
	[Enum.KeyCode.DPadUp] = Vector2.new(0, -1),
	[Enum.KeyCode.DPadDown] = Vector2.new(0, 1),
	[Enum.KeyCode.Left] = Vector2.new(-1, 0),
	[Enum.KeyCode.Right] = Vector2.new(1, 0),
	[Enum.KeyCode.Up] = Vector2.new(0, -1),
	[Enum.KeyCode.Down] = Vector2.new(0, 1),
}

local Decorator = {}

type Held = {
	spot: Furniture.Spot, -- where it would go
	index: number?, -- moving a placed piece: its number in the room's list (nil for a new one)
	ghost: Model, -- this screen's own copy of it, floating where it would go
	mark: Part, -- the tiles (or the bit of wall) it would cover
	at: CFrame, -- where the ghost floats from
	hidden: Model?, -- the placed piece, hidden on this screen while it's moved
	valid: boolean, -- it fits there
}
type Pending = { kind: string, id: string, name: string, price: number }
type Deco = {
	gui: ScreenGui,
	card: Frame,
	body: Frame, -- everything on the card, rebuilt by render()
	room: string, -- the room you're looking at
	turn: number, -- quarter turns the camera has gone round the room (0: looking in from the front)
	tab: string, -- "things" or "walls"
	pending: Pending?, -- something tapped that has to be bought first
	held: Held?,
	pick: number?, -- with a controller: the placed piece picked out with the shoulder buttons
	glow: Highlight?, -- round the piece picked out
	note: string?, -- a message from the server ("There's no room there...")
	waiting: boolean, -- a request to the server is on its way
	stick: Vector2, -- the left stick
	nextNudge: number, -- when the stick may move the piece again
	connections: { RBXScriptConnection },
}

local house: CFrame? = nil -- the middle of your house while you're inside (your Indoors attribute)
local buttons: Folder? = nil -- the Decorate and Go outside buttons inside
local going = false -- going in or out right now
local deco: Deco? = nil
local fadeFrame: Frame? = nil
local MOST_ZOOM = player.CameraMaxZoomDistance -- (as the game sets it)
local toldTip = false

-- What's in your house, as saved (see server/PlayerData), or nil before it's arrived.
local function myInterior(): Furniture.Interior?
	local saved = player:GetAttribute("Interior")
	if typeof(saved) ~= "string" then
		return nil
	end
	local ok, interior = pcall(function()
		return HttpService:JSONDecode(saved)
	end)
	return if ok and typeof(interior) == "table" then interior else nil
end

-- Your house as it's built (server/Interiors), or nil.
local function houseModel(): Model?
	local houses = Workspace:FindFirstChild("Houses")
	return houses and houses:FindFirstChild(tostring(player.UserId)) :: Model?
end

-- A room's furniture as it's built, or nil.
local function piecesOf(roomId: string): Instance?
	local model = houseModel()
	local room = model and model:FindFirstChild(roomId)
	return room and room:FindFirstChild("Pieces")
end

-- The placed piece at `index` in a room, as it's built, or nil.
local function pieceModel(roomId: string, index: number): Model?
	local pieces = piecesOf(roomId)
	for _, model in if pieces then pieces:GetChildren() else {} do
		if model:GetAttribute("Index") == index then
			return model :: Model
		end
	end
	return nil
end

---------------------------------------------------------------- going in and out

-- Puts the camera back behind your animal, a normal distance away. The decorating camera, and
-- being moved in or out, can leave Roblox's camera high up and far off, looking down.
local function cameraBehind()
	local character = player.Character
	local root = character and character.PrimaryPart
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	camera.CameraType = Enum.CameraType.Custom
	if humanoid then
		camera.CameraSubject = humanoid
	end
	if not root then
		return
	end
	local back = R.CAMERA_BEHIND
	camera.CFrame = CFrame.lookAt((root.CFrame * CFrame.new(0, back.height, back.distance)).Position, root.Position)
	-- (a moment's lower zoom limit brings Roblox's zoom back in; then it's let go again)
	player.CameraMaxZoomDistance = math.max(player.CameraMinZoomDistance, back.distance)
	task.delay(0.1, function()
		player.CameraMaxZoomDistance = MOST_ZOOM
	end)
end

-- Fades the screen to dark (and waits for it), or back again.
local function fade(dark: boolean)
	if not fadeFrame then
		local gui = Ui.screen("Fade", 40) -- over everything
		gui.ScreenInsets = Enum.ScreenInsets.None
		fadeFrame = Ui.new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Ui.colors.ink,
			BackgroundTransparency = 1,
			Parent = gui,
		})
	end
	local tween = TweenService:Create(fadeFrame :: Frame, TweenInfo.new(R.FADE_SECONDS), {
		BackgroundTransparency = if dark then 0 else 1,
	})
	tween:Play()
	if dark then
		tween.Completed:Wait()
	end
end

-- Asks the server to take you in ("enter") or out ("leave"), with the screen dark meanwhile.
local function goThrough(what: string)
	if going or deco then
		return
	end
	going = true
	fade(true)
	local ok, done, why = pcall(function()
		return Remotes.RoomAction:InvokeServer(what)
	end)
	task.wait(0.1) -- (a moment for your animal to arrive)
	if ok and done then
		cameraBehind()
	end
	fade(false)
	going = false
	if not (ok and done) then
		Hud.announce("Oh!", if ok and typeof(why) == "string" then why else "Something went wrong.")
	end
end

-- An invisible spot for a button (a ProximityPrompt, shown by client/Prompts).
local function buttonAt(at: CFrame, name: string, text: string, key: Enum.KeyCode, pad: Enum.KeyCode, parent: Instance): Part
	local spot = Ui.new("Part", {
		Name = name,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Transparency = 1,
		Size = Vector3.new(1, 1, 1),
		CFrame = at,
		Parent = parent,
	})
	Ui.new("ProximityPrompt", {
		Name = name,
		ActionText = text,
		ObjectText = "Your home",
		KeyboardKeyCode = key,
		GamepadKeyCode = pad,
		HoldDuration = 0,
		MaxActivationDistance = 10,
		RequiresLineOfSight = false,
		Style = Enum.ProximityPromptStyle.Custom, -- shown at the bottom of the screen (client/Prompts)
		Parent = spot,
	})
	return spot
end

-- The buttons inside: Go outside by the front door, and Decorate, which follows you.
local function makeButtons(at: CFrame)
	local folder = Ui.new("Folder", { Name = "HouseButtons", Parent = Workspace })
	buttons = folder
	buttonAt(Furniture.frontDoor(at) * CFrame.new(0, 3, 0), "GoOutside", "Go outside", Enum.KeyCode.E, Enum.KeyCode.ButtonX, folder)
	local follow = buttonAt(at, "Decorate", "Decorate", Enum.KeyCode.F, Enum.KeyCode.ButtonY, folder)
	task.spawn(function()
		while folder.Parent do
			local root = player.Character and player.Character.PrimaryPart
			if root then
				follow.CFrame = root.CFrame
			end
			task.wait(0.2)
		end
	end)
end

---------------------------------------------------------------- seeing in

-- Is everything upstairs showing? While you decorate, when the room you're looking at is
-- upstairs; otherwise once you're far enough up the stairs (Config.ROOM.SHOW_UPSTAIRS).
local function upstairsShown(root: BasePart): boolean
	local room = deco and Furniture.room(deco.room)
	if room then
		return room.up == true
	end
	local feet = ((house :: CFrame):PointToObjectSpace(root.Position).Y - Builder.ROOT_HEIGHT) / S
	return feet > R.UPSTAIRS * R.SHOW_UPSTAIRS
end

-- While `alive` is there (the buttons inside your house), a few times a second:
--   * Downstairs, everything upstairs is hidden (like a dollhouse with its top floor lifted
--     off), so the bedroom's floor never gets in the camera's way. It shows as you come up.
--   * Looks back from your animal towards where the camera wants to be, and fades every wall
--     in the way. Roblox's camera only bumps into walls that are nearly solid, so it stays
--     back where it was, looking in through the faded wall. While you decorate, it looks from
--     the middle of the room and four spots round it, so the walls on the camera's side fade.
--     Walls come back as soon as they're out of the way.
local function cutaway(alive: Instance)
	local CUT = R.CUTAWAY
	local faded: { [Model]: boolean } = {}
	local hidden = false -- upstairs is hidden
	local upFolders: { Instance } = {}
	local watched: Model? = nil

	-- how see-through a part of the house should be on this screen
	local function apply(part: Instance)
		if not part:IsA("BasePart") then
			return
		end
		local up = false
		for _, folder in upFolders do
			if part:IsDescendantOf(folder) then
				up = true
			end
		end
		local wall = part.Parent
		part.LocalTransparencyModifier = if up and hidden then 1
			elseif wall and wall:IsA("Model") and faded[wall] then CUT.FADE
			else 0
	end
	local function applyAll(thing: Instance)
		for _, part in thing:GetDescendants() do
			apply(part)
		end
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	task.spawn(function()
		while alive.Parent do
			local inWay: { [Model]: boolean } = {}
			local model = houseModel()
			local root = player.Character and player.Character.PrimaryPart
			if model and root and house then
				if watched ~= model then
					-- (furniture and walls the server rebuilds start see-through too, if they should)
					watched = model
					upFolders = {}
					for _, room in R.ROOMS do
						local folder = model:FindFirstChild(room.id)
						if room.up and folder then
							table.insert(upFolders, folder)
						end
					end
					model.DescendantAdded:Connect(apply)
				end
				local hide = not upstairsShown(root)
				if hide ~= hidden then
					hidden = hide
					for _, folder in upFolders do
						applyAll(folder)
					end
				end

				-- the walls that could be in the way: only on floors that are showing
				local walls: { Instance } = {}
				for _, room in R.ROOMS do
					local roomFolder = model:FindFirstChild(room.id)
					local shell = roomFolder and roomFolder:FindFirstChild("Shell")
					if shell and not (room.up and hidden) then
						for _, child in shell:GetChildren() do
							if child.Name == "Wall" then
								table.insert(walls, child)
							end
						end
					end
				end
				-- where to look from, and how far towards the camera
				local looks: { Vector3 } = {}
				local reach = CUT.REACH
				local d = deco
				local room = d and Furniture.room(d.room)
				if d and room then
					local middle = Furniture.roomFrame(house, room) * CFrame.new(0, S, 0)
					for _, spot in { { 0, 0 }, { -0.3, -0.3 }, { 0.3, -0.3 }, { -0.3, 0.3 }, { 0.3, 0.3 } } do
						table.insert(looks, (middle * CFrame.new(spot[1] * room.w * S, 0, spot[2] * room.d * S)).Position)
					end
					reach = math.huge
				else
					table.insert(looks, camera.Focus.Position)
				end
				for _, from in looks do
					local away = camera.CFrame.Position - from
					local left = table.clone(walls)
					-- (a few walls can be in the way: each one found is left out of the next look)
					for _ = 1, 4 do
						if away.Magnitude < 0.1 or #left == 0 then
							break
						end
						params.FilterDescendantsInstances = left
						local result = Workspace:Raycast(from, away.Unit * math.min(reach, away.Magnitude), params)
						local wall = result and result.Instance.Parent
						if not (wall and wall:IsA("Model")) then
							break
						end
						inWay[wall] = true
						table.remove(left, table.find(left, wall))
					end
				end
			end
			for wall in faded do
				if not inWay[wall] then
					faded[wall] = nil
					applyAll(wall)
				end
			end
			for wall in inWay do
				if not faded[wall] then
					faded[wall] = true
					applyAll(wall)
				end
			end
			task.wait(CUT.SECONDS)
		end
	end)
end

---------------------------------------------------------------- the decorating camera

-- Looks down into the room you're decorating (from the front, or a side), with the whole room in the
-- part of the screen beside the card.
local function frameRoom(instant: boolean?)
	local d = deco
	local room = d and Furniture.room(d.room)
	if not (d and room and house) then
		return
	end
	local view = camera.ViewportSize
	if view.X <= 0 or view.Y <= 0 then
		return
	end
	local free = math.clamp((view.X - d.card.AbsoluteSize.X - 24) / view.X, 0.4, 1) -- the part beside the card
	local tanV = math.tan(math.rad(camera.FieldOfView / 2))
	local tanH = tanV * view.X / view.Y
	local pitch = math.rad(R.CAMERA_PITCH)
	-- the room's size as the camera sees it: across, and from near to far
	local sideways = d.turn % 2 == 1
	local wide = ((if sideways then room.d else room.w) + 1.5) * S
	local deep = ((if sideways then room.w else room.d) + 1.5) * S
	-- far enough back that the room's near edge (the widest it looks) fits across the free part,
	-- and the room fits from top to bottom
	local nearer = deep / 2 * math.cos(pitch)
	local high = deep * math.sin(pitch) + R.WALL_H * S * math.cos(pitch)
	local distance = math.max(wide / (2 * tanH * free) + nearer, high / (2 * tanV) + nearer / 2) * R.CAMERA_ROOM
	-- looking a little to the right, so the room sits in the middle of the free part
	local slide = (1 - free) * distance * tanH
	local look = Furniture.roomFrame(house, room) * CFrame.Angles(0, d.turn * math.pi / 2, 0)
		* CFrame.new(slide, R.WALL_H * S * 0.3, 0)
	local from = look * CFrame.new(0, math.sin(pitch) * distance, math.cos(pitch) * distance)
	local goal = CFrame.lookAt(from.Position, look.Position)
	camera.CameraType = Enum.CameraType.Scriptable
	if instant then
		camera.CFrame = goal
	else
		TweenService:Create(camera, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = goal }):Play()
	end
end

---------------------------------------------------------------- holding a piece

local render: () -> () -- (below)

local function hide(model: Model?, hidden: boolean)
	for _, part in if model then model:GetDescendants() else {} do
		if part:IsA("BasePart") then
			part.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
end

-- Puts the ghost and its patch where the piece you're holding would go, green if it fits.
-- The card's buttons are only redrawn when that changes.
local function check()
	local d = deco
	local held = d and d.held
	local interior = myInterior()
	local room = d and Furniture.room(d.room)
	if not (d and held and interior and room and house) then
		return
	end
	local roomAt = Furniture.roomFrame(house, room)
	local spot = held.spot
	local piece = Furniture.piece(spot.id) :: Furniture.Piece
	local was = held.valid
	held.valid = Furniture.fits(room, interior.rooms[room.id].items, spot, held.index)
	held.at = Furniture.spotFrame(roomAt, room, spot)
	if piece.layer == "wall" then
		held.mark.Size = Vector3.new(piece.w, 1.6, 0.05) * S
		held.mark.CFrame = held.at * CFrame.new(0, 0, 0.05 * S)
	else
		local w, d2 = Furniture.footprint(piece, spot.r)
		held.mark.Size = Vector3.new(w - 0.06, 0.04, d2 - 0.06) * S
		-- (the patch isn't turned with the piece: it covers its tiles)
		held.mark.CFrame = CFrame.new((held.at * CFrame.new(0, 0.03 * S, 0)).Position) * (roomAt - roomAt.Position)
	end
	held.mark.Color = if held.valid then FITS else NO_FIT
	if held.valid ~= was then
		render()
	end
end

-- A copy of a piece that only this screen sees, which nothing bumps into.
local function ghostOf(id: string): Model
	local ghost = Furniture.build(id, CFrame.identity)
	for _, part in ghost:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanQuery = false
			part.CastShadow = false
		end
	end
	return ghost
end

local function clearPick()
	local d = deco
	if d then
		d.pick = nil
		if d.glow then
			d.glow:Destroy()
			d.glow = nil
		end
	end
end

-- Puts the controller's ring back on the card (on the button called `name`, if it's there).
local function ringOn(name: string?)
	local d = deco
	if not (d and Ui.usingController()) or d.held or d.pick then
		return
	end
	local target = if name then d.body:FindFirstChild(name, true) else nil
	if not (target and target:IsA("GuiObject") and target.Selectable) then
		target = d.body:FindFirstChild("Done", true) or d.body:FindFirstChild("Cancel", true)
	end
	if target and target:IsA("GuiObject") then
		GuiService.SelectedObject = target
	end
end

-- Picks up a piece: a placed one (`index`, in the room you're looking at) to move, or a new one
-- you own to place.
local function hold(id: string, index: number?)
	local d = deco
	local interior = myInterior()
	local room = d and Furniture.room(d.room)
	if not (d and interior and room) or d.held or d.waiting then
		return
	end
	local items = interior.rooms[room.id].items
	local piece = Furniture.piece(id) :: Furniture.Piece
	local spot: Furniture.Spot
	local hidden: Model? = nil
	if index then
		local placed = items[index]
		if not (placed and placed.id == id) then
			return
		end
		spot = table.clone(placed)
		hidden = pieceModel(room.id, index)
		hide(hidden, true)
	else
		spot = Furniture.findSpot(room, items, id)
			or (if piece.layer == "wall" then { id = id, wall = "back", s = 0 } else { id = id, x = 0, z = 0, r = 0 })
	end
	clearPick()
	local ghost = ghostOf(id)
	ghost.Parent = Workspace
	local mark = Ui.new("Part", {
		Name = "Patch",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.35,
		Parent = Workspace,
	})
	d.pending = nil
	d.note = nil
	d.held = { spot = spot, index = index, ghost = ghost, mark = mark, at = CFrame.identity, hidden = hidden, valid = false }
	GuiService.SelectedObject = nil -- a controller moves the piece now
	check()
	render()
end

-- Lets go of the piece you're holding, without changing anything: a placed one shows again
-- where it was, and a new one stays ready to place.
local function drop()
	local d = deco
	local held = d and d.held
	if not (d and held) then
		return
	end
	d.held = nil
	held.ghost:Destroy()
	held.mark:Destroy()
	hide(held.hidden, false)
	render()
	ringOn()
end

-- Asks the server to do something, showing its answer on the card if it says no. Returns
-- whether it was done.
local function ask(...: any): boolean
	local d = deco
	if not d or d.waiting then
		return false
	end
	d.waiting = true
	local args = table.pack(...)
	local ok, done, why = pcall(function()
		return Remotes.RoomAction:InvokeServer(table.unpack(args, 1, args.n))
	end)
	d.waiting = false
	if deco ~= d then
		return false -- (closed meanwhile)
	end
	if ok and done then
		d.note = nil
		return true
	end
	d.note = if ok and typeof(why) == "string" then why else "Something went wrong."
	render()
	return false
end

local function place()
	local d = deco
	local held = d and d.held
	if not (d and held and held.valid) then
		return
	end
	local done = if held.index then ask("move", d.room, held.index, held.spot) else ask("place", d.room, held.spot)
	if done and deco == d and d.held == held then
		-- (the server builds it in its new spot: the one hidden here is replaced)
		held.hidden = nil
		drop()
	end
end

local function turn()
	local d = deco
	local held = d and d.held
	local room = d and Furniture.room(d.room)
	local piece = held and Furniture.piece(held.spot.id)
	if not (held and room and piece) or piece.layer == "wall" then
		return
	end
	-- turn it round the middle of its tiles, keeping it in the room
	local spot = held.spot
	local w, dd = Furniture.footprint(piece, spot.r)
	local midX, midZ = (spot.x :: number) + w / 2, (spot.z :: number) + dd / 2
	spot.r = ((spot.r or 0) + 1) % 4
	local nw, nd = Furniture.footprint(piece, spot.r)
	spot.x = math.clamp(math.round(midX - nw / 2), 0, room.w - nw)
	spot.z = math.clamp(math.round(midZ - nd / 2), 0, room.d - nd)
	check()
end

local function putAway()
	local d = deco
	local held = d and d.held
	if not (d and held) then
		return
	end
	if held.index then
		if ask("putAway", d.room, held.index) and deco == d and d.held == held then
			held.hidden = nil
			drop()
		end
	else
		drop() -- (a new one: it's still ready to place)
	end
end

-- Moves the piece you're holding a tile (across, and towards the front), or along its wall.
-- Up and down move a wall piece to the next wall.
local function nudge(step: Vector2)
	local d = deco
	local held = d and d.held
	local room = d and Furniture.room(d.room)
	local piece = held and Furniture.piece(held.spot.id)
	if not (held and room and piece) then
		return
	end
	local spot = held.spot
	if piece.layer == "wall" then
		if step.Y ~= 0 then
			local walls = {}
			for _, wall in { "left", "back", "right" } do
				if not (room.noHang and room.noHang[wall] == true) then
					table.insert(walls, wall)
				end
			end
			local at = table.find(walls, spot.wall) or 1
			spot.wall = walls[(at - 1 + (if step.Y > 0 then 1 else -1)) % #walls + 1]
		end
		local length = Furniture.wallLength(room, spot.wall :: string)
		spot.s = math.clamp((spot.s :: number) + step.X, 0, length - piece.w)
	else
		-- (up on the stick is away from the camera, whichever way round it's looking)
		local angle = (d :: Deco).turn * math.pi / 2
		local across = math.round(step.X * math.cos(angle) + step.Y * math.sin(angle))
		local forward = math.round(-step.X * math.sin(angle) + step.Y * math.cos(angle))
		local w, dd = Furniture.footprint(piece, spot.r)
		spot.x = math.clamp((spot.x :: number) + across, 0, room.w - w)
		spot.z = math.clamp((spot.z :: number) + forward, 0, room.d - dd)
	end
	check()
end

-- Takes the camera a quarter of the way round the room (`way` 1 or -1).
local function turnView(way: number)
	local d = deco
	if d then
		d.turn = (d.turn + way) % 4
		frameRoom()
	end
end

-- Moves the piece you're holding to the tile (or the bit of wall) under a tap or click.
local function aimAt(ray: Ray)
	local d = deco
	local held = d and d.held
	local room = d and Furniture.room(d.room)
	local piece = held and Furniture.piece(held.spot.id)
	if not (held and room and piece and house) then
		return
	end
	local roomAt = Furniture.roomFrame(house, room)
	local from = roomAt:PointToObjectSpace(ray.Origin) / S
	local way = roomAt:VectorToObjectSpace(ray.Direction)
	local spot = held.spot
	if piece.layer == "wall" then
		-- the nearest wall the tap points at
		local best, bestT, bestAlong = nil, math.huge, 0
		local function try(wall: string, t: number)
			if (room.noHang and room.noHang[wall] == true) or not (t > 0 and t < bestT) then
				return
			end
			local p = from + way * t
			local along = if wall == "back" then p.X + room.w / 2 else p.Z + room.d / 2
			local length = Furniture.wallLength(room, wall)
			if p.Y > 0.2 and p.Y < R.WALL_H + 0.5 and along > -0.5 and along < length + 0.5 then
				best, bestT, bestAlong = wall, t, along
			end
		end
		if way.Z ~= 0 then
			try("back", (-room.d / 2 - from.Z) / way.Z)
		end
		if way.X ~= 0 then
			try("left", (-room.w / 2 - from.X) / way.X)
			try("right", (room.w / 2 - from.X) / way.X)
		end
		if not best then
			return
		end
		spot.wall = best
		spot.s = math.clamp(math.round(bestAlong - piece.w / 2), 0, Furniture.wallLength(room, best) - piece.w)
	else
		if way.Y >= 0 then
			return
		end
		local p = from + way * (-from.Y / way.Y)
		local w, dd = Furniture.footprint(piece, spot.r)
		spot.x = math.clamp(math.round(p.X + room.w / 2 - w / 2), 0, room.w - w)
		spot.z = math.clamp(math.round(p.Z + room.d / 2 - dd / 2), 0, room.d - dd)
	end
	check()
end

local function spotKey(spot: Furniture.Spot): string
	return `{spot.x}/{spot.z}/{spot.r}/{spot.wall}/{spot.s}`
end

-- A tap or click on the room: holding a piece, it moves there (or, tapped where it is, goes
-- down); otherwise a piece tapped is picked up.
local function tapAt(position: Vector3)
	local d = deco
	if not d or d.waiting then
		return
	end
	local ray = camera:ScreenPointToRay(position.X, position.Y)
	if d.held then
		local before = spotKey(d.held.spot)
		aimAt(ray)
		if d.held and spotKey(d.held.spot) == before and d.held.valid then
			place()
		end
		return
	end
	-- (only furniture on the floor you're looking at: the other floor's is hidden or underneath)
	local here = Furniture.room(d.room)
	local folders = {}
	for _, room in R.ROOMS do
		local pieces = piecesOf(room.id)
		if pieces and here and (room.up == true) == (here.up == true) then
			table.insert(folders, pieces)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = folders
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
	local model = hit and hit.Instance:FindFirstAncestorOfClass("Model")
	local roomId = model and model:GetAttribute("Room")
	local index = model and model:GetAttribute("Index")
	if model and typeof(roomId) == "string" and typeof(index) == "number" then
		if roomId ~= d.room then
			d.room = roomId
			d.pending = nil
			frameRoom()
		end
		hold(model.Name, index)
	end
end

-- With a controller: the shoulder buttons pick out the pieces in the room one at a time.
local function pickNext(step: number)
	local d = deco
	local interior = myInterior()
	if not (d and interior) or d.held then
		return
	end
	local count = #interior.rooms[d.room].items
	if count == 0 then
		return
	end
	d.pick = ((d.pick or (if step > 0 then 0 else 1)) - 1 + step) % count + 1
	if d.glow then
		d.glow:Destroy()
		d.glow = nil
	end
	local model = pieceModel(d.room, d.pick :: number)
	-- (without its piece, a highlight would light up everything)
	d.glow = if model then Ui.new("Highlight", {
		Adornee = model,
		FillColor = Ui.colors.yellow,
		FillTransparency = 0.55,
		OutlineColor = Ui.colors.yellow,
		Parent = Workspace,
	}) else nil
	GuiService.SelectedObject = nil
	render()
end

---------------------------------------------------------------- the card

-- Points a picture's camera at a piece so all of it shows (from the front and a little above;
-- from above for a rug, and straight on for a wall piece).
local function aim(view: Camera, model: Model, layer: string)
	local box, size = model:GetBoundingBox()
	local from = if layer == "wall" then Vector3.new(0.25, 0.1, 1)
		elseif layer == "rug" then Vector3.new(0.3, 1.2, 1)
		else Vector3.new(0.7, 0.55, 1)
	local reach = size.Magnitude / 2 / math.sin(math.rad(view.FieldOfView / 2)) * 1.05
	view.CFrame = CFrame.lookAt(box.Position + from.Unit * reach, box.Position)
end

-- A price with a little coin, or some words instead.
local function priceLine(parent: GuiObject, price: number?, words: string?, color: Color3?)
	local line = Ui.new("Frame", {
		Position = UDim2.new(0, 4, 1, -24),
		Size = UDim2.new(1, -8, 0, 20),
		BackgroundTransparency = 1,
		Parent = parent,
	}, {
		Ui.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 4),
		}),
	})
	if price then
		Ui.coin(16, { LayoutOrder = 1, Parent = line })
	end
	Ui.text({
		Text = words or tostring(price),
		TextSize = 14,
		TextColor3 = color or Ui.colors.ink,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
		LayoutOrder = 2,
		Parent = line,
	})
end

-- One tile in the list: a button the size of a grid cell.
local function tile(parent: Instance, name: string, order: number, selected: boolean, onClick: () -> ()): TextButton
	local button = Ui.button("", if selected then Ui.colors.yellowLight else Ui.colors.cream, onClick, {
		Name = name,
		LayoutOrder = order,
		Parent = parent,
	})
	return button
end

-- Greys out a tile for something you haven't enough coins for yet (you can still tap it to see
-- how many more you need).
local function greyOut(button: GuiObject)
	Ui.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Ui.colors.grey,
		BackgroundTransparency = 0.45,
		ZIndex = 5,
		Parent = button,
	}, { Ui.corner(16) })
end

-- A grid of tiles in the list, under an optional heading.
local function section(list: Instance, order: number, heading: string?): Frame
	if heading then
		Ui.text({
			Text = heading,
			TextSize = 15,
			TextColor3 = Ui.colors.teal,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, 22),
			LayoutOrder = order,
			Parent = list,
		})
	end
	return Ui.new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = order + 1,
		Parent = list,
	}, {
		Ui.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(92, 96),
			CellPadding = UDim2.fromOffset(6, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
end

-- A button along the bottom of the card. `key`: the controller button for it, whose picture
-- shows in its corner while you're holding a piece (the ring isn't on the card then).
local function actionButton(row: Instance, name: string, text: string, color: Color3, x: number, wide: number, key: Enum.KeyCode?, onClick: () -> ()): TextButton
	local d = deco :: Deco
	local button = Ui.button(text, color, onClick, {
		Name = name,
		Position = UDim2.fromOffset(x, 0),
		Size = UDim2.fromOffset(wide, Ui.TOUCH),
		TextSize = 18,
		Selectable = d.held == nil,
		Parent = row,
	})
	if key and d.held and Ui.usingController() then
		Ui.new("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(4, 4),
			Size = UDim2.fromOffset(24, 24),
			BackgroundTransparency = 1,
			Image = Ui.padImage(key),
			Parent = button,
		})
	end
	return button
end

local function buy()
	local d = deco
	local pending = d and d.pending
	if not (d and pending) then
		return
	end
	if ask("buy", pending.kind, pending.id, d.room) and deco == d then
		d.pending = nil
		if pending.kind == "piece" then
			hold(pending.id) -- straight into your paws, to place
		else
			render()
			ringOn()
		end
	end
end

local function chooseStyle(kind: string, style: Furniture.Style, owned: boolean)
	local d = deco
	if not d or d.held then
		return
	end
	if owned then
		d.pending = nil
		ask("style", d.room, kind, style.id)
		render()
	else
		d.pending = { kind = kind, id = style.id, name = `{style.name} {if kind == "wall" then "wallpaper" else "floor"}`, price = style.price }
		render()
		ringOn("Buy")
	end
end

local function choosePiece(piece: Furniture.Piece, ready: boolean)
	local d = deco
	if not d or d.held then
		return
	end
	if ready then
		hold(piece.id)
	else
		d.pending = { kind = "piece", id = piece.id, name = piece.name, price = piece.price }
		render()
		ringOn("Buy")
	end
end

local function switchRoom(id: string)
	local d = deco
	if not d or d.held or d.room == id then
		return
	end
	clearPick()
	d.room = id
	d.pending = nil
	d.note = nil
	frameRoom()
	render()
end

local function switchTab(tab: string)
	local d = deco
	if not d or d.held or d.tab == tab then
		return
	end
	d.tab = tab
	d.pending = nil
	render()
end

render = function()
	local d = deco
	local interior = myInterior()
	if not (d and interior) then
		return
	end
	local selected = GuiService.SelectedObject
	local ringName = if selected and selected:IsDescendantOf(d.body) then selected.Name else nil
	d.body:ClearAllChildren()
	local held = d.held
	local roomState = interior.rooms[d.room]

	-- the rooms, along the top
	for i, room in R.ROOMS do
		local here = room.id == d.room
		local button = Ui.button(`{room.icon} {room.short}`, if here then Ui.colors.yellow else Ui.colors.cream, function()
			switchRoom(room.id)
		end, {
			Name = `Room_{room.id}`,
			Position = UDim2.fromOffset(8 + (i - 1) * 102, 8),
			Size = UDim2.fromOffset(98, Ui.TOUCH),
			TextSize = 15,
			Selectable = held == nil,
			Parent = d.body,
		})
		if held and not here then
			button.TextTransparency = 0.5
		end
	end
	-- Furniture, or Walls & floor
	for i, tab in { { "things", "Furniture" }, { "walls", "Walls & floor" } } do
		Ui.button(tab[2], if d.tab == tab[1] then Ui.colors.mint else Ui.colors.paper, function()
			switchTab(tab[1])
		end, {
			Name = `Tab_{tab[1]}`,
			Position = UDim2.fromOffset(8 + (i - 1) * 154, 58),
			Size = UDim2.fromOffset(150, Ui.TOUCH),
			TextSize = 16,
			Selectable = held == nil,
			Parent = d.body,
		})
	end

	-- the list
	local list = Ui.new("ScrollingFrame", {
		Position = UDim2.fromOffset(8, 108),
		Size = UDim2.fromOffset(CARD.X - 16, 150),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Ui.colors.creamDeep,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = d.body,
	}, {
		Ui.new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
		Ui.new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 2) }),
	})
	local coins = player:GetAttribute("Coins")
	local money = if typeof(coins) == "number" then coins else 0
	if d.tab == "things" then
		local grid = section(list, 1, nil)
		for i, piece in R.PIECES do
			local ready = Furniture.free(interior, piece.id)
			local button = tile(grid, `Piece_{piece.id}`, i, d.pending ~= nil and d.pending.id == piece.id, function()
				choosePiece(piece, ready > 0)
			end)
			button.Selectable = held == nil
			local view, viewCamera = Ui.viewport({
				Position = UDim2.fromOffset(4, 2),
				Size = UDim2.new(1, -8, 0, 52),
				Parent = button,
			})
			local model = Furniture.build(piece.id, CFrame.identity)
			model.Parent = view
			aim(viewCamera, model, piece.layer)
			Ui.text({
				Text = piece.name,
				TextSize = 13,
				Position = UDim2.fromOffset(2, 52),
				Size = UDim2.new(1, -4, 0, 18),
				Parent = button,
			})
			if ready > 0 then
				priceLine(button, nil, `{ready} to place`, Ui.colors.teal)
			else
				priceLine(button, piece.price)
				if piece.price > money then
					greyOut(button)
				end
			end
		end
	else
		for k, kind in { { "wall", "Wallpaper", R.WALLS }, { "floor", "Floor", R.FLOORS } } do
			local grid = section(list, k * 2, kind[2])
			for i, style in kind[3] do
				local owned = Furniture.hasStyle(interior, kind[1], style.id)
				local using = (roomState :: any)[kind[1]] == style.id
				local button = tile(grid, `Style_{style.id}`, i, using or (d.pending ~= nil and d.pending.id == style.id), function()
					chooseStyle(kind[1], style, owned)
				end)
				button.Selectable = held == nil
				Ui.new("Frame", {
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, 0, 0, 8),
					Size = UDim2.fromOffset(56, 40),
					BackgroundColor3 = Color3.fromHex(style.color),
					Parent = button,
				}, { Ui.corner(10), Ui.stroke(2.5, Color3.fromHex(style.trim or style.line or style.color)) })
				Ui.text({
					Text = style.name,
					TextSize = 13,
					Position = UDim2.fromOffset(2, 52),
					Size = UDim2.new(1, -4, 0, 18),
					Parent = button,
				})
				if using then
					priceLine(button, nil, "Using", Ui.colors.teal)
				elseif owned then
					priceLine(button, nil, "Yours", Ui.colors.teal)
				else
					priceLine(button, style.price)
					if style.price > money then
						greyOut(button)
					end
				end
			end
		end
	end

	-- what to do now, and your coins
	local hint = if d.note then d.note
		elseif held then (if Ui.usingController() then "Move it with the stick, then press A."
			elseif Furniture.piece(held.spot.id) and (Furniture.piece(held.spot.id) :: Furniture.Piece).layer == "wall" then "Tap a wall to hang it there."
			else "Tap the floor to move it there.")
		elseif d.pending then `{d.pending.name}`
		elseif d.pick then "Press A to move it."
		elseif Ui.usingController() then "Shoulder buttons: pick one in the room."
		else "Tap a thing in your room to move it."
	Ui.text({
		Text = hint,
		TextSize = 14,
		TextColor3 = if d.note then Ui.colors.coral else Ui.colors.ink,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(10, 260),
		Size = UDim2.fromOffset(CARD.X - 90, 30),
		Parent = d.body,
	})
	priceLine(Ui.new("Frame", {
		Position = UDim2.fromOffset(CARD.X - 78, 262),
		Size = UDim2.fromOffset(72, 28),
		BackgroundTransparency = 1,
		Parent = d.body,
	}), money)

	-- the buttons along the bottom
	local row = Ui.new("Frame", {
		Position = UDim2.fromOffset(8, 292),
		Size = UDim2.fromOffset(CARD.X - 16, Ui.TOUCH),
		BackgroundTransparency = 1,
		Parent = d.body,
	})
	if held then
		local piece = Furniture.piece(held.spot.id) :: Furniture.Piece
		local x = 0
		if piece.layer ~= "wall" then
			actionButton(row, "Turn", "🔄 Turn", Ui.colors.mint, 0, 94, Enum.KeyCode.ButtonX, turn)
			x = 100
		end
		local wide = if piece.layer ~= "wall" then 94 else 146
		actionButton(row, "PutAway", "Put away", Ui.colors.cream, x, wide, Enum.KeyCode.ButtonY, putAway)
		local placeButton = actionButton(row, "Place", "Place it", if held.valid then Ui.colors.yellow else Ui.colors.creamDeep,
			x + wide + 6, CARD.X - 16 - x - wide - 6, Enum.KeyCode.ButtonA, place)
		if not held.valid then
			placeButton.TextTransparency = 0.45
		end
	elseif d.pending then
		local pending = d.pending
		actionButton(row, "Cancel", "Cancel", Ui.colors.cream, 0, 100, nil, function()
			d.pending = nil
			d.note = nil
			render()
			ringOn()
		end)
		local short = pending.price - money
		local buyButton = actionButton(row, "Buy", if short > 0 then `Need {short} more coins` else `Buy for {pending.price} coins`,
			if short > 0 then Ui.colors.creamDeep else Ui.colors.yellow, 106, CARD.X - 16 - 106, nil, buy)
		if short > 0 then
			buyButton.TextTransparency = 0.35
		end
	else
		actionButton(row, "Done", "Done", Ui.colors.yellow, 0, CARD.X - 16, nil, function()
			Decorator.close()
		end)
	end

	if not held and not d.pick and ringName and Ui.usingController() then
		ringOn(ringName)
	end
end

---------------------------------------------------------------- opening and closing

function Decorator.isOpen(): boolean
	return deco ~= nil
end

-- Opens the decorating screen on the room you're in.
function Decorator.open()
	local root = player.Character and player.Character.PrimaryPart
	if deco or not house or not root or going or Ui.openScreens > 0 or not myInterior() then
		return
	end
	local room = Furniture.roomAt(house, root.Position) or Furniture.room("living") :: Furniture.RoomDef
	Controls.set(false, "decorate")
	Hud.show(false)
	Run.show(false)
	ProximityPromptService.Enabled = false -- (no Decorate or Go outside buttons over the card)
	Ui.openScreens += 1

	local gui = Ui.screen("Decorator", 8)
	local edge = if Ui.CONSOLE then UDim2.fromScale(1 - Config.UI.TV_SAFE, 0.5) else UDim2.new(1, -8, 0.5, 0)
	local card = Ui.new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = edge,
		Size = UDim2.fromOffset(CARD.X, CARD.Y),
		BackgroundColor3 = Ui.colors.paper,
		Parent = gui,
	}, { Ui.corner(20), Ui.stroke(3) })
	-- (fitted as if twice as wide, so it never takes more than about half the screen, and the
	-- room shows beside it)
	Ui.fitToScreen(card, CARD.X * 2, CARD.Y)
	Ui.keepRingInside(card)
	local body = Ui.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = card })
	local padShows: { () -> () } = {} -- shows or hides each turn button's controller picture
	-- the buttons that take the camera round the room, bottom left (where the thumbstick is
	-- when you're walking; it's put away while you decorate)
	local turns = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = if Ui.CONSOLE then UDim2.fromScale(Config.UI.TV_SAFE, 1 - Config.UI.TV_SAFE) else UDim2.new(0, 16, 1, -16),
		Size = UDim2.fromOffset(128, 60),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }),
	})
	Ui.hudSize(turns)
	for i, each in { { "↩️", -1, Enum.KeyCode.ButtonL2 }, { "↪️", 1, Enum.KeyCode.ButtonR2 } } do
		local button = Ui.button(each[1], Ui.colors.paper, function()
			turnView(each[2])
		end, {
			Name = `View{i}`,
			Size = UDim2.fromOffset(60, 60),
			TextSize = 28,
			LayoutOrder = i,
			Selectable = false, -- (a controller uses L2 and R2)
			Parent = turns,
		})
		button:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(1, 0)
		local pad = Ui.new("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(6, 6),
			Size = UDim2.fromOffset(24, 24),
			BackgroundTransparency = 1,
			Image = Ui.padImage(each[3]),
			Parent = button,
		})
		local function showPad()
			pad.Visible = Ui.usingController() and pad.Image ~= ""
		end
		showPad()
		table.insert(padShows, showPad)
	end

	local d: Deco = {
		gui = gui,
		card = card,
		body = body,
		room = room.id,
		turn = 0,
		tab = "things",
		pending = nil,
		held = nil,
		pick = nil,
		glow = nil,
		note = nil,
		waiting = false,
		stick = Vector2.zero,
		nextNudge = 0,
		connections = {},
	}
	deco = d
	render()
	frameRoom(true)
	ringOn()

	local function connect(signal: RBXScriptSignal, callback: (...any) -> ())
		table.insert(d.connections, signal:Connect(callback))
	end
	connect(player:GetAttributeChangedSignal("Interior"), function()
		if d.held then
			check()
		else
			render()
		end
	end)
	connect(player:GetAttributeChangedSignal("Coins"), render)
	connect(card:GetPropertyChangedSignal("AbsoluteSize"), function()
		frameRoom(true)
	end)
	connect(UserInputService.LastInputTypeChanged, function()
		for _, showPad in padShows do
			showPad()
		end
		render()
		ringOn()
	end)
	-- the piece you're holding bobs a little, and the stick moves it
	connect(RunService.RenderStepped, function()
		local held = d.held
		if not held then
			return
		end
		local now = os.clock()
		local piece = Furniture.piece(held.spot.id)
		local bob = math.sin(now * 5)
		local lift = if piece and piece.layer == "wall" then CFrame.new(0, bob * 0.04 * S, 0.05 * S)
			else CFrame.new(0, (R.HOLD_LIFT + bob * 0.06) * S, 0)
		held.ghost:PivotTo(held.at * lift)
		if d.stick.Magnitude > STICK and now >= d.nextNudge then
			local step = if math.abs(d.stick.X) > math.abs(d.stick.Y)
				then Vector2.new(math.sign(d.stick.X), 0)
				else Vector2.new(0, -math.sign(d.stick.Y))
			local first = d.nextNudge == 0
			d.nextNudge = now + (if first then STICK_FIRST else STICK_AGAIN)
			nudge(step)
		elseif d.stick.Magnitude <= STICK then
			d.nextNudge = 0
		end
	end)
	connect(UserInputService.InputChanged, function(input)
		if input.KeyCode == Enum.KeyCode.Thumbstick1 then
			d.stick = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
	connect(UserInputService.InputBegan, function(input, processed)
		if deco ~= d or GuiService.MenuIsOpen then
			return
		end
		local kind, key = input.UserInputType, input.KeyCode
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			if not processed then
				tapAt(input.Position)
			end
			return
		end
		if key == Enum.KeyCode.ButtonL2 or key == Enum.KeyCode.ButtonR2
			or ((key == Enum.KeyCode.Q or key == Enum.KeyCode.E) and not processed) then
			turnView(if key == Enum.KeyCode.ButtonR2 or key == Enum.KeyCode.E then 1 else -1)
		elseif key == Enum.KeyCode.ButtonB then
			if d.held then
				drop()
			elseif d.pick then
				clearPick()
				render()
				ringOn()
			elseif d.pending then
				d.pending = nil
				render()
				ringOn()
			else
				Decorator.close()
			end
		elseif d.held then
			if key == Enum.KeyCode.ButtonA or (key == Enum.KeyCode.Return and not processed) then
				place()
			elseif key == Enum.KeyCode.ButtonX or (key == Enum.KeyCode.R and not processed) then
				turn()
			elseif key == Enum.KeyCode.ButtonY then
				putAway()
			elseif PAD_KEYS[key] and (not processed or key.Name:sub(1, 4) == "DPad") then
				nudge(PAD_KEYS[key])
			end
		elseif key == Enum.KeyCode.ButtonR1 or key == Enum.KeyCode.ButtonL1 then
			pickNext(if key == Enum.KeyCode.ButtonR1 then 1 else -1)
		elseif key == Enum.KeyCode.ButtonA and d.pick then
			local interior = myInterior()
			local placed = interior and interior.rooms[d.room].items[d.pick]
			if placed then
				hold(placed.id, d.pick)
			end
		end
	end)
end

-- Closes the decorating screen. A piece you're holding that fits is put down first; one that
-- doesn't goes back where it was.
function Decorator.close()
	local d = deco
	if not d then
		return
	end
	if d.held and d.held.valid and house then
		place()
	end
	if deco ~= d then
		return
	end
	drop()
	clearPick()
	deco = nil
	for _, connection in d.connections do
		connection:Disconnect()
	end
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(d.gui) then
		GuiService.SelectedObject = nil
	end
	d.gui:Destroy()
	Ui.openScreens -= 1
	cameraBehind()
	ProximityPromptService.Enabled = true
	Controls.set(true, "decorate")
	Hud.show(true)
	Run.show(true)
end

---------------------------------------------------------------- starting

function Decorator.start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name == "GoInside" then
			goThrough("enter")
		elseif prompt.Name == "GoOutside" then
			goThrough("leave")
		elseif prompt.Name == "Decorate" then
			Decorator.open()
		end
	end)

	-- The server sets Indoors (where your house is) while you're inside.
	local function indoors()
		local at = player:GetAttribute("Indoors")
		if typeof(at) == "CFrame" and at == house then
			return
		end
		Decorator.close()
		if buttons then
			buttons:Destroy()
			buttons = nil
		end
		house = if typeof(at) == "CFrame" then at else nil
		if house then
			makeButtons(house)
			cutaway(buttons :: Folder)
			if not toldTip then
				toldTip = true
				Hud.announce("Home sweet home!", "Press Decorate to make it yours.")
			end
		end
	end
	player:GetAttributeChangedSignal("Indoors"):Connect(indoors)
	indoors()
end

return Decorator
