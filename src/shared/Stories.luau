-- The picture stories in the Library, from the web game's stories.js: short, warm tales about
-- the people of Sunnyfolk, for readers aged 6 to 9. Each page is a big emoji picture and a line
-- or two. At the end there's a friendly question with picture answers.
--
-- Tidying the shelves (server/Library) gives stamps, and stamps unlock the stories in this
-- order (Stories.unlockedFor). Saves keep the ids of the stories a player has read, so never
-- change a story's id.

local Config = require(script.Parent.Config)

export type Story = {
	id: string,
	title: string,
	color: string, -- its cover's colour
	cover: string, -- the emoji on its cover
	pages: { { pic: string, text: string } },
	-- the question at the end: three answers, each a picture and a few words, and which is right
	question: { ask: string, answers: { { pic: string, text: string } }, right: number },
}

local Stories = {}

Stories.LIST = {
	{
		id = "lily-map",
		color = "#6fb35c",
		title = "Lily and the Map",
		cover = "🐸",
		pages = {
			{ pic = "🐸🎒🗺️", text = "Lily the frog packed her backpack. Three snacks and one map. Time for an adventure!" },
			{ pic = "🐸🌼🌳", text = "She hopped past the country lane, humming her happy hopping song." },
			{ pic = "🌬️🗺️🌳", text = "Whoosh! The wind grabbed her map and stuck it high up in a tree." },
			{ pic = "🐸🌳😟", text = "Lily jumped and jumped. But even a very good jumper could not reach it." },
			{ pic = "🐸🍪🐦", text = "A little bird sat nearby. It looked hungry, so Lily shared one of her snacks." },
			{ pic = "🐦🗺️🐸", text = "The bird flew up, took the map, and dropped it, plop, into Lily’s hands!" },
			{ pic = "🐸🐦😊", text = "Now Lily had two snacks, one map and one new friend. The best adventure yet!" },
		},
		question = {
			ask = "Who helped Lily?",
			answers = { { pic = "🦀", text = "A crab" }, { pic = "🐦", text = "A little bird" }, { pic = "🐴", text = "A horse" } },
			right = 2,
		},
	},
	{
		id = "pepper-pumpkin",
		color = "#ee9a45",
		title = "The Giant Pumpkin Soup",
		cover = "🎃",
		pages = {
			{ pic = "🐹🥄🍲", text = "Chef Pepper stirred the soup. That spoon has stirred a thousand pots!" },
			{ pic = "🐹💭🎃", text = "‘Hmph,’ said Chef Pepper. ‘I dream of giant pumpkin soup. But my pumpkins are all tiny.’" },
			{ pic = "🦫🌱😊", text = "Fern the gardener smiled. ‘Every tiny seed can grow into something big.’" },
			{ pic = "🦫🐹💧🌱", text = "So they planted a seed together. They watered it and waited. And waited. And waited." },
			{ pic = "☀️🌧️🎃", text = "Sun came. Rain came. The pumpkin grew bigger, and bigger, and BIGGER!" },
			{ pic = "🐹🎃🍲", text = "Chef Pepper made the biggest pot of pumpkin soup Sunnyfolk had ever seen." },
			{ pic = "🦫🐹🥣😊", text = "‘Not bad,’ grumbled Chef Pepper, with a very big smile. Everyone in town had a bowl." },
		},
		question = {
			ask = "What helped the pumpkin grow?",
			answers = { { pic = "📢", text = "Lots of shouting" }, { pic = "🏎️", text = "A fast kart" }, { pic = "☀️🌧️", text = "Sun, rain and waiting" } },
			right = 3,
		},
	},
	{
		id = "pip-race",
		color = "#e5604c",
		title = "Pip Goes Slow",
		cover = "🏎️",
		pages = {
			{ pic = "🦫🏎️🍃", text = "Pip has a kart and a lucky leaf on the helmet. Today is race day!" },
			{ pic = "🦫🥞🏎️", text = "Zip ate pancakes for speed. Dash practised corners. ‘Dash is fastest!’ said Dash." },
			{ pic = "🏁🏎️💨", text = "Ready, steady, go! Zip and Dash zoomed away. Vroom, vroom!" },
			{ pic = "🦫🏎️👋", text = "Pip drove slowly and waved at everyone. ‘Hello, ducks! Hello, Biscuit!’" },
			{ pic = "🦫😟🏁", text = "Pip came last. ‘Oh dear,’ Pip sighed. ‘Maybe slow is not very good.’" },
			{ pic = "🦫🦫🥞", text = "But Zip and Dash had saved some pancakes. ‘You waved at the whole town. Everyone loved it!’" },
			{ pic = "🦫🍃😊", text = "Pip smiled. Fast is fun, and slow is fun too. Being Pip is the best!" },
		},
		question = {
			ask = "What does Pip like to do in a race?",
			answers = { { pic = "👋", text = "Go slow and wave" }, { pic = "🍦", text = "Eat ice cream" }, { pic = "😴", text = "Go to sleep" } },
			right = 1,
		},
	},
	{
		id = "pebble-post",
		color = "#5a8fd6",
		title = "Pebble’s Chilly Post Round",
		cover = "🐧",
		pages = {
			{ pic = "🐧✉️📮", text = "Pebble the penguin works at the Post Office. Today there were lots of letters." },
			{ pic = "🐧🧣🥶", text = "Brrr! Pebble was a bit cold, as always. But the letters still had to go." },
			{ pic = "🐧🦫☕", text = "At the Cafe, Biscuit gave Pebble a warm cup. ‘Warm drink, warm heart!’" },
			{ pic = "🐧🐰🎩", text = "At the Hat Shop, Clover gave Pebble a cosy hat. ‘A good hat makes any day better!’" },
			{ pic = "🐧🐹🍲", text = "Chef Pepper gave Pebble warm soup and fish-shaped biscuits. ‘Eat up,’ came a kind grumble." },
			{ pic = "🐧✉️❓", text = "At the end, there was one letter left. On the front it said: To Pebble." },
			{ pic = "🐧💌😊", text = "‘Thank you for our letters! Love from Sunnyfolk.’ Pebble felt warm all over." },
		},
		question = {
			ask = "Who was the last letter for?",
			answers = { { pic = "☕", text = "Biscuit" }, { pic = "🐰", text = "Clover" }, { pic = "🐧", text = "Pebble" } },
			right = 3,
		},
	},
	{
		id = "cosmo-clouds",
		color = "#4a5aa8",
		title = "Cosmo and the Cloudy Night",
		cover = "🔭",
		pages = {
			{ pic = "🦫🚀🔭", text = "Cosmo wears a space suit with a bubble helmet, and looks after the Observatory." },
			{ pic = "🦫💭🍋🪐", text = "‘One day I will find a planet made of yuzu,’ said Cosmo. ‘Beep boop!’" },
			{ pic = "☁️☁️🌙", text = "But tonight, big grey clouds covered the whole sky. Not one star could be seen." },
			{ pic = "🦫😔🔭", text = "Cosmo sighed. ‘Nobody will want to visit on a cloudy night.’" },
			{ pic = "👋☕☕", text = "Knock, knock! A new friend in town came to visit. Cosmo made two hot cocoas." },
			{ pic = "🦫☕✨", text = "They sipped and chatted and laughed. Slowly, the clouds drifted away. Twinkle, twinkle!" },
			{ pic = "🔭⭐🍋", text = "‘Look! A little yellow star,’ said Cosmo. ‘Maybe it is made of yuzu! Beep boop!’" },
		},
		question = {
			ask = "What did Cosmo and the new friend drink?",
			answers = { { pic = "🍋", text = "Lemonade" }, { pic = "☕", text = "Hot cocoa" }, { pic = "🥛", text = "Milk" } },
			right = 2,
		},
	},
	{
		id = "puddles-sunny",
		color = "#e9b93a",
		title = "Puddles and the Sunny Week",
		cover = "🦆",
		pages = {
			{ pic = "🦆🌧️💦", text = "Puddles the duck loves rain. Splish, splash, splosh in every puddle!" },
			{ pic = "🦆☀️😕", text = "But this week it was sunny every single day. Not one puddle anywhere." },
			{ pic = "🦆🦫🥀", text = "Fern’s sunflowers looked thirsty and droopy. ‘They need rain,’ said Fern." },
			{ pic = "🦆🪣🌻", text = "Puddles had an idea. Puddles filled a bucket and helped water every flower." },
			{ pic = "🌻💧🦆", text = "Drip, drip! A tiny puddle formed by the flowers. Puddles did one small, happy splash." },
			{ pic = "🌧️🌙🌻", text = "That night, the rain came at last. Pitter, patter, pitter, patter!" },
			{ pic = "🌈🦆🦫", text = "In the morning there was a rainbow. Puddles shared sunflower seeds with Fern. Hooray!" },
		},
		question = {
			ask = "How did Puddles help Fern?",
			answers = { { pic = "🌻💧", text = "Watered the flowers" }, { pic = "🎂", text = "Baked a cake" }, { pic = "🌙", text = "Flew to the moon" } },
			right = 1,
		},
	},
	{
		id = "dabble-splodge",
		color = "#9b72cf",
		title = "Dabble’s Big Splodge",
		cover = "🎨",
		pages = {
			{ pic = "🦫🎨🖌️", text = "Dabble the artist loves mixing colours. Blue and yellow make green. Red and white make pink!" },
			{ pic = "🦫🖼️🍋", text = "Dabble was painting the yuzu tree for the town square. It was nearly done." },
			{ pic = "💥🎨😮", text = "Then, oops! Dabble’s elbow bumped the paint pots. Splat! A big blue splodge." },
			{ pic = "🦫😢🖼️", text = "‘Oh no, my picture is spoilt,’ Dabble sniffed." },
			{ pic = "🦫🤔🖌️", text = "Then Dabble looked again. The blue splodge looked a bit like… a pond!" },
			{ pic = "🦫🦆🐸", text = "Dabble added a duck, three baby capybaras and a frog doing yoga. Silly and splendid!" },
			{ pic = "🖼️⛲😊", text = "Everyone loved it. A new friend gave Dabble a picture too. Dabble’s favourite present!" },
		},
		question = {
			ask = "What did the blue splodge turn into?",
			answers = { { pic = "🚀", text = "A rocket" }, { pic = "🦆💧", text = "A pond" }, { pic = "🍕", text = "A pizza" } },
			right = 2,
		},
	},
	{
		id = "clover-hat",
		color = "#e682a8",
		title = "A Hat for Butterscotch",
		cover = "👒",
		pages = {
			{ pic = "🐰🎩😊", text = "Clover the bunny runs the Hat Shop. ‘A good hat makes any day better!’" },
			{ pic = "🐹🐴👋", text = "‘Howdy, partner!’ said Dusty. ‘Butterscotch needs a sun hat for the ranch.’" },
			{ pic = "🐰🎩🐴", text = "Clover made a tiny hat. It sat on Butterscotch’s ear like a button. Too small!" },
			{ pic = "🐰👒🐴", text = "Clover made a big floppy hat. It flopped right over Butterscotch’s eyes. Too floppy!" },
			{ pic = "🐰🧵✨", text = "Clover did not give up. Snip, snip, stitch, stitch. Time to try again." },
			{ pic = "🐴👒🥕", text = "The new hat fitted just right. It even had a carrot on top!" },
			{ pic = "🐴🥕🐰", text = "Butterscotch munched the carrot. Clover laughed and shared a secret carrot stash. ‘Yee-haw!’" },
		},
		question = {
			ask = "What was on top of the best hat?",
			answers = { { pic = "🌸", text = "A flower" }, { pic = "🐟", text = "A fish" }, { pic = "🥕", text = "A carrot" } },
			right = 3,
		},
	},
} :: { Story }

-- Every story by its id, and where it is in the list.
Stories.BY_ID = {} :: { [string]: Story }
Stories.INDEX = {} :: { [string]: number }
for i, story in Stories.LIST do
	Stories.BY_ID[story.id] = story
	Stories.INDEX[story.id] = i
end

-- How many stamps unlock story number `n` (1 is the first story).
function Stories.stampsFor(n: number): number
	local L = Config.LIBRARY
	return L.FIRST_STORY + (n - 1) * L.STORY_EVERY
end

-- How many stories `stamps` stamps have unlocked (0 to all of them).
function Stories.unlockedFor(stamps: number): number
	local L = Config.LIBRARY
	if stamps < L.FIRST_STORY then
		return 0
	end
	return math.min(#Stories.LIST, 1 + math.floor((stamps - L.FIRST_STORY) / L.STORY_EVERY))
end

return Stories
