# Plan v4: choice of garden bed look

## Decisions (from the user)
- Four looks, chosen in Settings like "Scene view": **Soil patch** (today's), **Soil mounds**, **Grid layout**, **Raised wooden planter boxes**.
- Switchable any time, free. Plants stay where they are when they still fit; the rest are moved to the nearest free spot.
- Grid layout = a tidy rectangular bed with **free planting** (no snapping) and **no visible lines anywhere**: no cell edges, no seams, no drawn grid. It should look like real tilled soil, only rectangular.
- Look only: no growth or water rules change (optional balance idea at the end, off by default).

## Model (DharmaGardenCore)
- `BedStyle` enum: `soilPatch, mounds, grid, plantersBoxes` (String raw, CaseIterable, Codable, Sendable; displayName, blurb).
- `PlotShape` (Garden.swift) gains `style: BedStyle = .soilPatch` and keeps its API (`contains`, `edgeDistance`, `point(seed:inset:)`, `area`) so the engine, weed spawning, volunteers, `canPlant` and tests keep working. Internally it asks a list of **regions** for the style:
  - soilPatch: the existing wobbly oval.
  - mounds: 4 overlapping oval mounds (fixed centres/radii, slightly different sizes), leaving lawn between them.
  - grid: one rounded rectangle, about 0.84 x 0.62 of the unit square (area close to the oval so `maxPlants` and weed rate stay balanced).
  - plantersBoxes: 3 rectangles (two long, one short, or 2x2 short ones) with walkable lawn gaps. Plantable area is the **inside** of each frame (inset by plank thickness).
  Each region supplies `edgeDistance` (signed, positive inside) so `contains(inset:)` works unchanged; `edgeDistance` of the plot is the max over regions.
- `point(seed:inset:)` samples within the bounding box of the regions instead of the oval box, and `area` is the sum of region areas. Weed spawn scaling (`area / PlotShape().area`) already uses `area`.
- Decoding: `style` via `decodeIfPresent` (default `.soilPatch`) so old saves load with no version bump.
- `GardenEngine.setBedStyle(_ style: BedStyle, in g: inout Garden)`: swaps the plot, then for every plant and weed outside the new regions finds the nearest valid point (search outward from the object, respecting `sowSpacing`). A plant with nowhere to go is removed and its seed packet is returned to `seedStock` (weeds just vanish). Deterministic; covered by tests.
- `SoilField` stays one unit-square grid; cells outside the regions are already ignored.

## Rendering (DharmaGardenArt)
Keep everything in `ScenePatch.swift`'s pipeline (projected through `Camera.groundPoint(x:y:height:)`), split by style into `ScenePatch+Styles.swift` (new) so the file stays readable. `drawPatch` dispatches on `garden.plot.style`.
- **Soil patch:** unchanged.
- **Mounds:** per mound, a domed look in flat style: soil body with moisture shading (reuse the blurred cell fills clipped to each mound), a lighter crest highlight on the sun side, a darker lower rim, a crescent shadow on the lawn on the side away from the sun (reuse `SceneLighting.shadowDirection`), a few crumbs/pebbles. Plants are not lifted; the dome is shading only, so taps and depth order stay simple.
- **Grid:** a rectangle of soil with softly rounded corners and a faint darker rim. **No lines:** the moisture cells are painted over a solid base fill, blurred, and every cell quad is expanded by a hair (about 0.5 px) so anti-aliasing seams never show; the existing blur already merges them. Add subtle hand-tilled texture instead of lines (a few long, very low-contrast soft furrow strokes along the rows direction with irregular breaks and varying length, plus the crumbs). Test: render and check for any straight repeating line at 2x zoom.
- **Planter boxes:** each box is drawn in three passes so plants can sit inside it:
  1. Behind plants: back wall inner face (planks in dark wood), the soil (moisture shading, slightly darker near the walls), and the left/right inner faces.
  2. Plants and weeds as now (depth sorted).
  3. In front of plants: the front wall outer face (planks with grain lines and nail dots, lighter on the sun side) plus the top rim edge, so the lower leaves of back-row plants tuck behind the front board. Corner posts, a soft contact shadow on the lawn, and a thin highlight on the top edge.
  Box height around 0.045 of ground width (`height:` parameter of `Camera.groundPoint`). Plant ground positions are unchanged; soil level is raised by the same height in the draw only. Wood colours: warm cedar tones from the palette and tinted by `ScenePalette` light (dusk/night/overcast), plus a darker wet look near the soil line when moisture is high.
- `SceneView.swift`: add the "front of plants" pass after the depth-sorted plants (the ghost marker stays on top). Hit-testing uses `contains`, so taps on planks do nothing.
- Plant shadows are already clipped to the patch path; clip to the combined region path instead (`patchPath` helper returning a union path).

## App
- `App/AppSettings.swift`: no new setting needed beyond the live garden (style lives in `Garden.plot.style` because it affects rules). `App/SettingsView.swift`: a "Garden bed" picker with four options and a small preview swatch each (drawn with the same art functions on a tiny canvas), calling `store.apply { GardenEngine.setBedStyle($0, in: &$1) }`.
- Show a one-line notice if plants had to be moved or returned as seeds.

## Order of work
Wait for the visitor core (Garden.swift, GardenEngine.swift) to land first, since both plans touch those files.
1. Core: `BedStyle`, regions, `PlotShape` generalisation, `setBedStyle`, tests (contains/inset per style, `point` always inside, `area`, relocation, seed refund, old-save decode, existing plot tests still pass).
2. Art, one style at a time with PNG render checks in light, dusk and night: grid (no-line check) → mounds → planter boxes (incl. front-wall pass and the plants-behind-front-board check).
3. Settings picker, preview swatches, switch notice.
4. Debug panel: style buttons plus Scatter plants to test crowding in each shape.
5. Balance: `maxPlants` and weed counts per style; confirm tap targets and the camera drift look right near box walls.

## Verification
- `cd DharmaGardenCore && swift test --scratch-path ~/Library/Caches/weeds-build`.
- Render PNGs (extend `SceneStyleRenderTests`) for each style x both scene styles (first person and backyard) x day/dusk/night, view them, zoom on the grid bed to confirm no lines.
- Run the app (build outside Documents; clean stale DerivedData): switch styles with plants in the garden, confirm they relocate, taps/water/weed/pick work in each shape, saves survive relaunch.

## Optional later (off by default)
Light balance character: boxes drain a little slower (0.85x), mounds a little faster (1.15x), grid neutral. Not part of this plan unless asked.
