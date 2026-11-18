import SwiftUI
import DharmaGardenCore

/// The planting patch on the lawn: one organic soil shape with a soft edge, moisture shading from the soil grid,
/// a darker rim, the golden-hour edge, a few crumbs, plant shadows, feedback rings and the selection and seed
/// markers. Everything is projected through the same camera as the plants, so it agrees with taps. The other bed
/// styles (grid, mounds, planter boxes) are drawn in ScenePatchStyles.swift.
extension SceneCanvas {
    /// One soil grid cell on the canvas: its projected corners and its moisture.
    typealias SoilCell = (quad: [CGPoint], moisture: Double)

    /// Soil colour: dark and rich when wet, pale and dry when low on moisture (0...100).
    static func soilColour(_ palette: ScenePalette, moisture: Double) -> RGB {
        let dry = SceneColour.lerp(palette.soil, RGB(0.86, 0.74, 0.56), 0.4)
        let wet = SceneColour.scaled(palette.soil, 0.72)
        return SceneColour.lerp(dry, wet, moisture / 100)
    }

    /// A paler, drier earth used to lighten the soil in planter boxes.
    static let paleEarth = RGB(0.5, 0.38, 0.26)

    /// Soil colour under a plant's mound (FlowerArt's `soilColor`/`soilShade`), so the mound blends into the soil.
    static func moundColours(_ palette: ScenePalette, moisture: Double) -> (soil: Color, shade: Color) {
        let soil = soilColour(palette, moisture: moisture)
        return (SceneColour.color(soil), SceneColour.color(SceneColour.scaled(soil, 0.78)))
    }

    /// The soil patch's edge in ground coordinates: the outline of the plot's one oval region.
    static func patchOutline(_ plot: PlotShape, samples: Int = 72) -> [GroundPoint] {
        outline(of: plot.regions[0], samples: samples)
    }

    /// The edge of one plantable region in ground coordinates. Each direction is searched out to the region's own
    /// edge test, so the outline is exactly where planting is allowed, wobble included.
    static func outline(of region: BedRegion, samples: Int = 72) -> [GroundPoint] {
        (0..<samples).map { k in
            let theta = Double(k) / Double(samples) * 2 * Double.pi
            let cu = cos(theta), sv = sin(theta)
            var inside = 0.0, outside = 1.6
            for _ in 0..<32 {
                let mid = (inside + outside) / 2
                let p = GroundPoint(x: region.centre.x + mid * region.halfWidth * cu,
                                    y: region.centre.y + mid * region.halfHeight * sv)
                if region.edgeDistance(p) >= 0 { inside = mid } else { outside = mid }
            }
            return GroundPoint(x: region.centre.x + inside * region.halfWidth * cu,
                               y: region.centre.y + inside * region.halfHeight * sv)
        }
    }

    /// A closed path through `pts`.
    static func polygon(_ pts: [CGPoint]) -> Path {
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        for q in pts.dropFirst() { path.addLine(to: q) }
        path.closeSubpath()
        return path
    }

    /// Points pushed away from `centre` by factor `f`.
    static func scaled(_ pts: [CGPoint], by f: CGFloat, about centre: CGPoint) -> [CGPoint] {
        pts.map { CGPoint(x: centre.x + ($0.x - centre.x) * f, y: centre.y + ($0.y - centre.y) * f) }
    }

    /// Points moved by a fixed offset on the canvas.
    static func shifted(_ pts: [CGPoint], dx: CGFloat = 0, dy: CGFloat = 0) -> [CGPoint] {
        pts.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
    }

    /// Points pushed `px` away from the centre of the quad, so neighbouring quads overlap slightly.
    static func padded(_ quad: [CGPoint], by px: CGFloat) -> [CGPoint] {
        let c = mean(quad)
        return quad.map { q in
            let dx = q.x - c.x, dy = q.y - c.y
            let len = max(1e-9, (dx * dx + dy * dy).squareRoot())
            return CGPoint(x: q.x + dx / len * px, y: q.y + dy / len * px)
        }
    }

    /// Mean moisture of the soil cells, or the starting moisture when there are none.
    static func meanMoisture(_ cells: [SoilCell]) -> Double {
        cells.isEmpty ? SoilField.startingMoisture : cells.reduce(0) { $0 + $1.moisture } / Double(cells.count)
    }

    /// Canvas point of a point on the bed's soil: the lawn plus `soilLift`, plus `height` above that. Everything that
    /// sits on the soil (moisture, crumbs, shadows, rings, plants) goes through here.
    func ground(_ g: GroundPoint, height: Double = 0) -> CGPoint {
        lawn(g, height: height + soilLift)
    }

    /// Canvas point of a point on the lawn, `height` above it. Planter walls and rims use this, so they stay put
    /// while the soil inside them is lifted.
    func lawn(_ g: GroundPoint, height: Double = 0) -> CGPoint {
        let q = camera.uprightGroundPoint(x: g.x, y: g.y, height: height)
        return p(q.x, q.y)
    }

    /// A circle on the ground around `point`, projected: a closed polyline in canvas points.
    func groundCircle(_ point: GroundPoint, radius: Double, steps: Int = 40) -> [CGPoint] {
        (0..<steps).map { k in
            let t = Double(k) / Double(steps) * 2 * Double.pi
            return ground(GroundPoint(x: point.x + radius * cos(t), y: point.y + radius * sin(t)))
        }
    }

    /// The plantable regions on the canvas, one subpath each, for clipping.
    func patchPath(_ plot: PlotShape) -> Path {
        var path = Path()
        for region in plot.regions {
            path.addPath(Self.polygon(Self.outline(of: region).map { ground($0) }))
        }
        return path
    }

    /// Runs `body` with the canvas clipped to `path`, then restores the clip.
    func clipped(to path: Path, _ body: () -> Void) {
        let saved = ctx
        ctx.clip(to: path)
        body()
        ctx = saved
    }

    /// Soil grid cells whose centres pass `inside`, as canvas quads with their moisture. `pad` pushes each quad's
    /// corners out a little (in points) so neighbouring quads overlap and no hairline shows between them.
    func soilCells(_ garden: Garden, pad: CGFloat = 0, inside: (GroundPoint) -> Bool) -> [SoilCell] {
        var cells: [SoilCell] = []
        let cols = Double(SoilField.columns), rows = Double(SoilField.rows)
        garden.soil.forEachCell { c, r, centre, moisture in
            guard inside(centre) else { return }
            let x0 = Double(c) / cols, x1 = Double(c + 1) / cols
            let y0 = Double(r) / rows, y1 = Double(r + 1) / rows
            var quad = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)].map { ground(GroundPoint(x: $0.0, y: $0.1)) }
            if pad > 0 { quad = Self.padded(quad, by: pad) }
            cells.append((quad: quad, moisture: moisture))
        }
        return cells
    }

    /// Paints soil cells as one blurred layer, so the moisture reads as soft patches with no cell edges. `lighten`
    /// mixes the soil toward a paler earth (0 for the bed's own soil, up to 1 for the lightest).
    func paintMoisture(_ cells: [SoilCell], blur: CGFloat, lighten: Double = 0) {
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: blur))
            for cell in cells {
                let soil = Self.soilColour(palette, moisture: cell.moisture)
                let colour = SceneColour.color(SceneColour.lerp(soil, Self.paleEarth, lighten))
                layer.fill(Self.polygon(cell.quad), with: .color(colour))
            }
        }
    }

    /// Draws the bed for the plot's style, then the crumbs, the plant shadows, the feedback rings and the selection
    /// marker. Plants and weeds are drawn separately, depth sorted, on top; planter boxes also draw their front
    /// boards in that order (see `SceneContent`).
    func drawPatch(_ garden: Garden, rings: [ActiveRing], selected: GroundPoint?,
                   ghost: (point: GroundPoint, valid: Bool)?) {
        let plot = garden.plot
        switch plot.style {
        case .soilPatch: drawSoilPatch(garden)
        case .grid: drawGridBed(garden)
        case .mounds: drawMounds(garden)
        case .plantersBoxes: drawPlanterBoxesBehind(garden)
        }

        // 5. A few crumbs: small darker specks placed deterministically inside the plot.
        drawCrumbs(plot)

        // 6. Plant shadows from the sun, clipped to the plantable regions so none spill onto the lawn.
        if let sun = palette.sun, let dir = SceneLighting.shadowDirection(for: sun) {
            let opacity = SceneLighting.shadowOpacity(for: sun)
            clipped(to: patchPath(plot)) {
                for plant in garden.plants {
                    drawPlantShadow(plant, direction: dir, opacity: opacity, elevation: sun.elevationDegrees)
                }
            }
        }

        // 7. Feedback rings, then the selection and seed markers (plants are drawn over all of these).
        for ring in rings {
            drawRing(ring)
        }
        if let s = selected {
            let ring = groundCircle(s, radius: 0.03)
            stroke(ring + [ring[0]], width: 2.5, Color(hex: 0xFFF2C2).opacity(0.7))
        }
    }

    /// The soil patch: its one oval region, with moisture from the cells inside it.
    private func drawSoilPatch(_ garden: Garden) {
        let plot = garden.plot
        let edge = Self.patchOutline(plot).map { ground($0) }
        let cells = soilCells(garden) { plot.contains($0) }
        drawSoilBody(edge: edge, cells: cells, mean: Self.meanMoisture(cells))
    }

    /// The soil body of a bed whose edge is `edge`: a soft halo, a flat base colour with the moisture cells blurred
    /// over it, a darker rim and the golden-hour edge on the side facing the sun.
    func drawSoilBody(edge: [CGPoint], cells: [SoilCell], mean: Double) {
        let patch = Self.polygon(edge)
        let centre = Self.mean(edge)
        let rim = SceneColour.color(SceneColour.scaled(palette.soil, 0.5))

        // 1. Soft edge: a faint darker halo just past the patch, blurred so it fades into the lawn.
        let halo = Self.polygon(Self.scaled(edge, by: 1.025, about: centre))
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 0.008 * unit))
            layer.fill(halo, with: .color(rim.opacity(0.28)))
        }

        // 2. The soil: a flat base colour, then the moisture grid blurred into soft patches, clipped to the edge.
        fill(edge, SceneColour.color(Self.soilColour(palette, moisture: mean)))
        // The clip sits outside the blurred layer: a clip inside the layer would cut off the blur.
        clipped(to: patch) { paintMoisture(cells, blur: 0.012 * unit) }

        // 3. Rim: a soft darker band just inside the edge, then a fine line on the edge itself.
        // The inner rim band is kept inside the patch by an outer clip.
        clipped(to: patch) {
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 0.01 * unit))
                layer.stroke(patch, with: .color(rim.opacity(0.35)), lineWidth: 0.035 * unit)
            }
        }
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 0.002 * unit))
            layer.stroke(patch, with: .color(rim.opacity(0.5)), lineWidth: 0.006 * unit)
        }

        // 4. Golden hour: the stretch of edge that faces the sun catches warm light.
        if let sun = palette.sun, let dir = SceneLighting.shadowDirection(for: sun), sun.warmth > 0 {
            let toSun = (x: -dir.x, y: -dir.y)
            clipped(to: patch) {
                ctx.drawLayer { layer in
                    layer.addFilter(.blur(radius: 0.008 * unit))
                    for i in edge.indices {
                        let a = edge[i], b = edge[(i + 1) % edge.count]
                        let mid = CGPoint(x: (a.x + b.x) / 2 - centre.x, y: (a.y + b.y) / 2 - centre.y)
                        let len = max(1e-9, hypot(Double(mid.x), Double(mid.y)))
                        let facing = max(0, Double(mid.x) / len * toSun.x + Double(mid.y) / len * toSun.y)
                        let strength = 0.8 * sun.warmth * facing * facing
                        guard strength > 0.02 else { continue }
                        var seg = Path()
                        seg.move(to: a)
                        seg.addLine(to: b)
                        layer.stroke(seg, with: .color(Color(hex: 0xFFD08A).opacity(strength)), lineWidth: 0.04 * unit)
                    }
                }
            }
        }
    }

    /// The seed preview's footprint: a green ring where the seed can land, red where it cannot. Drawn above the
    /// plants (see `GardenSceneView`), so it stays visible among them.
    func drawGhostMarker(_ point: GroundPoint, valid: Bool) {
        let colour = valid ? Color(hex: 0xD6F2B0) : Color(red: 1, green: 0.4, blue: 0.36)
        let ring = groundCircle(point, radius: Tuning.sowSpacing)
        fill(ring, colour.opacity(0.14))
        stroke(ring + [ring[0]], width: 2.5, colour.opacity(0.9))
    }

    /// The mean of a set of canvas points.
    static func mean(_ pts: [CGPoint]) -> CGPoint {
        guard !pts.isEmpty else { return .zero }
        let n = CGFloat(pts.count)
        return CGPoint(x: pts.reduce(0) { $0 + $1.x } / n, y: pts.reduce(0) { $0 + $1.y } / n)
    }

    /// A few darker crumbs on the soil, placed deterministically from fixed seeds.
    private func drawCrumbs(_ plot: PlotShape) {
        let crumb = SceneColour.color(SceneColour.scaled(palette.soil, 0.6))
        var placed = 0
        var k: UInt64 = 0
        while placed < 24 && k < 240 {
            let p = GroundPoint(x: 0.1 + 0.8 * unitHash(0xC2B, 2 * k), y: 0.1 + 0.8 * unitHash(0xC2B, 2 * k + 1))
            k += 1
            guard plot.contains(p, inset: 0.03) else { continue }
            placed += 1
            let c = ground(p)
            let s = CGFloat(camera.scale(atGroundY: p.y))
            ellipse(c, 0.012 * unit * s, 0.006 * unit * s, crumb.opacity(0.85))
        }
    }

    /// One feedback ring: it spreads out on the soil and fades. Watering also tints the soil a little.
    private func drawRing(_ ring: ActiveRing) {
        let t = min(1, max(0, ring.progress))
        let eased = 1 - (1 - t) * (1 - t)
        let radius = ring.maxRadius * (0.2 + 0.8 * eased)
        let fade = 1 - t
        let tint = Self.ringTint(ring.kind)
        // A furrow is just its lines. The tool actions keep a faint ring so the reach still shows.
        if ring.kind == .furrow {
            drawToolAction(ring, pass: .ground)
            return
        }
        let strength = [.aerate, .seasol, .fertilise].contains(ring.kind) ? 0.4 : 1.0
        let pts = groundCircle(ring.point, radius: radius)
        if ring.kind == .water {
            fill(pts, SceneColour.color(tint).opacity(0.12 * fade))
        }
        stroke(pts + [pts[0]], width: max(1.2, 0.003 * unit), SceneColour.color(tint).opacity(0.8 * fade * strength))
        drawToolAction(ring, pass: .ground)
        if ring.kind == .spot {
            // Sparkle: short bright ticks around the ring, turning as it fades.
            let c = ring.point
            for k in 0..<6 {
                let a = Double(k) / 6 * 2 * Double.pi + t * 1.5
                let from = ground(GroundPoint(x: c.x + cos(a) * radius * 1.1, y: c.y + sin(a) * radius * 1.1))
                let to = ground(GroundPoint(x: c.x + cos(a) * radius * 1.5, y: c.y + sin(a) * radius * 1.5))
                stroke([from, to], width: max(1.5, 0.004 * unit), Color(hex: 0xFFD84A).opacity(fade))
            }
        }
    }

    static func ringTint(_ kind: SceneRipple.Kind) -> RGB {
        switch kind {
        case .water: RGB(0.6, 0.82, 1.0)
        case .plant: RGB(1.0, 0.9, 0.5)
        case .pull: RGB(0.78, 0.62, 0.42)
        case .pick: RGB(1.0, 0.85, 0.55)
        case .spot: RGB(1.0, 0.84, 0.3)
        case .aerate: RGB(0.62, 0.45, 0.3)
        case .seasol: RGB(0.35, 0.62, 0.45)
        case .fertilise: RGB(0.7, 0.85, 0.35)
        case .furrow: RGB(0.4, 0.28, 0.18)
        }
    }

    /// A soft flat shadow for one planted spot: a skewed ellipse leaving the plant's soil mound along the shadow
    /// direction, plus a faint contact shadow around the mound. Two layers stand in for softness.
    /// Size follows the plant's growth and the scale at its depth. The mound (about 0.35 of a plant wide) covers
    /// the start of the shadow, so the visible part starts just beyond it.
    private func drawPlantShadow(_ plant: Plant, direction d: (x: Double, y: Double), opacity: Double, elevation: Double) {
        let base = ground(plant.position)
        let scale = camera.scale(atGroundY: plant.position.y)
        let side = unit * CGFloat(SceneLighting.plantSizeFraction * scale)
        let grow = SceneLighting.plantGrowth(progress: plant.progress, isSeedHead: plant.lifeStage == .seedHead)
        let species = Species.of(plant.flower)
        let height = side * CGFloat(species.maxHeight * grow)
        let length = height * CGFloat(SceneLighting.shadowLength(elevationDegrees: elevation))
        let canopy = side * CGFloat(species.canopy * (0.7 + 0.3 * grow))   // half width of the leaf spread
        let start = side * 0.26                                 // where the visible shadow leaves the mound
        var reach = max(length, canopy * 1.2)                  // total length from the stem
        // A shadow cast away from the viewer stops at the fence: the fence is a wall, not ground.
        if d.y < 0 {
            let worldX = Camera.groundWorld(x: plant.position.x, y: plant.position.y).x
            let fenceY = p(0, camera.project(x: worldX, z: SceneCanvas.fenceZ).y).y
            let gap = base.y - fenceY
            if gap < (start + reach) * CGFloat(-d.y) { reach = max(0, gap / CGFloat(-d.y) - start) }
        }
        let major = reach / 2
        let minor = canopy * 0.5
        let centre = CGPoint(x: base.x + CGFloat(d.x) * (start + major), y: base.y + CGFloat(d.y) * (start + major))
        // Near-black warm ink: it has to read on dark soil.
        let ink = Color(red: 0.1, green: 0.07, blue: 0.05)

        // Strengthened from the first pass so shadows read in full sun (the opacity itself follows sun intensity).
        fill(Self.ellipse(centre: centre, direction: d, major: major * 1.15, minor: minor * 1.35), ink.opacity(0.12 * opacity))
        fill(Self.ellipse(centre: centre, direction: d, major: major, minor: minor), ink.opacity(0.28 * opacity))
        // Contact shadow: a small soft rim at the stem's foot, so it does not read as a disc under each plant.
        let contact = CGPoint(x: base.x + CGFloat(d.x) * side * 0.03, y: base.y + CGFloat(d.y) * side * 0.03)
        fill(Self.ellipse(centre: contact, direction: d, major: side * 0.3, minor: side * 0.15), ink.opacity(0.2 * opacity))
    }

    /// Polygon approximating an ellipse whose major axis points along `direction`.
    static func ellipse(centre c: CGPoint, direction d: (x: Double, y: Double), major: CGFloat, minor: CGFloat,
                        steps: Int = 24) -> [CGPoint] {
        let perp = (x: -d.y, y: d.x)
        return (0..<steps).map { k in
            let t = Double(k) / Double(steps) * 2 * Double.pi
            let a = CGFloat(cos(t)) * major, b = CGFloat(sin(t)) * minor
            return CGPoint(x: c.x + CGFloat(d.x) * a + CGFloat(perp.x) * b,
                           y: c.y + CGFloat(d.y) * a + CGFloat(perp.y) * b)
        }
    }
}
