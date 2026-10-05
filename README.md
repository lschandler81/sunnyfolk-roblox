# Sunnyfolk for Roblox

A Roblox version of [Sunnyfolk](https://github.com/lschandler81/game), a cosy little animal town
for children aged 6–9. Make friends, collect coins and find a hat you love.

## What's in the game so far

- **The town square**: the fountain with its giant stone yuzu, Clover's Hat Shop and three
  more shops (opening soon), lamps with bunting, benches, flower planters, trees, a picnic, a
  signpost, and gates on the roads to the places that come next.
- **Choose your animal**: a capybara, bunny or guinea pig, its colours and a scarf. Change
  any time with the **Change animal** button.
- **Walk around**: the animals waddle, breathe, look around and blink, just like in the web game.
- **Three residents**: Clover the bunny (by her Hat Shop), Puddles the duck and Pebble the
  penguin. Walk up and press **Talk** to see what they say in a speech bubble. The first
  time each visit, they wave and say hello by name.
- **Coins** float round the square. Walk into one to pick it up; it comes back a few
  minutes later. Coins are saved between visits.
- **Clover's Hat Shop**: try hats on, buy them with coins and wear them. Everyone sees your hat.

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
  Config.luau             where things are in the square, the coins, the residents, speeds
  Looks.luau              easy reading of sunnyfolk.json (coats, scarves, hats, residents)
  Models.luau             finds the imported models in ReplicatedStorage.SunnyfolkModels
  MeshLayout.luau         where every mesh sits (made by the tool above)
  CharacterBuilder.luau   builds a rigged animal with its colours, clothes, held things and hat

src/server/             → ServerScriptService.Sunnyfolk
  Main.server.luau        starts everything
  Town.luau               builds the town square
  PlayerData.luau         saves coins, your animal and your hats (DataStore)
  Avatars.luau            gives each player their animal
  Residents.luau          Clover, Puddles and Pebble: strolling, and facing you when you talk
  Coins.luau              checks each coin picked up
  HatShop.luau            checks each hat bought or worn

src/client/             → StarterPlayer.StarterPlayerScripts.Sunnyfolk
  Main.client.luau        starts everything on each player's computer
  Chooser.luau            the welcome screen (pick your animal)
  Hud.luau                your coins, and the Change animal button
  Coins.luau              the coins you see, spinning, and picking them up
  Talk.luau               speech bubbles and name tags
  HatShop.luau            the Hat Shop screen
  Animator.luau           walking, breathing, blinking, nodding and waving
  Controls.luau           pauses walking while a screen is open
  Ui.luau                 the look shared by all the screens
```

### Adding things

- **Another resident**: add their id (from `sunnyfolk.json → residents`) to
  `Config.RESIDENTS` in `src/shared/Config.luau`, and import their animal's body and clothes
  files into Studio. They stroll round the home spot given in `sunnyfolk.json`.
- **More coins**: add spots to the list in `Config.COINS`.
- **The models changed** (re-exported from the web game): import the new files into Studio,
  then run `python3 tools/make_mesh_layout.py` so the game knows where everything sits.
