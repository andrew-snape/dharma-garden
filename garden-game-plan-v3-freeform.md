# Plan v3: free-form planting (no grid)

## Decisions (from the user)
- One big soft-edged patch of soil on the lawn; plant anywhere inside it.
- Watering: a soft circle around where you tap; the soil darkens in a spreading patch.
- Crowding: soft. Plants can sit close, crowded ones grow a bit slower; seeds cannot land on top of another plant.
- DharmaGarden: pop up at random spots on the soil, tap to pull, they slow nearby plants.
- First-person 45 degree view stays the default; the backyard style must keep working.

## New model (engine contract, save version 4; old saves reset)
- `GroundPoint { x: 0...1 left to right, y: 0...1 back to front }` on the ground plane of the patch.
- `Plant { id, flower, position, progress, bloomHoursElapsed, dryHours, frostUntil, plantSeed, isDead }` with the same computed life stage, fade, droop, stage, speedFactor as `Bed` today. Moisture is sampled from the soil under the plant.
- `Weed { id, position, ageHours }`: slows plants within a radius (more as it ages, capped).
- `SoilField`: a coarse moisture grid (for example 28 x 18 cells over the patch), values 0...100. Rain refills, heat and wind drain, as now. Watering adds moisture in a soft circle. Cells outside the patch shape are ignored.
- `PlotShape`: an organic oval (centre and radii, slight wobble) that defines where plants, weeds and soil can exist.
- `Garden`: plants, weeds, soil, plot, seeds, coins, lastSimulatedAt, nextID, version 4.
- Crowding: each neighbour within roughly 1.2 plant-widths reduces growth up to a capped 25 percent.
- Self-sowing: after the seed-head period a plant scatters 0 to 3 volunteer seedlings at deterministic random points within a short radius, only inside the plot, not on top of another plant.
- Actions: `sow(flower, at:)`, `water(at:, radius:)`, `pullWeed(at:)` (nearest within reach), `harvest(at:)` (nearest ready plant within reach). All deterministic; catch-up still hourly and deterministic.
- Maximum plants about 60 so performance stays fine.

## Rendering and input
- `Camera` gets the inverse: screen point to `GroundPoint` (and back), keeping drift, parallax and both styles.
- Soil patch drawn as one organic shape with a soft edge and moisture shading from the `SoilField` (darker where wet), plus the golden-hour highlight.
- Plants and weeds drawn depth sorted by y at their own positions; size from perspective scale; shadows as today.
- Taps: tool plant puts a seed where you tap (with a ghost preview and a not-allowed hint outside the patch or on top of a plant); water shows a spreading ring and darkening soil; weed pulls the nearest weed; pick takes the nearest ready plant. Reach radius scales with perspective so back-row plants stay tappable.

## Order of work
1. Engine rewrite and tests (Plant, Weed, SoilField, PlotShape, actions, self-sow, crowding, DebugTools, ReminderText, shop functions, save v4).
2. Camera inverse, soil patch, depth-sorted plants, input and feedback in the app, both scene styles, render checks.
3. Balance pass (how many plants fit, crowding and watering radii), debug panel updates, final verification.

## Constraint
Start only after the music wave finishes, because both touch App/GardenView.swift and App/SettingsView.swift.

## What shipped (wave 9C)
- The app runs on the free-form engine only. The grid code (Bed, the old Garden and GardenEngine, the bed scene
  code, Camera.project(row:col:)) is gone. The names are final: `Garden`, `GardenEngine`, `DebugTools`,
  `ReminderText`, `Tuning`. Save version is 4; older saves are discarded.
- Input: a tap uses the armed tool at its ground point (water, weed, pick, or plant a seed). A seed on a spot that
  is not allowed does nothing and flashes the ghost red. Dragging with the water tool sprinkles a spot every 0.04
  ground units. Hovering shows the seed ghost, using the same rule as planting (`GardenEngine.canPlant`).
  Feedback rings are kept in the view and pruned after 2 seconds.
- The weed tool also clears a withered plant when no weed is in reach. Planting over a withered plant replaces it.
- Look: the patch is about 35 percent wider on screen (`Camera.patchSide` 5.4), plants are 20 percent smaller,
  the stem mound is a tiny soft dab, shadows are a little stronger in full sun, and weeds are low jagged rosettes in
  a duller yellow-green (small yellow dots when older).
- Balance: weeds spawn at half the old rate (0.64 per check on the default plot) with a cap of 12.
- Debug panel: +1 day, +1 week, +30 days, +90 days, auto-water, Scatter plants (20), reset. The summary line counts weeds.
- Not yet checked by a person: the feel of hover, drag sprinkling and the weed tool in the running app.
