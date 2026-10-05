# Backups of the imported models

The character models are imported into Roblox Studio from `assets/characters/*.glb` and live
in the place, in `ReplicatedStorage.SunnyfolkModels` (see `docs/roblox-studio.md`). Rojo
leaves that folder alone, because it can't recreate imported meshes itself.

To keep a copy here: in Studio, right-click `SunnyfolkModels` → **Save to File…** and save it
in this folder as `SunnyfolkModels.rbxm`. To put them back into a new place: right-click
`ReplicatedStorage` → **Insert from File…** and pick that file.
