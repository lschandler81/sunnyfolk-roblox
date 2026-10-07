# Setting up Sunnyfolk in Roblox Studio

The game's code lives in this folder, and Rojo copies it into Roblox Studio as you work. The
character models are imported into Studio once, and saved with the place.

You only need to do parts 1 to 4 once. After that, part 5 is all you do each time.

## 1. Connect Studio to this folder with Rojo

1. Open **Terminal**, go to this folder and start Rojo:

   ```bash
   cd ~/sunnyfolk-roblox
   ```

   ```bash
   rojo serve
   ```

   It says `Rojo server listening` on port 34872. Leave it running while you work.
2. In Roblox Studio, with your Baseplate place open, go to the **Plugins** tab and click
   **Rojo**. In the Rojo window click **Connect** (the address should be `localhost` and
   port `34872`).
3. If Rojo asks to accept changes, click **Accept**. In the **Explorer** you should now see:
   - `ReplicatedStorage` → `Sunnyfolk` (shared code, the character data and `Remotes`)
     and an empty `SunnyfolkModels` folder;
   - `ServerScriptService` → `Sunnyfolk` (the server's code);
   - `StarterPlayer` → `StarterPlayerScripts` → `Sunnyfolk` (each player's code).

   If Rojo complains about a **version mismatch**, update the Rojo plugin (Plugins tab →
   **Manage Plugins**) so it's version 7.

## 2. Try it before importing anything

Press **Play** (F5). You should see the welcome screen over the town square: the fountain,
the four shops, lamps with bunting, benches, trees and gates on the roads out of town.
Pick an animal and press **Play!**.

Until the characters are imported, every animal is a round stand-in, and the **Output**
window (View → Output) shows a yellow note for each missing model. That's expected.

Press **Stop** (Shift+F5) when you're done.

## 3. Import the characters

You need 13 of the files in `assets/characters`:

| For | Files |
|---|---|
| The animals you can be | `capybara.glb`, `bunny.glb`, `guineapig.glb` |
| Their hats (the Hat Shop) | `capybara-hats.glb`, `bunny-hats.glb`, `guineapig-hats.glb` |
| Their scarves | `capybara-clothes.glb`, `bunny-clothes.glb`, `guineapig-clothes.glb` |
| Clover, Puddles and Pebble | `duck.glb`, `duck-clothes.glb`, `penguin.glb`, `penguin-clothes.glb` |

(Clover is a bunny, so she uses the bunny files.)

For each file:

1. **File** → **Import 3D** (it's also on the **Home** and **Avatar** tabs), then pick the
   file from `sunnyfolk-roblox/assets/characters`.
2. In the import window's settings, check these. Leave everything else as it is:
   - **Scale Unit**: **Stud**
   - **Merge Meshes**: **off**
   - **Import Only As Model**: **on** (if you see it)
3. Click **Import**. Studio uploads the meshes to your account as it goes. The hats and
   clothes files are big, so they take a minute or two.
4. The model appears in **Workspace**. In the Explorer, drag it into
   `ReplicatedStorage` → `SunnyfolkModels`. Its name doesn't matter, but the file's name
   (like `capybara-hats`) is tidiest.

After the first one (`capybara.glb`), press Play and choose the capybara to check it looks
right, then carry on with the rest.

The game works out where every piece goes from `src/shared/MeshLayout.luau`, so it doesn't
matter where Studio drops the models or if the importer turns them round. If one was
imported at the wrong size, the game fixes it and the Output tells you.

## 4. Save the place, and turn on saving coins

1. Make sure Studio is signed in to the Roblox account that should own the game: one whose
   email and phone you know, with 2-Step Verification on. Whoever owns that account owns
   the game and the imported models.
2. **File** → **Publish to Roblox**. Make a new experience called **Sunnyfolk**. This also
   saves the imported models with the place. In the publish window:
   - **Devices**: Computer, Phone, Tablet and Console (the game works with a controller
     since Step 7b). Leave **VR** off.
   - **Team Create**: off. Its live script editing (Collaborative Editing) stops Rojo from
     updating scripts.
3. **File** → **Experience Settings** (called Game Settings in older Studio) → **Security**:
   turn on **Enable Studio Access to API Services**, then **Save**. Now coins, your animal
   and your hats are remembered between tests in Studio, as they will be for players.
4. Set the **server size to 20 players**, to match the twenty plots (ten at Home Pond, ten at
   Lily Pond). In the [Creator Dashboard](https://create.roblox.com/dashboard/creations), open
   Sunnyfolk → **Places** → the Sunnyfolk place → **Configure** (or **Access**), and set
   **Max Players** (server size) to 20. If more players join than there are plots, the extra
   ones can still play, but won't get a house on that server.
5. Optional backup of the models: right-click `SunnyfolkModels` → **Save to File…** and save
   it into `assets/models` as `SunnyfolkModels.rbxm` (see `assets/models/README.md`).

## 5. Every time you work on the game

1. In Terminal, in this folder: `rojo serve`
2. In Studio, while editing (not while playing): Plugins → Rojo → **Connect**. Do this each
   time you open Studio.
3. Edit the code here (or ask Claude to). Rojo copies each change into Studio straight away.
4. Press Play to try it. **File** → **Publish to Roblox** when you want players to get it.

Changes to scripts made inside Studio aren't copied back to this folder, so make changes
here.

## Checking hats and clothes (the wardrobe check)

Hats and clothes are fitted to each animal by the web game's exporter, so they should sit
exactly as they do in the web game. To check them all at once in Roblox:

1. In `src/shared/Config.luau`, change `Config.WARDROBE_CHECK = false` to `true` and save.
2. Press **Play** in Studio and pick any animal. You start in a fitting room: for each
   imported animal there's a row of every hat, a row of every outfit and scarf colour, and a
   row of every held thing, each labelled. They take turns walking, standing and waving.
3. Walk along the rows (and round the back) looking for anything that pokes through,
   floats or doesn't follow the animal. The **Output** lists anything that's missing, which
   usually means that animal's `-hats` or `-clothes` file isn't imported yet.
4. Set it back to `false` when you're done. It only ever works in Studio.

If something looks wrong in Roblox but right in the web game, tell Claude which animal and
which item (the label says). If it looks wrong in both, the fix belongs in the web game's
`src/chars/wear.js`, and then the models are exported again.

## Keeping it kind and safe for children

- There's no fighting, nothing to lose, and the only way to get coins is to find them.
- Players' chat uses Roblox's own chat (TextChatService). Roblox filters every message and
  applies each player's age and parental-control settings, including stricter rules for
  under-13s. The game has no text boxes of its own, so nothing typed can get round that
  filter. The residents' speech bubbles are the game's own words and only the player
  talking to them sees them.
- To turn players' chat off completely, set `Config.PLAYER_CHAT = false` in
  `src/shared/Config.luau`.
- Before making the game public, fill in the **Maturity & Compliance** questionnaire in
  the [Creator Dashboard](https://create.roblox.com/dashboard/creations) (your
  experience → **Audience**). Answered honestly, Sunnyfolk should come out as **Minimal**.
  Leave **voice chat** off in Game Settings → **Communication**.

## If something's not right

- **Nothing happens when I press Play**: check Rojo is connected (the Rojo window says
  *Connected*), and look in the Output for red errors.
- **An animal is a round stand-in**: its model isn't in `SunnyfolkModels` yet. The yellow
  note in the Output names the file to import.
- **"saving is off" in the Output, or "Saving is off in this test" on screen**: do part 4.
- **Rojo says "Http requests can only be executed by game server"**: you pressed Connect
  while playing. Press Stop, then Connect.
- **A change to the code doesn't show up in Studio** (Rojo is connected, but Studio still
  runs the old code):
  1. Check **Collaborative Editing** is off (File → Experience Settings, usually under
     Other). With it on, Rojo can't update scripts.
  2. If it still doesn't update: press Stop, Disconnect Rojo, delete the three **Sunnyfolk**
     folders (in ReplicatedStorage, ServerScriptService and StarterPlayer →
     StarterPlayerScripts), then Connect and Accept. Rojo puts them back fresh. Never delete
     **SunnyfolkModels**: that's your imported animals and hats.
  3. To check, open a script in Studio and search for something new in it.
- **"Script Editor's read-only due to an unstable connection"**: that's Team Create losing
  its connection for a moment. It doesn't affect Rojo. If it keeps happening, turn Team
  Create off.
- **The capybara's face or arms are in the wrong place**: tell Claude what you see (a
  screenshot helps), and which import settings you used.
