# Garden plan v8 — everyday use (version 1.1.0)

The game is meant to stay open all day. This phase makes it easier to live with and tidies the economy and tools.

## Versioning (starts now)
- Semantic versions: `MAJOR.MINOR.PATCH`. Each phase bumps MINOR; fixes bump PATCH. Build number (`CURRENT_PROJECT_VERSION`) goes up by one on every release build.
- 1.0.0 = everything up to commit ca1277e. This phase = **1.1.0 (build 2)**.
- `project.yml` holds `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` and the Info.plist keys; Settings shows "Version 1.1.0 (2)".
- `CHANGELOG.md` at the repo root lists each version's changes. Commits that finish a version get a git tag `v1.1.0`.

## Work, split by file ownership (Sonnet agents in parallel)

### A — App shell and HUD (App/DharmaGardenApp.swift, GardenView.swift, SettingsView.swift, AppSettings.swift, project.yml)
1. **Menu bar garden**: a `MenuBarExtra` (window style) with a leaf icon that opens a compact, clickable garden (same `GardenView` content, smaller) plus "Open Garden window" and "Quit". Settings toggle "Show in menu bar" (default on). Shares the one `GardenStore`.
2. **Garden name**: Settings text field "Gardener's name"; header reads "<Name>'s Garden" (falls back to "My Garden" when empty). Window title follows.
3. **Hide the tool bar**: a small chevron button collapses/expands the bottom bar (remembered in settings; key `H`).
4. **Carrot currency**: a small drawn carrot icon (SwiftUI shape, orange body, green tops) replaces the orange dot everywhere; "coins" → "carrots" in UI copy.
5. **Tool icons**: Weed = a hand weeder (forked-tip blade on a handle), Fork = a garden fork (four tines, D-handle). Drawn as small SwiftUI shapes, not SF Symbols.
6. **Speed setting**: Settings picker "Garden speed: 1x / 2x / 4x" (`settings.gameSpeed`), passed to `store.speed`.
7. **Version** label in Settings; bump project.yml to 1.1.0 (2).

### B — Economy and speed (DharmaGardenCore core, App/GardenStore.swift, App/ShopView.swift, core tests)
1. Seed prices 1–2 carrots (1 for quick crops, 2 for slow ones). Seasol 1, Fertiliser 2.
2. Speed: `GardenStore.speed` (1, 2, 4) multiplies how far plants, weeds and soil move per simulated hour. The clock stays real, so weather, seasons, day/night and the sundial stay true. Speed saved with the garden settings; tests for 2x/4x growth.
3. Copy in core strings (reminders, advice, chores, shop): "coins" → "carrots".

### C — Scene art (DharmaGardenCore/Sources/DharmaGardenArt)
1. **Sundial** on the lawn in every theme: stone plinth and bronze dial; the gnomon shadow points at the real local solar time (from `SunPosition`), and fades when the sun is down or it's overcast. Hover/help shows the clock time.
2. **Watering fix**: the pouring can is drawn in the tool-action layer *after* the scenery walls, so walls never cover it, at any spot in the bed.
3. **One watering can**: the pouring can uses the same art as the watering can prop in the bottom-right of the scene. Expose the prop's hit rect and a "carried" state (prop hidden while carried, drawn at a given point).

### D — Pick-up watering can (after A and C; App/GardenView.swift)
Clicking the scene's watering can picks up the Water tool; the can follows the pointer and pours where you click/drag; clicking it back on its spot (or picking another tool) puts it down.

## Done when
All tests pass, the app builds, rendered screenshots of each theme show the sundial and carrot HUD, CHANGELOG.md has 1.1.0, committed and tagged `v1.1.0` on the current branch (no push).
