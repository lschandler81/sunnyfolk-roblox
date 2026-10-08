-- The Cafe's food and drink (Config.CAFE.MENU), from the web game's cafe/food.js: cocoa, a
-- yuzu cake, pancakes and pumpkin soup, each a few simple parts. The server puts one on the
-- counter at each station; each player's screen draws them in the visitors' order bubbles,
-- on the tables, over the heads of helpers carrying one, and on the cards (client/Cafe).
-- "dirty" is the stack of dirty plates a visitor leaves behind, for a helper to wash up, and
-- CafeFood.tub() is the wash-up tub they go in.
-- Every dish is a picture, so nobody has to read to know what a visitor wants.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Sunnyfolk")
local Build = require(Shared.Build)
local Config = require(Shared.Config)

local C = Build.C
local S = Config.STUDS
-- nothing to bump into, no shadows: they're small, and some float over heads
local PROPS = { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }

local COCOA = Color3.fromHex("#7a4a2e")
local SPONGE = Color3.fromHex("#f7e2b0")
local ICING = Color3.fromHex("#fbd85a")
local PANCAKE = Color3.fromHex("#e2a860")
local BUTTER = Color3.fromHex("#fff3c0")
local SOUP = Color3.fromHex("#f0a050")
local CRUMBS = Color3.fromHex("#b98a5a")

local CafeFood = {}

-- One dish, `scale` times its real size, standing on the ground at the origin. Its parts are
-- anchored; move it with PivotTo (its pivot stands upright on the ground at its middle).
function CafeFood.model(id: string, scale: number?): Model
	local model = Instance.new("Model")
	model.Name = id
	local k = (scale or 1) * S
	local function u(x: number, y: number, z: number): CFrame
		return CFrame.new(x * k, y * k, z * k)
	end
	local function put(p: BasePart)
		p.Parent = model
	end

	if id == "cocoa" then
		-- a cream mug of cocoa with a marshmallow, and a handle
		put(Build.cylinder(0.2 * k, 0.32 * k, u(0, 0.16, 0), C.cream, PROPS))
		put(Build.cylinder(0.17 * k, 0.02 * k, u(0, 0.32, 0), COCOA, PROPS))
		put(Build.blob(Vector3.new(0.14, 0.08, 0.14) * k, u(0.04, 0.34, 0.02), C.white, PROPS))
		put(Build.block(Vector3.new(0.06, 0.2, 0.06) * k, u(0.28, 0.17, 0), C.cream, PROPS))
		for _, y in { 0.08, 0.26 } do
			put(Build.block(Vector3.new(0.1, 0.05, 0.06) * k, u(0.23, y, 0), C.cream, PROPS))
		end
	elseif id == "cake" then
		-- a little round yuzu cake on a plate: sponge, yellow icing and a yuzu on top
		put(Build.cylinder(0.38 * k, 0.03 * k, u(0, 0.015, 0), C.white, PROPS))
		put(Build.cylinder(0.26 * k, 0.24 * k, u(0, 0.15, 0), SPONGE, PROPS))
		put(Build.cylinder(0.27 * k, 0.06 * k, u(0, 0.29, 0), ICING, PROPS))
		put(Build.ball(0.14 * k, u(0, 0.37, 0), C.yuzu, PROPS))
		put(Build.blob(Vector3.new(0.1, 0.03, 0.06) * k, u(0.06, 0.43, 0), C.leaf, PROPS))
	elseif id == "pancakes" then
		-- a stack of three on a plate, with syrup and a pat of butter
		put(Build.cylinder(0.38 * k, 0.03 * k, u(0, 0.015, 0), C.white, PROPS))
		for i = 0, 2 do
			put(Build.cylinder(0.27 * k, 0.08 * k, u(0, 0.07 + i * 0.085, 0), PANCAKE, PROPS))
		end
		put(Build.cylinder(0.21 * k, 0.02 * k, u(0, 0.3, 0), ICING, PROPS))
		put(Build.blob(Vector3.new(0.14, 0.07, 0.12) * k, u(0.02, 0.33, 0.02), BUTTER, PROPS))
	elseif id == "soup" then
		-- a teal bowl of pumpkin soup, with a curl of steam
		put(Build.cylinder(0.3 * k, 0.2 * k, u(0, 0.12, 0), C.teal, PROPS))
		put(Build.cylinder(0.2 * k, 0.04 * k, u(0, 0.02, 0), C.teal, PROPS))
		put(Build.cylinder(0.26 * k, 0.02 * k, u(0, 0.22, 0), SOUP, PROPS))
		for i, x in { -0.07, 0.07 } do
			put(Build.blob(Vector3.new(0.06, 0.14, 0.06) * k, u(x, 0.36 + i * 0.05, 0), C.white, PROPS))
		end
	elseif id == "dirty" then
		-- two plates, one on the other, a little skew, with crumbs and a smear of soup on top
		put(Build.cylinder(0.38 * k, 0.04 * k, u(0, 0.02, 0), C.white, PROPS))
		put(Build.cylinder(0.36 * k, 0.04 * k, u(0.05, 0.065, 0.03) * CFrame.Angles(0, 0, 0.05), C.white, PROPS))
		put(Build.blob(Vector3.new(0.3, 0.02, 0.18) * k, u(0.0, 0.09, 0.05), SOUP, PROPS))
		for i = 0, 4 do
			local a = i * 1.3
			put(Build.ball(0.06 * k, u(math.cos(a) * 0.18 + 0.05, 0.1, math.sin(a) * 0.15), CRUMBS, PROPS))
		end
		put(Build.block(Vector3.new(0.04, 0.03, 0.36) * k, u(-0.12, 0.11, 0) * CFrame.Angles(0, 0.4, 0), Color3.fromHex("#b8c4c8"), PROPS))
	end
	-- (without this, a model's pivot takes the tilt of its first part, and PivotTo tips it over)
	model.WorldPivot = CFrame.identity
	return model
end

-- The wash-up tub, `scale` times its real size, standing at the origin: a grey tub of water
-- with bubbles on it, and a tap at the back (-Z). Anchored; move it with PivotTo.
function CafeFood.tub(scale: number?): Model
	local model = Instance.new("Model")
	model.Name = "WashTub"
	local k = (scale or 1) * S
	local function u(x: number, y: number, z: number): CFrame
		return CFrame.new(x * k, y * k, z * k)
	end
	local STEEL = Color3.fromHex("#b8c4c8")
	local TAP = Color3.fromHex("#8aa0a8")
	for _, p in {
		Build.cylinder(0.5 * k, 0.36 * k, u(0, 0.18, 0), STEEL, PROPS),
		Build.cylinder(0.44 * k, 0.04 * k, u(0, 0.34, 0), C.water, PROPS),
		Build.cylinder(0.04 * k, 0.5 * k, u(0, 0.58, -0.45), TAP, PROPS),
		Build.cylinder(0.04 * k, 0.3 * k, u(0, 0.83, -0.32) * CFrame.Angles(math.pi / 2, 0, 0), TAP, PROPS),
	} do
		p.Parent = model
	end
	for i = 0, 5 do
		local a = i * 1.05
		Build.ball((0.16 + (i % 3) * 0.05) * k, u(math.cos(a) * 0.28, 0.4, math.sin(a) * 0.24), C.white, PROPS).Parent = model
	end
	model.WorldPivot = CFrame.identity
	return model
end

return CafeFood
