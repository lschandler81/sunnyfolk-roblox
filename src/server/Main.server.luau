-- Starts the game on the server: builds the town, then looks after players, coins, the Hat
-- Shop, the residents and players' homes.

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Builder = require(ReplicatedStorage:WaitForChild("Sunnyfolk").CharacterBuilder)

local Avatars = require(script.Parent.Avatars)
local Coins = require(script.Parent.Coins)
local HatShop = require(script.Parent.HatShop)
local Homes = require(script.Parent.Homes)
local PlayerData = require(script.Parent.PlayerData)
local Residents = require(script.Parent.Residents)
local Town = require(script.Parent.Town)
local Wardrobe = require(script.Parent.Wardrobe)

-- Animals walk through each other rather than pushing each other about.
local group = Builder.COLLISION_GROUP
if not PhysicsService:IsCollisionGroupRegistered(group) then
	PhysicsService:RegisterCollisionGroup(group)
end
PhysicsService:CollisionGroupSetCollidable(group, group, false)

local town = Town.build()
PlayerData.start()
Avatars.start()
Coins.start()
HatShop.start()
Residents.start(town.doors)
Homes.start(town.plots)

-- In Studio, with Config.WARDROBE_CHECK on, everyone starts in the fitting room instead.
local fittingRoom = Wardrobe.build()
if fittingRoom then
	Avatars.spawnPoint = fittingRoom
end
