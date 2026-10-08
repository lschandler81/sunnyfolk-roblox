---
name: step
description: Carry out one numbered step from docs/BUILD_STEPS.md for the Sunnyfolk Roblox project
disable-model-invocation: true
argument-hint: [step number, for example 7]
---

Do Step $ARGUMENTS from docs/BUILD_STEPS.md.

1. Read CLAUDE.md (if it does not exist yet, tell me to run Step 1 first) and PROGRESS.md (create it if it is missing).
2. Read Step $ARGUMENTS in docs/BUILD_STEPS.md: its Why, Files, prompt and Done when. If the step says "plan first", show me your plan and wait for my OK before you change any file. If it says "tag first", create a git tag before editing anything.
3. Use the step's prompt as your brief. Stay inside the files the step names unless you tell me why you need another.
4. Never edit anything in assets/characters or src/shared/MeshLayout.luau.
5. If the step has a "You" line, do not guess ids or imports. Leave those as clearly named placeholders and list them for me at the end.
6. When the work is done, prove the project still builds. If rojo is installed, run `rojo build -o /tmp/sunnyfolk-check.rbxl`, and run any Luau checker the repo has set up. Tell me exactly what you ran and what it said.
7. Ask the reviewer agent to review your changes. It runs on Sonnet. Run it on Opus instead (the Agent tool's model "opus") if the change touches saves (src/server/PlayerData.luau), remotes (a Remote in default.project.json, or any OnServerEvent or OnServerInvoke handler), or purchases (MarketplaceService, Products, Purchases). Fix what it marks "must fix" and tell me about the rest.
8. Give me a short checklist to test in Roblox Studio that matches the step's "Done when" line.
9. Do not commit until I tell you the Studio test passed. When I do, commit with the message "Step N: <title>" and add a line to PROGRESS.md with the step, the date, what changed and anything still left for me.
