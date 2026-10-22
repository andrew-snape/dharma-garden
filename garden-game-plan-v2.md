# Garden Game: Plan v2 (first-person view, realistic growth)

## Decisions so far
- **Camera:** fixed first-person, about 45° down over the beds (view 2). Later widen the camera toward the backyard 3/4 view (view 4), so the camera is one set of parameters, not hard-coded.
- **Art:** flat, outline-free, warm Bluey-inspired shapes with a darker offset shade layer. Style test of 4 flowers x 4 stages looked good.
- **Growth time:** realistic weeks to months, with visible micro changes every visit.
- **Micro changes wanted:** continuous growth, daily-life details, aging and seasons, wind sway and moving light.
- **Already built:** engine, weather (live Open-Meteo), seasons, palette, placeholder app, flower style sheet. Details in the code under `DharmaGardenCore/` and `App/`.

## What changes in the engine
1. **Realistic durations** (days from seed to first bloom): daisy 49, poppy 70, sunflower 84, lavender 120. All in `Tuning`/`FlowerType`.
2. **Continuous progress, no stage jumps.** The four stages stay as labels for the game (harvest only when blooming), but drawing uses `progress` 0...1 directly.
3. **Full life cycle:** growing -> bloom (about 10 days at full flower) -> fading (petals drop) -> seed head. Harvest window sits inside bloom; unpicked flowers age out gracefully, never harshly.
4. **Per-plant variation** from a seed stored on the bed: growth speed +/-8%, lean angle, height, leaf count, so no two daisies look identical.
5. **Continuous thirst:** moisture drives leaf droop smoothly (not only wilt at 48h). Watering perks leaves up over the next hour.
6. **Rebalance economy** to slower income: sell value roughly days/4 coins, seed price about a third of that; starting coins enough for 2-3 seeds.
7. **Long catch-up:** hourly simulation for up to 120 days is cheap. Open-Meteo forecast API serves 92 past days; beyond that use neutral weather for the older hours.
8. **Save migration:** bump a `version` field in `Garden`; old test saves reset (acceptable pre-release).

## Rendering (the big piece)
1. **Scene layers**, back to front: sky and weather, far hills and trees, fence, lawn, beds, foreground (watering can, tools), light and rain overlays.
2. **Projection:** `Camera` struct (height, pitch, distance, field of view) maps bed (row, col) to screen position and scale. Back rows smaller, front rows larger. View 4 later = different `Camera` values plus extra layers.
3. **Parametric plants:** `FlowerArt` takes progress, thirst droop, openness, age/fade, plant seed, wind sway, and sun direction. Stem height, leaf size and count, petal count and size scale smoothly.
4. **Hit testing** in projected space, with enlarged tap areas for small back-row plants.
5. **Lighting:** sun position from real sunrise/sunset sets shadow direction and length, and warm/cool light. Weather overlays already built are reused.
6. **Animation:** `TimelineView` at about 30 fps only while the window is active. Wind sway amplitude from real wind speed, rain drops, drifting clouds, petals opening through the day.
6b. **Gentle camera drift:** a slow, subtle breathing motion of the `Camera` (a few pixels of sideways and vertical sway, a fraction of a degree of pitch, roughly a 12-20 second loop), so it feels like a person standing still and looking. Layers move by depth (parallax): sky barely, fence and lawn a little, beds and foreground most. Strength scales with wind and is a setting with an off switch (and respects the macOS Reduce Motion setting). Drift is applied in the `Camera` projection only, so tap hit testing uses the same drifted positions.
7. **Seasons and aging visuals:** lawn and foliage colour by season, yellowing lower leaves with age, soil darker when wet and lighter when dry, grass growing between visits.
8. **Fix style sheet issues first:** sunflower head cropped, lavender spike a messy blob.

## Order of work
1. Fix flower art issues; make `FlowerArt` parametric (progress, droop, fade, variation) and render a time-lapse strip PNG per flower (day 0 to bloom to fade) to judge micro changes by eye.
2. Engine v2: durations, life cycle, per-plant seed, thirst droop value, migration, updated tests.
3. `Camera` and perspective scene with static layers; 4x4 beds projected; tap and hit testing wired to the engine.
4. Lighting, shadows and real-weather sky integrated into the scene.
5. Animation: sway, rain, clouds, petals opening, gentle camera drift with parallax.
6. Debug time-lapse scrubber in the app (slide forward days to check growth and aging).
7. Remaining V1 pieces: seed shop screen, location and manual town, reminders, settings, first-run.
8. Toward view 4: widen camera, add fence and house, more beds, bees and butterflies, decorations.

## Verification
- `swift test` for engine rules (durations, life cycle, droop, determinism, migration).
- Rendered PNG sheets from tests for each flower at progress steps and for the full time-lapse.
- App run with the time scrubber: plant a daisy, scrub 49 days, confirm smooth growth, bloom, fade; check the scene at dawn, noon, dusk, rain, heat, frost via debug weather override.

## Decisions (answered)
- **Self-sowing:** unpicked flowers fade, form a seed head, then drop seeds. Each empty neighbouring bed (up, down, left, right) has a deterministic 35% chance of a volunteer seedling of the same flower. Picked flowers never self-sow.
- **Lavender stays at 120 days** in V1.

## Delivery process
Haiku agents do the work in waves; Sonnet (the project manager) writes the briefs, keeps file ownership disjoint, checks each result by running the tests and viewing rendered output, then starts the next wave.
- Wave 1 (parallel): A) art, `DharmaGardenArt` + style sheet tests. B) engine v2, `DharmaGardenCore` engine + tests.
- Wave 2: perspective scene and tapping, wired to the new art and engine.
- Wave 3: lighting, animation, camera drift, debug time scrubber.
- Wave 4: shop, location, reminders, settings.
