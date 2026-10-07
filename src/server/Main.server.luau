-- Starts the game on the server: builds the town, then looks after players, coins, the Hat
-- Shop, the residents, players' homes, the goals, the daily present and request board, and
-- badges.

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Builder = require(ReplicatedStorage:WaitForChild("Sunnyfolk").CharacterBuilder)

local Avatars = require(script.Parent.Avatars)
local Badges = require(script.Parent.Badges)
local Coins = require(script.Parent.Coins)
local Daily = require(script.Parent.Daily)
local Goals = require(script.Parent.Goals)
local HatShop = require(script.Parent.HatShop)
local Homes = require(script.Parent.Homes)
local PlayerData = require(script.Parent.PlayerData)
local Residents = require(script.Parent.Residents)
local Town = require(script.Parent.Town)
local Wardrobe = require(script.Parent.Wardrobe)

-- Animals bump into each other (set this to false to let them walk through each other).
local group = Builder.COLLISION_GROUP
if not PhysicsService:IsCollisionGroupRegistered(group) then
	PhysicsService:RegisterCollisionGroup(group)
end
PhysicsService:CollisionGroupSetCollidable(group, group, true)

local town = Town.build()
PlayerData.start()
Avatars.start()
Coins.start()
HatShop.start()
Residents.start(town.doors)
Homes.start(town.plots)
Goals.start()
Daily.start()
Badges.start()

-- In Studio, with Config.WARDROBE_CHECK on, everyone starts in the fitting room instead.
local fittingRoom = Wardrobe.build()
if fittingRoom then
	Avatars.spawnPoint = fittingRoom
end
