# Sunnyfolk for Roblox

A Roblox version of [Sunnyfolk](https://github.com/lschandler81/game), a cosy little animal town
for children aged 6–9. Make friends, collect coins and find a hat you love.

## What's in the game so far

- **The town square**, about twice the size of the web game's: the fountain with its giant
  stone yuzu, Clover's Hat Shop and three more shops (opening soon), a ring of lamps with
  bunting, benches and flower beds, the library on the south lawn, a gazebo, cottages along
  the roads (with a duck pond by Puddles' house), meadows full of trees and flowers, and gates
  on the roads to the places that come next.
- **Choose your animal**: a capybara, bunny or guinea pig, its colours and a scarf. Change
  any time from **My things** (the **Change animal** button there).
- **Walk around**: the animals waddle, breathe, look around and blink, just like in the web game.
- **Residents**: Clover the bunny (by her Hat Shop), Puddles the duck, Pebble the penguin, and
  Biscuit the capybara and Chef Pepper at the Cafe. Walk up and press **Talk** to see what they say in a speech bubble. The first
  time each visit, they wave and say hello by name.
- **Coins** float round the square. Walk into one to pick it up; it comes back a few
  minutes later. Coins are saved between visits.
- **Clover's Hat Shop** and **the Clothes Shop**: try things on, buy them with coins and wear
  them: a hat, and clothes for your neck (bandanas, instead of your scarf), body (aprons,
  raincoats, a space suit) and back (backpacks). Everyone sees what you're wearing.
- **Your own home at Home Pond**: follow the Home Pond road to two neighbourhoods of ten
  plots, each round a pond (Home Pond, and Lily Pond along a path just inside the town
  hedge). Pick a free plot and design your house: its shape (cottage, tall house or
  round hut), wall, roof and door colours, a garden (flowers, vegetables or a little pond) and
  a sign with your name. Change it any time at your front door. It's saved, and next visit
  you move straight back in.
- **Pets**: adopt a puppy, kitten or duckling at the Pet Shop, pick its colour and a name, and
  dress it in a collar and something for its head. It trots after you everywhere, sits when you
  stop and hops when you jump, and everyone can see it.
- **Biscuit's Cafe**, at the end of the Cafe road (once you have 4 sunshine): ask Biscuit for a
  shift, then carry each visitor what their bubble shows, from the counter to their table,
  and take their dirty plates to the wash-up tub. A friend can join the same shift, and every
  helper is paid for every order.
- **Fishing** at Home Pond, Lily Pond and Puddles' pond: cast, wait for the splash, then reel
  in. Every fish goes back in the water and into your **Fish Book**, which shows the shape of
  the next fish to find. A new fish pays a few coins, and a full book gives a badge.
- **Goals**: a new player is led round town by nine little goals (say hello, pick up coins,
  buy a hat, make a home, visit places, adopt a pet), with a yellow arrow pointing the way.
  Each pays coins and sunshine; sunshine will open the gated roads once there's something
  behind them.

No fighting, nothing to lose, and chat stays within Roblox's filtered chat (see
[Keeping it kind and safe](docs/roblox-studio.md#keeping-it-kind-and-safe-for-children)).

## Getting started

Follow [docs/roblox-studio.md](docs/roblox-studio.md): connect Rojo, import the characters
into Studio, publish, and play.

## How it's put together

The code is Luau, synced into Roblox Studio by [Rojo](https://rojo.space) (`default.project.json`).

```
assets/characters/      the animals, hats and clothes from the web game (.glb) and sunnyfolk.json
assets/models/          a place to keep a backup of the models once they're imported into Studio
docs/characters.md      what's in the character models and how they fit together
docs/roblox-studio.md   step-by-step setup in Roblox Studio
tools/make_mesh_layout.py   writes src/shared/MeshLayout.luau from the .glb files

src/shared/             → ReplicatedStorage.Sunnyfolk (used by the server and every player)
  Config.luau             where things are in the square and Home Pond, the coins, the residents
  Build.luau              parts in the Sunnyfolk colours, and props: lamps, benches, trees, houses
  Houses.luau             the choices for players' houses, and building one from them
  Goals.luau              the goals for new players, and what each one pays
  PetBuilder.luau         builds a pet from simple parts, and poses it
  CafeFood.luau           the Cafe's cocoa, cake, pancakes and soup, from simple parts
  Looks.luau              easy reading of sunnyfolk.json (coats, scarves, hats, residents)
  Models.luau             finds the imported models in ReplicatedStorage.SunnyfolkModels
  MeshLayout.luau         where every mesh sits (made by the tool above)
  CharacterBuilder.luau   builds a rigged animal with its colours, clothes, held things and hat

src/server/             → ServerScriptService.Sunnyfolk
  Main.server.luau        starts everything
  Town.luau               builds the town square
  PlayerData.luau         saves coins, your animal and your hats (DataStore)
  Avatars.luau            gives each player their animal
  Residents.luau          Clover, Puddles, Pebble, Biscuit and Pepper: strolling, and facing you when you talk
  places/Cafe.luau        Biscuit's Cafe, and its shifts (checked here)
  Coins.luau              checks each coin picked up
  HatShop.luau            the shops (hats and clothes): checks each thing bought or worn
  Homes.luau              the plots at Home Pond: moving in, building houses, moving back in
  Goals.luau              watches for each goal, pays its coins and sunshine
  Pets.luau               adopting, changing and dressing pets (checked here)
  Fishing.luau            fishing: picks every bite and every fish (checked here)

src/client/             → StarterPlayer.StarterPlayerScripts.Sunnyfolk
  Main.client.luau        starts everything on each player's computer
  Chooser.luau            the welcome screen (pick your animal)
  Hud.luau                your coins, and the Goals, My things and Garden Book buttons
  GoalsPanel.luau         the goal you're on, the arrow pointing the way, and the Goals screen
  Pets.luau               everyone's pets, walked along behind their owners on your screen
  PetShop.luau            the Pet Shop screen
  Cafe.luau               the Cafe's visitors, order bubbles, buttons and shift cards
  Fishing.luau            the ponds' fishing buttons, the fishing card, and everyone's rods
  FishBook.luau           the Fish Book screen, and the fish themselves
  Coins.luau              the coins you see, spinning, and picking them up
  Talk.luau               speech bubbles and name tags
  HatShop.luau            the shop screen, for Clover's Hat Shop and the Clothes Shop
  Homes.luau              the "Make this my home" and "Change my home" buttons
  HomeDesigner.luau       the screen for designing your house
  Animator.luau           walking, breathing, blinking, nodding and waving
  Controls.luau           pauses walking while a screen is open
  Ui.luau                 the look shared by all the screens
```

### Adding things

- **Another resident**: add their id (from `sunnyfolk.json → residents`) to
  `Config.RESIDENTS` in `src/shared/Config.luau`, and import their animal's body and clothes
  files into Studio. They stroll round the home spot given in `sunnyfolk.json`.
- **More coins**: add spots to the list in `Config.COINS`.
- **More goals**: add them to `Goals.LIST` in `src/shared/Goals.luau`. Only add new goals
  at the end, so the goal number in players' saves still means the same goal.
- **More house choices** (shapes, colours, gardens): add them to the lists in
  `src/shared/Houses.luau`. The designer and the server's checks pick them up from there.
- **The models changed** (re-exported from the web game): import the new files into Studio,
  then run `python3 tools/make_mesh_layout.py` so the game knows where everything sits.
