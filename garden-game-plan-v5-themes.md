# Plan v5: garden themes (background, buildings, ambience, music)

## Decisions (from the user)
- Four themes: **Farm** (today's look), **Japanese garden**, **Rural UK garden**, **Urban backyard**.
- Independent of the existing view setting: any theme works in both **First person** and **Backyard**. First person gets the theme's horizon and barrier; Backyard adds the theme's buildings, trees, side fences and props.
- Beyond scenery, each theme also gets **ambient touches** (small animated extras and foreground props) and **its own music**.
- Look and feel only. No growth, water or shop rules change. The theme is a per-player setting like `sceneStyle` (UserDefaults, `AppSettings`), not part of the save, so it never needs a save migration.
- Free to switch any time, like the bed style. Works with all four bed styles (soil patch, mounds, grid, planter boxes) and real weather, seasons and day/night.

## Theme definitions
- **Farm (current)**: rolling green hills, post-and-rail fence, Queenslander house, gum tree, Hills Hoist, lilac watering can. Must render pixel-identical after the refactor.
- **Japanese garden**: soft layered misty mountains; a low earthen wall with a tiled cap (tsuijigaki) or a bamboo slat fence as the barrier; tiled-roof gate and a small tea house or pagoda behind; a maple (momiji) with red/orange canopy and a cloud-pruned pine; stone lantern and bamboo water spout in the corners; ground is moss-green with a raked gravel strip along the front edge (wavy lines) and a few stepping stones. Ambient: blossom or maple leaves drifting (by season), gentle ripples on a small pond edge. Foreground prop: stone lantern or wooden bucket instead of the watering can.
- **Rural UK garden**: patchwork fields with hedgerow lines on gentle hills, a church spire on the horizon, a few sheep dots; the barrier is a dry-stone wall (backyard side walls too) with a timber gate; behind it a stone cottage with a chimney and a big oak; lusher, slightly cooler greens and softer, cloudier skies; stone-edged path and flowerbed edging; cottage-garden planters. Ambient: chimney smoke curl, drifting clouds a touch heavier, a robin or two on the wall occasionally. Foreground prop: galvanised watering can and a pair of wellies.
- **Urban backyard**: terrace houses with brick, windows, drainpipes and chimney pots over the fence, an apartment block skyline, power lines; the barrier is a tall timber close-board fence (panelled, with a gravel board) and neighbours' roofs; ground is a small lawn patch with concrete pavers around the bed; clutter props: wheelie bin, bike against the fence, barbecue, washing line. Ambient: string lights glowing at dusk and night, a cat on the fence sometimes, a lit window or two at night. Foreground prop: a plastic watering can and a pot plant.

## Architecture
- `SceneTheme` enum in WeedsArt (`farm, japanese, ruralUK, urban`; `displayName`, `blurb`), carried like `SceneStyle`: `GardenSceneView(..., theme:)` -> `SceneContent` -> `SceneCanvas(theme:)`. Default `.farm`, so every existing caller keeps working.
- `SceneCanvas` draw entry points dispatch on theme instead of calling the farm functions directly (SceneView.swift lines around 257-312: sky, clouds, hills, lawn, backyard back, fence, side fences, foreground). Each theme implements the same set of hooks in its own file: `drawThemeSky/Clouds/Horizon/Ground/Barrier/BackdropProps/SideBarriers/Foreground/Ambient`. Farm's implementation wraps the current functions unchanged (`SceneBackdrop.swift`, `SceneBackyard.swift`, `SceneOverlay.swift`).
- Barriers: generalise `FenceFrame` (SceneBackdrop.swift) into `BarrierFrame` with a style (railFence, bambooSlat, stoneWall, drystoneWall, timberPanel) built on the shared `Camera.upright` projection so back and side barriers meet at one corner post/pillar exactly as the fence does today (keep the corner-join and vanishing-point tests, add them for each barrier type). All heights use `upright(...)`: verticals vertical, lines to the vanishing point.
- Palette: `ScenePalette.resolve(...)` gains an optional theme parameter that nudges grass, foliage, sky saturation and soil per theme (Japanese: mossier and cooler; UK: lusher and greyer; urban: duller grass). Real weather, seasons and darkness still drive everything.
- Ambient: `SceneMotion.Frame` already supplies time and wind; ambient drawing (`drawThemeAmbient`) uses it for drifting petals, smoke, string-light twinkle. Night/dusk glow draws in the weather-overlay pass so it stays lit under the darkness overlay (the moth glow uses the same trick).
- Setting: `AppSettings.sceneTheme` (key `sceneTheme`, default `.farm`), a "Garden theme" picker in `SettingsView.swift` next to "Garden bed" and "Scene view", each row with a small live preview swatch (a tiny `GardenSceneView` of an empty bed at ~96x72, or a cached image), wired through `GardenView.gardenScene` to the scene view and to the music.
- Music: `GardenMood` (GardenMusic.swift) gains `theme`; `MusicComposer` / `PhraseStyle` pick scale, voices and busyness per theme, and `GardenSynth.swift` gets the new voices. Japanese = today's koto, flute and drone (it already is the Japanese-garden sound). Because that is what plays now, Farm needs its own sound: a gentle fingerpicked acoustic-guitar feel in a major pentatonic. Rural UK: soft piano with a drone/pad in a folk mode (Dorian or Mixolydian). Urban: warm electric-piano chords with a soft pad and light pulse. Same rules as today: deterministic per seed, weather and time-of-day shaping speed and volume. Switching theme crossfades the music (`GardenMusic.setMood` path). Add tests in the style of `GardenMusicTests.swift`.

## Order of work
1. **Plumbing and Farm refactor** (one agent, sequential): `SceneTheme`, hooks, `BarrierFrame`, setting and picker (labels only at first), music `theme` field passed through (no new sound yet). Farm renders pixel-identical to today (render before/after compare for both views, day/dusk/night, all four beds). Tests green.
2. **Themes in parallel, one agent each, own file each**: `SceneThemeJapanese.swift`, `SceneThemeUK.swift`, `SceneThemeUrban.swift` (+ their barrier style). Each agent renders both views, day/dusk/night, plus planter boxes and soil patch, views the PNGs and iterates; checks that the bed, plants, visitors, fence corners and taps are unaffected and that the backdrop never overlaps the bed.
3. **Ambient and foreground props** per theme (petals, smoke, string lights, creatures on walls).
4. **Music per theme** (voices in `GardenSynth`, composer styles, tests), then the settings picker previews.
5. **Verify and polish**: full suite, build with the `Weeds` scheme, run the app switching themes live with weather, check CPU (ambient effects capped), check dusk and night glow, and tune.

## Verification
- `cd WeedsCore && swift test --scratch-path ~/Library/Caches/weeds-build` (new theme tests: Farm unchanged, barrier corner joins and vanishing points for every barrier, setting round trip, mood/theme music determinism).
- Render sheets in `~/Library/Caches/weeds-renders/themes/` (theme x view x light x two beds) and look at every one, zooming on corners and seams.
- Build and run the app via the `Weeds` scheme: switch theme in Settings with plants in the garden; confirm taps, planting, visitors and the book work under each theme; confirm music changes and fades.

## Risks
- Art quality: buildings and trees in a flat style take iteration; the Farm art is the style bar. Budget a visual review loop per theme.
- Urban and UK need fences/walls taller than the bed frames: keep clear of the planter box front-board depth sorting and of the visitors' flight paths (they enter from the edges).
- Performance: ambient effects must stay light (capped particle counts) at 30 fps.
