# Garden performance plan (v6)

Goal: the garden should cost as little CPU as possible while it sits open, without any visible or audible change.
Every phase ends with `swift test`, an app build, and the same scene PNGs rendered before and after.

## What the code does today (verified 2026-10-22)

- **Every mouse move rebuilds the whole main view.** `onHover` writes `@State hoverPoint` in `GardenView`
  (App/GardenView.swift:55, :538). The entire 941-line body is rebuilt on each move: header, bottom bar,
  `GardenAdvice.tips` (computed twice), chores, and `palette`. `palette` calls `weather.palette(at: Date())`, so the
  sun position is worked out again each time. Hover is reported even when no seed is selected.
- **The scene redraws every layer on every frame** (30 fps idle, 60 fps while acting), via one `TimelineView` in
  `GardenSceneView`. Of the 12+ canvases:
  - Sky, horizon, back barrier, backdrop props, side barriers and foreground never read the time. They depend only on
    size, the undrifted camera, palette, style, theme and soil lift. Drift only shifts them (`canvas(... layer)`
    translates by `layerShift`). The one exception is the urban side barrier: it calls `urbanGroundAligned()`, which
    draws its props with the drifted camera.
  - Clouds, ambient touches (smoke, cats, bulbs, petals), rain and fog read the time.
  - The ground, the patch and the chair use the drifted camera, which includes pitch drift (a change of perspective,
    not a shift), so they really do change every frame.
- **Each frame repeats work that only changes with the garden:** `SceneContent.body` rebuilds the plant and weed
  dictionaries, `drawOrder` (sort plus `planterFrontDepths`), and `ghostSpot` → `GardenEngine.canPlant`.
- **Plants really do move every frame.** `FlowerArt` bends the stem with `sway` (not a plain shift), and
  `WeedRosette` rebuilds 10 toothed leaves per weed. Neither is `Equatable`, so they also redraw when paused.
- **Music is synthesised live** (`AVAudioSourceNode` → `GardenSynth.renderInterleaved`). The flute, drone and
  e-piano voices call Double `sin`/`exp` for every sample; the piano voice already uses a rotating oscillator.
- **The app is normally run as a Debug build** (`-Onone`), which makes the synth and the canvas code several times
  slower than a Release build.
- **The engine is cheap at current sizes.** `slowdowns` compares all pairs of plants, but there are at most about
  60. Catch-up runs on the main thread at about 0.4 ms per simulated hour in Debug, so roughly 0.3 s for a month away.

## Phase 0: Baseline (measure first)

1. Add `ScenePerformanceTests`. It renders `SceneContent` with `ImageRenderer` for a 60-plant, 20-weed garden in
   every theme and both styles, at a fixed `SceneMotion.Frame`, and records the time per frame (`XCTClockMetric`;
   a baseline only, no pass/fail limit, because timing tests are flaky under load).
2. Profile the Debug and Release app in Instruments (Time Profiler plus the SwiftUI instrument) in three states:
   idle, moving the mouse over the scene, and watering by dragging. Note the main-thread % and frame time for each.
3. Record the numbers in this file. Use them to decide whether phases 4 and 6 are worth doing.

## Phase 1: Stop hover rebuilding the whole view (high payoff, low risk)

- Move `hoverPoint` into a small `@Observable` `PointerModel`. Only the scene and the hovered-plant card read it
  (`GardenView` :670 and :698 move into a child view), so a mouse move no longer touches `GardenView.body`.
- Make `palette` a `@State`, refreshed by the existing minute timer, by weather report changes and by theme changes,
  instead of recalculating `Date()` and the sun position on every body rebuild. This also keeps the palette stable,
  which phase 2 relies on.
- Compute `GardenAdvice.tips` once per body, not twice.
- Check: Instruments shows `GardenView.body` no longer runs on mouse moves. The ghost seed, invalid-spot tint and
  plant card behave as before.

## Phase 2: Draw the backdrop layers once (high payoff, medium risk)

- Make `Camera` `Equatable`.
- Add a `SceneStaticLayer: View, Equatable` that wraps one `Canvas`. Its inputs are size, camera, palette, style,
  theme, soil lift and which layer to draw. Apply it with `.equatable()` and move it by the parallax with `.offset`
  outside the view. An offset only moves an already-drawn layer, so the paths are not drawn again.
- Static layers: sky (gradient only), horizon, the fence group (backdrop props, barrier, side barriers) and the
  foreground.
- Split clouds out of the sky canvas into their own live canvas. Split `drawUrbanProps` out of the urban side
  barriers into a live ground-aligned canvas, drawn in the same z position.
- Check: the existing render tests (SceneTests, SceneStyleRenderTests, SceneFenceJoinTests, SceneThemeUKWallTests)
  pass unchanged. Before and after PNGs at a non-zero drift frame match pixel for pixel (or within 1/255 if
  antialiasing differs). The phase 0 benchmark shows the gain.

## Phase 3: Take garden-only work off the frame loop (medium payoff, low risk)

- Pass a `SceneLayout` value (plant and weed dictionaries, depth-sorted entries, planter front depths) into
  `SceneContent`. Build it in `GardenSceneView` only when `garden` changes, outside the `TimelineView`. Only the
  visitor entries are merged in per frame.
- Have `GardenView` always pass `ghostValid`, so `ghostSpot` never calls `canPlant` per frame.
- Merge the ground, patch and chair canvases into one canvas, which saves two layers per frame.
- Check: `drawOrder` tests still pass, and `SceneRenderTests` match.

## Phase 4: Plants (payoff depends on the baseline; visual sign-off needed for 4b)

- 4a (no visual change): make `FlowerArt` and `WeedRosette` `Equatable` and apply `.equatable()`. When the scene is
  paused (Reduce Motion, drift off, app inactive) sway is 0, so nothing redraws. Seed-head, dead and fully calm plants
  then cost nothing.
- 4b (choose one, then show the user before and after renders or a short screen recording):
  - Update plant sway at 15 fps while the rest of the scene stays at 30 or 60 fps (round the timeline time down for
    sway only). Half the plant cost, and the slow 2.6–3.8 s sway should still look smooth.
  - Or draw each plant once without sway and apply sway as a shear anchored at the soil line. This removes almost all
    of the plant cost, but the bend becomes even along the stem instead of strongest at the top.
- Skip 4b if phase 0 shows plants are a small share of the frame.

## Phase 5: Release builds for play (large payoff, no code risk)

- Add a `Play` scheme (or document the command) that builds the Release configuration into
  `~/Library/Caches/dharma-derived`, and use it for everyday play and listening tests. Keep Debug for development.
- Optionally, set `SWIFT_OPTIMIZATION_LEVEL: -O` on the DharmaGardenCore target for Debug in `project.yml`, so the
  synth and drawing code are fast even in dev builds (stepping through the package code in the debugger gets worse).

## Phase 6: Cheaper synth voices (medium payoff, audible-risk: compare renders)

- Flute, drone, e-piano: replace the per-sample `sin(phase)` with the rotating (cos, sin) pair the piano already
  uses, and the per-sample `exp(-t/τ)` envelopes with a multiply by a fixed factor each sample. Work in `Float` where
  the piano does.
- Re-check the e-piano's FM step: it needs `sin(carrier + index·sin(modulator))`, so keep one `sin` for the carrier
  and rotate the modulator.
- Check: offline renders before and after with `MUSIC_RENDER_DIR`. The report's RMS and "above 3 kHz" share stay
  within 1%, and the largest per-sample difference is below −60 dB. The user listens to the Urban theme before
  signing off. Expected side effect: the ~100 s music tests get faster.

## Phase 7: Small items (do only alongside other work)

- Engine: compare squared distances in `slowdowns`, `canPlant` and `sowVolunteers`.
- Run catch-up longer than 24 h in a detached `Task`, then apply the result on the main actor (show the existing
  "Welcome back" card when it finishes).
- `GardenStore.save()`: reuse one static `JSONEncoder`.

## Order and notes

0 → 1 → 2 → 3 → 5, then 4 and 6 based on the baseline numbers, then 7. Commit each phase separately.
Other sessions edit SceneView.swift and GardenView.swift, so make targeted edits and rebase before each phase.
