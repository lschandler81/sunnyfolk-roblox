-- The goals: a short First Story every new player follows in order, then Adventures they
-- choose one at a time on the Goals screen. Each goal pays coins and sunshine once.
--
--   First Story: say hello to Clover (which opens Fern's Garden), plant your first seeds,
--   water and pick them (the very first crop grows fast: Config.GARDEN.FIRST_STAGE), then buy
--   a hat with what you've earned.
--   Adventures: make a home, say hello to Puddles and Pebble, adopt a pet, look round the
--   Clothes Shop, visit the gazebo.
--
-- The server (server/Goals) watches for each goal and pays the rewards; the player's screen
-- (client/GoalsPanel) shows the goal they're on and points the way. Saves keep the ids of the
-- goals a player has done, so goals can be added, moved or taken out. Never reuse an id for
-- a different goal.
--
-- kind: what finishes it.
--   talk     say hello to everyone in `who` (resident ids)
--   shop     open the shop `shop` ("hats", "clothes" or "pets")
--   hat      buy a hat (already owning one counts)
--   home     make a home at a pond (already having one counts)
--   visit    walk to `at` (within Goals.VISIT_RADIUS)
--   pet      adopt a pet (already having one counts)
--   plant    plant seeds in the Garden (something already planted counts)
--   harvest  pick something you grew in the Garden

local Config = require(script.Parent.Config)
local Looks = require(script.Parent.Looks)

export type Goal = {
	id: string,
	text: string, -- what to do
	hint: string, -- a little help underneath
	kind: string,
	who: { string }?,
	shop: string?,
	at: Vector3?,
	coins: number,
	sun: number,
	short: string?, -- an Adventure's name on its card
	-- a second message after "Well done!", if finishing this one opens something new
	next: { title: string, small: string }?,
}

local Goals = {}

Goals.STORY = {
	{ id = "hello", kind = "talk", who = { "clover" }, coins = 3, sun = 1,
		text = "Say hello to Clover", hint = "Walk up to her and press Talk",
		next = { title = "Fern's Garden is open!", small = "Clover says: follow the arrow and plant your first seeds." } },
	{ id = "plant", kind = "plant", coins = 2, sun = 1,
		text = "Plant your first seeds", hint = "Follow the arrow to Fern's Garden" },
	{ id = "harvest", kind = "harvest", coins = 5, sun = 1,
		text = "Water them and pick them", hint = "They grow fast the first time!" },
	{ id = "hat", kind = "hat", coins = 5, sun = 1,
		text = "Buy a hat", hint = `At Clover's Hat Shop. Hats start at {Looks.shopHats()[1].price} coins` },
} :: { Goal }

Goals.ADVENTURES = {
	{ id = "home", kind = "home", coins = 10, sun = 2, short = "Make a home",
		text = "Make your own home", hint = "Follow the Home Pond road to a free plot" },
	{ id = "friends", kind = "talk", who = { "puddles", "pebble" }, coins = 3, sun = 1, short = "Meet Puddles and Pebble",
		text = "Say hello to Puddles and Pebble", hint = "Follow the arrow to find them" },
	{ id = "pet", kind = "pet", coins = 5, sun = 1, short = "Adopt a pet",
		text = "Adopt a pet", hint = `At the Pet Shop, for {Config.PETS.ADOPT_PRICE} coins` },
	{ id = "clothes", kind = "shop", shop = "clothes", coins = 2, sun = 1, short = "Clothes Shop",
		text = "Look round the Clothes Shop", hint = "Follow the arrow to its door" },
	{ id = "gazebo", kind = "visit", at = Config.polar(Config.GAZEBO.angle, Config.GAZEBO.dist), coins = 3, sun = 1,
		short = "Visit the gazebo", text = "Visit the gazebo", hint = "Follow the arrow" },
} :: { Goal }

-- Every goal by its id.
Goals.BY_ID = {} :: { [string]: Goal }
for _, goal in Goals.STORY do
	Goals.BY_ID[goal.id] = goal
end
for _, goal in Goals.ADVENTURES do
	Goals.BY_ID[goal.id] = goal
end

-- Fern's Garden opens once this goal is done.
Goals.GARDEN_OPENS = "hello"

-- The goals before Step 16, in their old order (old saves kept the number of the goal a
-- player was on). Ids that are no longer goals ("coins", "shop", "library") are skipped.
Goals.OLD_ORDER = { "hello", "coins", "friends", "shop", "hat", "home", "library", "gazebo", "pet", "harvest" }

-- A bonus for finishing them all.
Goals.FINISH = { coins = 10, sun = 2 }

-- How close (web units) counts as visiting somewhere.
Goals.VISIT_RADIUS = 5

-- How many of the residents in `met` this goal is asking for.
function Goals.metCount(goal: Goal, met: { string }): number
	local n = 0
	local who: { string } = goal.who or {}
	for _, id in who do
		if table.find(met, id) then
			n += 1
		end
	end
	return n
end

-- Which First Story goal this is (1 to 4), or nil for an Adventure.
function Goals.storyStep(id: string): number?
	for i, goal in Goals.STORY do
		if goal.id == id then
			return i
		end
	end
	return nil
end

function Goals.isAdventure(id: string): boolean
	for _, goal in Goals.ADVENTURES do
		if goal.id == id then
			return true
		end
	end
	return false
end

function Goals.storyDone(done: { string }): boolean
	for _, goal in Goals.STORY do
		if not table.find(done, goal.id) then
			return false
		end
	end
	return true
end

function Goals.allDone(done: { string }): boolean
	if not Goals.storyDone(done) then
		return false
	end
	for _, goal in Goals.ADVENTURES do
		if not table.find(done, goal.id) then
			return false
		end
	end
	return true
end

function Goals.gardenOpen(done: { string }): boolean
	return table.find(done, Goals.GARDEN_OPENS) ~= nil
end

-- The goal a player is on: the first First Story goal they haven't done, then the Adventure
-- they've chosen (`adventure`). Nil while they're choosing one, or once they've done them all.
function Goals.current(done: { string }, adventure: string?): Goal?
	for _, goal in Goals.STORY do
		if not table.find(done, goal.id) then
			return goal
		end
	end
	if adventure and Goals.isAdventure(adventure) and not table.find(done, adventure) then
		return Goals.BY_ID[adventure]
	end
	return nil
end

-- A list of goal ids from an attribute ("hello,plant"), for the player's screen.
function Goals.fromAttribute(value: any): { string }
	return if typeof(value) == "string" and value ~= "" then string.split(value, ",") else {}
end

return Goals
