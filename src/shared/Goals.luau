-- The goals that lead a new player round town, one at a time, like the web game's guided
-- start. Each pays coins and sunshine. Sunshine is saved, and will later open the gated roads
-- once there are places behind them.
--
-- The server (server/Goals) watches for each goal and pays the rewards; the player's screen
-- (client/GoalsPanel) shows the current goal and points the way.
--
-- kind: what finishes it.
--   talk   say hello to everyone in `who` (resident ids)
--   coin   pick up `need` coins
--   shop   open the shop `shop` ("hats" or "clothes")
--   hat    buy a hat (already owning one counts)
--   home   make a home at a pond (already having one counts)
--   visit  walk to `at` (within Goals.VISIT_RADIUS)
--   pet    adopt a pet (already having one counts)
--
-- Only ever add new goals at the end: saves keep the number of the goal a player is on.

local Config = require(script.Parent.Config)
local Looks = require(script.Parent.Looks)

export type Goal = {
	id: string,
	text: string, -- what to do
	hint: string, -- a little help underneath
	kind: string,
	who: { string }?,
	shop: string?,
	need: number?,
	at: Vector3?,
	coins: number,
	sun: number,
}

local Goals = {}

Goals.LIST = {
	{ id = "hello", kind = "talk", who = { "clover" }, coins = 3, sun = 1,
		text = "Say hello to Clover", hint = "Walk up to her and press Talk" },
	{ id = "coins", kind = "coin", need = 10, coins = 5, sun = 1,
		text = "Pick up 10 coins", hint = "They're all round the square" },
	{ id = "friends", kind = "talk", who = { "puddles", "pebble" }, coins = 3, sun = 1,
		text = "Say hello to Puddles and Pebble", hint = "Follow the arrow to find them" },
	{ id = "shop", kind = "shop", shop = "hats", coins = 2, sun = 1,
		text = "Look round Clover's Hat Shop", hint = "Clover or the shop door can open it" },
	{ id = "hat", kind = "hat", coins = 5, sun = 1,
		text = "Buy a hat", hint = `Hats start at {Looks.shopHats()[1].price} coins` },
	{ id = "home", kind = "home", coins = 10, sun = 2,
		text = "Make your own home", hint = "Follow the Home Pond road to a free plot" },
	{ id = "library", kind = "visit", at = Config.polar(Config.LIBRARY.angle, Config.LIBRARY.dist - 5), coins = 3, sun = 1,
		text = "Visit the library", hint = "Follow the arrow" },
	{ id = "gazebo", kind = "visit", at = Config.polar(Config.GAZEBO.angle, Config.GAZEBO.dist), coins = 3, sun = 1,
		text = "Visit the gazebo", hint = "Follow the arrow" },
	{ id = "pet", kind = "pet", coins = 5, sun = 1,
		text = "Adopt a pet", hint = `At the Pet Shop, for {Config.PETS.ADOPT_PRICE} coins` },
} :: { Goal }

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

-- The goal a player is on: 1 to #Goals.LIST, or #Goals.LIST + 1 once they've done them all.
function Goals.done(step: number): boolean
	return step > #Goals.LIST
end

return Goals
