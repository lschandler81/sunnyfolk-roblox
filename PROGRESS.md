# Progress

One line per finished step from `docs/BUILD_STEPS.md`: the step, the date, what changed, and
anything still left for the owner to do.

- Step 1 (2026-10-06): added CLAUDE.md (what the project is, folder layout, rules for every session) and this file. Nothing left for you.
- Step 2 (2026-10-06): made saving safe in src/server/PlayerData.luau, with the numbers in Config.SAVE. Each save is locked to one server at a time, saves never overwrite newer data, saves have a version number (old saves upgrade on load), a save that can't be opened gets a kind "try again" kick instead of unsaved play, and PlayerData.saveNow(player) is ready for purchases. Tested in Studio: coins and home survive a leave and rejoin. Left for you: when you first publish this update, use "Shut down all servers" in the Creator Dashboard, so no old server overwrites a lock. Purchases (Step 19) still need their own record of granted receipts.
