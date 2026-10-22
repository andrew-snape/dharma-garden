import SwiftUI
import DharmaGardenCore

/// The bed styles besides the soil patch: a grid of soil, soil mounds and raised timber planter boxes. They share
/// the soil patch's camera, lighting and moisture cells. A planter box is drawn in two parts around the plants: its
/// back part before them (`drawPlanterBoxesBehind`), and its front board after the plants that stand in front of it
/// (`drawPlanterBoxFront`, called in depth order from `SceneContent`). Mounds are domes built from stacked soil rings.
extension SceneCanvas {
    /// Height of a planter box's walls in world units: 0.075 of the ground width.
    static let planterHeight = 0.075 * Camera.patchSide
    /// How far the soil inside a planter box sits above the lawn, in world units: seven tenths of the wall height.
    /// The plants stand on it (see `SceneContent`), so the inside walls show as a band of timber above the soil.
    static let planterSoilLift = 0.7 * planterHeight
    /// How far the corner posts stand above the rim, as a fraction of the wall height.
    static let postRise = 0.3
    /// Width of a corner post in ground units: a little wider than a board, so the corners read as posts.
    static let postWidth = 0.04
    /// How high the top of a mound stands above the lawn, in world units (a low heap).
    static let moundHeight = 0.022 * Camera.patchSide
    /// How far a mound's foot spreads past its planting edge, as a factor, so the base feathers into the grass.
    static let moundFoot = 1.06
    /// Near-black warm ink for shadows, as on the plants.
    static let shadowInk = Color(red: 0.1, green: 0.07, blue: 0.05)

    /// The soil level for a plot: planter boxes lift their soil, mounds lift their tops, every other bed sits on the lawn.
    static func soilLift(for plot: PlotShape) -> Double {
        switch plot.style {
        case .plantersBoxes: planterSoilLift
        case .mounds: moundHeight
        case .soilPatch, .grid: 0
        }
    }

    /// Ground depth of each planter box's front board, in region order. Empty for the other styles.
    static func planterFrontDepths(_ plot: PlotShape) -> [Double] {
        guard plot.style == .plantersBoxes else { return [] }
        return plot.regions.map { $0.centre.y + $0.halfHeight + PlotShape.plankThickness }
    }

    /// Timber for the planters: a weathered, muted cedar. It is lit by the sun (brighter when it is strong, warmer near
    /// the horizon) and dimmed by the palette's darkness. `shade` scales it for each face.
    static func timber(_ palette: ScenePalette, shade: Double) -> RGB {
        let level = palette.sun.map { $0.isUp ? 0.62 + 0.38 * $0.intensity : 0.4 } ?? 0.5
        let warm = palette.sun.map { $0.warmth } ?? 0
        let weathered = SceneColour.lerp(RGB(0.5, 0.43, 0.35), RGB(0.6, 0.47, 0.34), warm)
        return SceneColour.scaled(weathered, level * (1 - 0.45 * palette.darkness) * shade)
    }

    /// The soil inside a planter: the bed's soil mixed toward a paler earth, so the boxes read lighter than the lawn's dark soil.
    static func lighterSoil(_ palette: ScenePalette, moisture: Double) -> RGB {
        SceneColour.lerp(soilColour(palette, moisture: moisture), paleEarth, 0.5)
    }

    /// Inside edges (x0, x1, y0, y1) of a planter's plantable region.
    private static func inner(_ r: BedRegion) -> (x0: Double, x1: Double, y0: Double, y1: Double) {
        (r.centre.x - r.halfWidth, r.centre.x + r.halfWidth, r.centre.y - r.halfHeight, r.centre.y + r.halfHeight)
    }

    /// Outside edges of a planter box: its inside grown by the plank thickness.
    private static func outer(_ r: BedRegion) -> (x0: Double, x1: Double, y0: Double, y1: Double) {
        let i = inner(r), t = PlotShape.plankThickness
        return (i.x0 - t, i.x1 + t, i.y0 - t, i.y1 + t)
    }

    /// The screen direction shadows fall toward, or nil when the sun gives no direct light.
    var shadowDir: (x: Double, y: Double)? {
        palette.sun.flatMap { SceneLighting.shadowDirection(for: $0) }
    }

    /// Where the eye is on the ground plane (x across, y back to front), from the camera's offset and distance. A box
    /// side shows only when the eye is on the outside of it (outer faces) or the inside of it (inner faces).
    var eyeGround: (x: Double, y: Double) {
        (camera.offset.x / Camera.patchSide + 0.5, camera.distance / Camera.patchSide + 0.5)
    }

    /// A flat quad on the lawn between two corners, lifted to `height` (the walls and rims of a planter).
    func flatQuad(_ x0: Double, _ x1: Double, _ y0: Double, _ y1: Double, height: Double = 0) -> [CGPoint] {
        [lawn(GroundPoint(x: x0, y: y0), height: height), lawn(GroundPoint(x: x1, y: y0), height: height),
         lawn(GroundPoint(x: x1, y: y1), height: height), lawn(GroundPoint(x: x0, y: y1), height: height)]
    }

    /// A flat quad on the planter's soil, at soil level (so it sits where the plants stand).
    func soilQuad(_ x0: Double, _ x1: Double, _ y0: Double, _ y1: Double) -> [CGPoint] {
        [ground(GroundPoint(x: x0, y: y0)), ground(GroundPoint(x: x1, y: y0)),
         ground(GroundPoint(x: x1, y: y1)), ground(GroundPoint(x: x0, y: y1))]
    }

    /// A vertical wall quad on the lawn from ground point `a` to `b`, rising from height `h0` to `h1`.
    func wallQuad(from a: GroundPoint, to b: GroundPoint, _ h0: Double, _ h1: Double) -> [CGPoint] {
        [lawn(a, height: h0), lawn(b, height: h0), lawn(b, height: h1), lawn(a, height: h1)]
    }

    /// A vertical face from ground point `a` to `b`, rising from `h0` to `h1`, made of `boards` stacked boards with a
    /// dark seam between each pair. Each board has its own tone and two faint grain lines, and the face is lit from the
    /// sun side. `lean` is positive when the sun is on the left, so the left end is the lit one.
    private func boardFace(from a: GroundPoint, to b: GroundPoint, _ h0: Double, _ h1: Double, shade: Double,
                           seed: UInt64, boards: Int, lean: Double) {
        for j in 0..<boards {
            let k0 = h0 + (h1 - h0) * Double(j) / Double(boards)
            let k1 = h0 + (h1 - h0) * Double(j + 1) / Double(boards)
            let tone = 0.9 + 0.2 * unitHash(seed, UInt64(j))
            let hi = SceneColour.color(Self.timber(palette, shade: shade * 1.08 * tone))
            let lo = SceneColour.color(Self.timber(palette, shade: shade * 0.88 * tone))
            let mid = (k0 + k1) / 2
            ctx.fill(Self.polygon(wallQuad(from: a, to: b, k0, k1)), with: .linearGradient(
                Gradient(colors: lean >= 0 ? [hi, lo] : [lo, hi]),
                startPoint: lawn(a, height: mid), endPoint: lawn(b, height: mid)))
            for g in 0..<2 {
                let hg = k0 + (k1 - k0) * (0.3 + 0.4 * Double(g) + 0.1 * unitHash(seed, UInt64(10 + 2 * j + g)))
                let phase = 6 * unitHash(seed, UInt64(20 + j))
                let pts = (0...6).map { s -> CGPoint in
                    let t = Double(s) / 6
                    let p = GroundPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                    return lawn(p, height: hg + 0.002 * sin(7 * t + Double(g) * 2 + phase))
                }
                stroke(pts, width: 0.0025 * unit, Self.shadowInk.opacity(0.16))
            }
            if j > 0 {
                stroke([lawn(a, height: k0), lawn(b, height: k0)], width: 0.0035 * unit, Self.shadowInk.opacity(0.45))
            }
        }
    }

    /// A corner post: a square upright of timber from lawn level to above the rim, standing on the footprint
    /// (x0, x1) by (y0, y1). It has a front face, a side face wherever the eye can see one (darker on the side away
    /// from the sun, as on the box walls) and a lighter flat cap.
    private func post(_ x0: Double, _ x1: Double, _ y0: Double, _ y1: Double, shade: Double) {
        let top = Self.planterHeight * (1 + Self.postRise)
        let lean = -(shadowDir?.x ?? 0)
        let eye = eyeGround
        // Sun on the left (lean positive): faces looking left are lit, faces looking right are in shade.
        if eye.x > x1 {
            let side = shade * (lean >= 0 ? 0.62 : 0.9)
            ctx.fill(Self.polygon(wallQuad(from: GroundPoint(x: x1, y: y0), to: GroundPoint(x: x1, y: y1), 0, top)),
                     with: .color(SceneColour.color(Self.timber(palette, shade: side))))
        }
        if eye.x < x0 {
            let side = shade * (lean >= 0 ? 0.9 : 0.62)
            ctx.fill(Self.polygon(wallQuad(from: GroundPoint(x: x0, y: y1), to: GroundPoint(x: x0, y: y0), 0, top)),
                     with: .color(SceneColour.color(Self.timber(palette, shade: side))))
        }
        ctx.fill(Self.polygon(wallQuad(from: GroundPoint(x: x0, y: y1), to: GroundPoint(x: x1, y: y1), 0, top)),
                 with: .color(SceneColour.color(Self.timber(palette, shade: shade))))
        // A lighter cap, so the top of the post reads against the rim.
        fill(flatQuad(x0, x1, y0, y1, height: top), SceneColour.color(Self.timber(palette, shade: shade * 1.25)))
    }

    // MARK: Grid

    /// The grid bed: one rounded rectangle of soil. The moisture is painted over a solid base and blurred, the cell
    /// quads are padded to overlap, and the furrows are faint, so no cell edge or grid line shows.
    func drawGridBed(_ garden: Garden) {
        let plot = garden.plot
        guard let region = plot.regions.first else { return }
        let edge = Self.outline(of: region, samples: 96).map { ground($0) }
        let cells = soilCells(garden, pad: 0.5) { plot.contains($0) }
        drawSoilBody(edge: edge, cells: cells, mean: Self.meanMoisture(cells))
        drawFurrows(region, edge: edge)
    }

    /// Hand-tilled texture: six soft, low-contrast furrows along the rows. Each is broken into runs of irregular length
    /// and wobbles a little. They stay off the centre line and are clipped to the bed.
    private func drawFurrows(_ region: BedRegion, edge: [CGPoint]) {
        let rows = 6
        let left = region.centre.x - region.halfWidth * 0.8, right = region.centre.x + region.halfWidth * 0.8
        var path = Path()
        for i in 0..<rows {
            let seed = 0x7F0 &+ UInt64(i) &* 0x101
            let y = region.centre.y - region.halfHeight * 0.7 + region.halfHeight * 1.4 * (Double(i) + 0.5) / Double(rows)
                + (unitHash(seed, 0) - 0.5) * 0.02
            var x = left + 0.08 * unitHash(seed, 1)
            var run: UInt64 = 2
            while x < right {
                let end = min(right, x + 0.1 + 0.25 * unitHash(seed, run))
                let steps = 6
                for s in 0...steps {
                    let t = Double(s) / Double(steps)
                    let gx = x + (end - x) * t
                    let p = ground(GroundPoint(x: gx, y: y + 0.004 * sin(gx * 17 + Double(i) * 2)))
                    if s == 0 { path.move(to: p) } else { path.addLine(to: p) }
                }
                x = end + 0.03 + 0.12 * unitHash(seed, run + 1)
                run += 2
            }
        }
        let furrow = SceneColour.color(SceneColour.scaled(palette.soil, 0.5))
        clipped(to: Self.polygon(edge)) {
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 0.004 * unit))
                layer.stroke(path, with: .color(furrow.opacity(0.16)),
                             style: StrokeStyle(lineWidth: 0.01 * unit, lineCap: .round, lineJoin: .round))
            }
        }
    }


    // MARK: Mounds

    /// Ring of ground points around `c`: the heap's outline scaled by `scale` about its centre.
    private func ringGround(_ base: [GroundPoint], _ c: GroundPoint, scale: Double) -> [GroundPoint] {
        base.map { GroundPoint(x: c.x + ($0.x - c.x) * scale, y: c.y + ($0.y - c.y) * scale) }
    }

    /// Canvas points of a ring at `height` above the lawn.
    private func ringPoints(_ ground: [GroundPoint], height: Double) -> [CGPoint] {
        ground.map { lawn($0, height: height) }
    }

    /// Soil heaps: each is a low dome of soil with an irregular outline, a lit crest on the sun side and a darker rim,
    /// its foot feathered into the lawn, with a soft shadow falling away from the sun. Every heap's shadow is drawn
    /// first, so no shadow lands on another heap.
    func drawMounds(_ garden: Garden) {
        let regions = garden.plot.regions
        let bases = regions.map { Self.outline(of: $0) }

        for (i, region) in regions.enumerated() {
            let foot = ringGround(bases[i], region.centre, scale: Self.moundFoot)
            if let dir = shadowDir, let sun = palette.sun {
                let cast = Self.polygon(Self.shifted(ringPoints(foot, height: 0),
                                                     dx: CGFloat(dir.x) * 0.05 * unit, dy: CGFloat(dir.y) * 0.05 * unit))
                ctx.drawLayer { layer in
                    layer.addFilter(.blur(radius: 0.012 * unit))
                    layer.fill(cast, with: .color(Self.shadowInk.opacity(0.32 * SceneLighting.shadowOpacity(for: sun))))
                }
            }
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 0.008 * unit))
                layer.fill(Self.polygon(ringPoints(foot, height: 0)), with: .color(Self.shadowInk.opacity(0.2)))
            }
        }

        for (i, region) in regions.enumerated() {
            drawMoundBody(region, base: bases[i], garden: garden)
            drawMoundDetail(region, base: bases[i], index: i)
        }
    }

    /// The dome itself: stacked rings of soil from the feathered foot up to the top, each a little smaller and higher
    /// than the one below and lighter toward the crest. The stack is blurred slightly, so the rings blend into one dome.
    /// The top is then painted with the moisture, a crest highlight on the sun side and a soft darkening at its rim.
    private func drawMoundBody(_ region: BedRegion, base: [GroundPoint], garden: Garden) {
        let cells = soilCells(garden, pad: 0.5) { region.edgeDistance($0) >= 0 }
        let soil = Self.soilColour(palette, moisture: Self.meanMoisture(cells))
        let foot = SceneColour.scaled(soil, 0.7)
        let crest = SceneColour.lerp(soil, RGB(1.0, 0.9, 0.75), 0.22)
        let steps = 12
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 0.005 * unit))
            for k in 0...steps {
                let t = Double(k) / Double(steps)
                let scale = Self.moundFoot - (Self.moundFoot - 1) * t
                let height = Self.moundHeight * (1 - (1 - t) * (1 - t))
                let colour = SceneColour.color(SceneColour.lerp(foot, crest, pow(t, 0.7)))
                layer.fill(Self.polygon(ringPoints(ringGround(base, region.centre, scale: scale), height: height)),
                           with: .color(colour))
            }
        }

        let top = ringGround(base, region.centre, scale: 1)
        let topPath = Self.polygon(top.map { ground($0) })
        clipped(to: topPath) {
            paintMoisture(cells, blur: 0.012 * unit)
            if let dir = shadowDir, let sun = palette.sun {
                let c = ground(region.centre)
                let rx = ground(GroundPoint(x: region.centre.x + region.halfWidth, y: region.centre.y)).x - c.x
                let ry = ground(GroundPoint(x: region.centre.x, y: region.centre.y + region.halfHeight)).y - c.y
                let centre = CGPoint(x: c.x - CGFloat(dir.x) * 0.3 * rx, y: c.y - CGFloat(dir.y) * 0.3 * ry)
                let light = Color(hex: 0xFFF0D0)
                ctx.fill(topPath, with: .radialGradient(
                    Gradient(colors: [light.opacity(0.3 * sun.intensity), light.opacity(0)]),
                    center: centre, startRadius: 0, endRadius: 1.1 * max(rx, ry)))
            }
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 0.012 * unit))
                layer.stroke(topPath, with: .color(SceneColour.color(foot).opacity(0.3)), lineWidth: 0.07 * unit)
            }
        }
    }

    /// Crumbs on the top of a heap, and at its foot a few grass tufts and pebbles. Placed from fixed seeds.
    private func drawMoundDetail(_ region: BedRegion, base: [GroundPoint], index: Int) {
        let dark = SceneColour.color(RGB(0.1, 0.07, 0.05)), light = SceneColour.color(RGB(0.7, 0.6, 0.5))
        for k in 0..<14 {
            let seed = UInt64(index) &* 0x2F &+ 0x700 &+ UInt64(k) &* 3
            let p = GroundPoint(x: region.centre.x + (2 * unitHash(seed, 0) - 1) * region.halfWidth * 0.85,
                                y: region.centre.y + (2 * unitHash(seed, 1) - 1) * region.halfHeight * 0.85)
            guard region.edgeDistance(p) >= 0.04 else { continue }
            let c = ground(p)
            let s = CGFloat(camera.scale(atGroundY: p.y))
            let size = 0.8 + 0.5 * unitHash(seed, 3)
            if unitHash(seed, 2) < 0.7 {
                ellipse(c, 0.010 * unit * s * size, 0.006 * unit * s, dark.opacity(0.4))
            } else {
                ellipse(c, 0.008 * unit * s * size, 0.005 * unit * s, light.opacity(0.5))
            }
        }

        let foot = ringGround(base, region.centre, scale: Self.moundFoot + 0.04)
        let grass = SceneColour.color(SceneColour.scaled(palette.grass, 0.75))
        let pebble = SceneColour.color(RGB(0.62, 0.56, 0.5))
        for k in 0..<9 {
            let seed = UInt64(index) &* 0x41 &+ 0x900 &+ UInt64(k) &* 5
            let i = min(foot.count - 1, Int(unitHash(seed, 0) * Double(foot.count)))
            let g = foot[i]
            let p = lawn(g)
            let s = CGFloat(camera.scale(atGroundY: g.y))
            if k % 3 == 2 {
                ellipse(p, 0.012 * unit * s, 0.008 * unit * s, pebble.opacity(0.9))
            } else {
                let h = 0.022 * unit * s * (0.8 + 0.4 * unitHash(seed, 1))
                for b in -1...1 {
                    let dx = CGFloat(b) * 0.006 * unit * s
                    let lean = CGFloat(unitHash(seed, UInt64(2 + b + 1))) * 0.004 * unit * s
                    stroke([p, CGPoint(x: p.x + dx + lean, y: p.y - h * CGFloat(0.7 + 0.3 * unitHash(seed, 5)))],
                           width: max(1, 0.003 * unit * s), grass)
                }
            }
        }
    }

    // MARK: Planter boxes

    /// Behind the plants: every box's contact shadow on the lawn, then each box's back part. All shadows come first, so
    /// no box's shadow lands on another box.
    func drawPlanterBoxesBehind(_ garden: Garden) {
        let regions = garden.plot.regions
        for region in regions { drawPlanterContactShadow(region) }
        for region in regions { drawPlanterBehind(region, garden: garden) }
    }

    /// A soft shadow of the box on the lawn: cast away from the sun, a darker band where the timber meets the grass,
    /// and a faint wider haze around the foot, so the box sits on the ground.
    private func drawPlanterContactShadow(_ region: BedRegion) {
        let o = Self.outer(region)
        let base = flatQuad(o.x0, o.x1, o.y0, o.y1)
        if let dir = shadowDir, let sun = palette.sun {
            let cast = Self.polygon(Self.shifted(base, dx: CGFloat(dir.x) * 0.03 * unit,
                                                 dy: CGFloat(dir.y) * 0.03 * unit))
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 0.012 * unit))
                layer.fill(cast, with: .color(Self.shadowInk.opacity(0.32 * SceneLighting.shadowOpacity(for: sun))))
            }
        }
        let haze = Self.polygon(flatQuad(o.x0 - 0.01, o.x1 + 0.01, o.y0 - 0.01, o.y1 + 0.01))
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 0.02 * unit))
            layer.fill(haze, with: .color(Self.shadowInk.opacity(0.14)))
        }
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 0.006 * unit))
            layer.stroke(Self.polygon(base), with: .color(Self.shadowInk.opacity(0.35)), lineWidth: 0.018 * unit)
        }
    }

    /// One box, behind the plants. The rims are the top of each wall, seen from above. The inside faces show where the
    /// eye is on their inside (the far wall always). The soil is lifted, so the inside walls show above it, and it is
    /// darkened where it meets the walls. The back corner posts stand above the back rim.
    private func drawPlanterBehind(_ region: BedRegion, garden: Garden) {
        let f = Self.inner(region), o = Self.outer(region)
        let H = Self.planterHeight
        let eye = eyeGround
        let lean = -(shadowDir?.x ?? 0)
        let cells = soilCells(garden) { region.edgeDistance($0) >= 0 }
        let moisture = Self.meanMoisture(cells)
        let seed = UInt64(abs(region.centre.x * 1000)) &* 31 &+ UInt64(abs(region.centre.y * 1000))

        // Outside end walls, when the eye is beyond them.
        if eye.x < o.x0 {
            boardFace(from: GroundPoint(x: o.x0, y: o.y1), to: GroundPoint(x: o.x0, y: o.y0), 0, H,
                      shade: 0.78, seed: seed &+ 1, boards: 2, lean: lean)
        }
        if eye.x > o.x1 {
            boardFace(from: GroundPoint(x: o.x1, y: o.y0), to: GroundPoint(x: o.x1, y: o.y1), 0, H,
                      shade: 0.78, seed: seed &+ 2, boards: 2, lean: lean)
        }

        // Rims: the back rim and the two side rims. The front rim goes with the front board.
        let rim = Self.timber(palette, shade: 1.14)
        fill(flatQuad(o.x0, o.x1, o.y0, f.y0, height: H), SceneColour.color(rim))
        fill(flatQuad(o.x0, f.x0, f.y0, f.y1, height: H), SceneColour.color(rim))
        fill(flatQuad(f.x1, o.x1, f.y0, f.y1, height: H), SceneColour.color(rim))

        // Inside walls: the far wall, then each side wall whose inside faces the eye.
        boardFace(from: GroundPoint(x: f.x0, y: f.y0), to: GroundPoint(x: f.x1, y: f.y0), 0, H,
                  shade: 0.62, seed: seed &+ 3, boards: 2, lean: lean)
        if eye.x > f.x0 {
            boardFace(from: GroundPoint(x: f.x0, y: f.y0), to: GroundPoint(x: f.x0, y: f.y1), 0, H,
                      shade: 0.5, seed: seed &+ 4, boards: 2, lean: lean)
        }
        if eye.x < f.x1 {
            boardFace(from: GroundPoint(x: f.x1, y: f.y1), to: GroundPoint(x: f.x1, y: f.y0), 0, H,
                      shade: 0.5, seed: seed &+ 5, boards: 2, lean: lean)
        }

        // Soil: lighter earth, moisture shading, and a darker band just inside the walls.
        let floor = soilQuad(f.x0, f.x1, f.y0, f.y1)
        let floorPath = Self.polygon(floor)
        fill(floor, SceneColour.color(Self.lighterSoil(palette, moisture: moisture)))
        clipped(to: floorPath) {
            paintMoisture(cells, blur: 0.01 * unit, lighten: 0.5)
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 0.02 * unit))
                layer.stroke(floorPath, with: .color(Self.shadowInk.opacity(0.42)), lineWidth: 0.07 * unit)
            }
        }

        // Back corner posts, standing a little above the back rim.
        let pw = Self.postWidth
        post(o.x0, o.x0 + pw, o.y0, o.y0 + pw, shade: 0.95)
        post(o.x1 - pw, o.x1, o.y0, o.y0 + pw, shade: 0.95)
    }

    /// The front of one planter box, drawn after the plants in front of it. Two boards make the front face, with a seam
    /// between them, grain, and a lit sun side. Corner posts stand proud of the rim (drawn last), and the top of the front board
    /// is the front rim, so the lower leaves of the plants behind it tuck under it.
    func drawPlanterBoxFront(_ garden: Garden, box: Int) {
        guard garden.plot.style == .plantersBoxes, garden.plot.regions.indices.contains(box) else { return }
        let region = garden.plot.regions[box]
        let f = Self.inner(region), o = Self.outer(region)
        let H = Self.planterHeight
        let lean = -(shadowDir?.x ?? 0)
        let seed = UInt64(abs(region.centre.x * 1000)) &* 31 &+ UInt64(abs(region.centre.y * 1000))

        boardFace(from: GroundPoint(x: o.x0, y: o.y1), to: GroundPoint(x: o.x1, y: o.y1), 0, H,
                  shade: 1.0, seed: seed &+ 6, boards: 2, lean: lean)

        // Nail heads near each end of each board.
        let nail = SceneColour.color(RGB(0.22, 0.2, 0.18))
        let r = 0.0032 * unit
        for x in [o.x0 + 0.5 * Self.postWidth + 0.02, o.x1 - 0.5 * Self.postWidth - 0.02] {
            for h in [H * 0.25, H * 0.75] {
                let c = lawn(GroundPoint(x: x, y: o.y1), height: h)
                ellipse(c, 2 * r, 2 * r, nail.opacity(0.85))
            }
        }

        // Front rim: lit on its front edge, with a dark line where it meets the inside of the box.
        fill(flatQuad(o.x0, o.x1, f.y1, o.y1, height: H), SceneColour.color(Self.timber(palette, shade: 1.2)))
        stroke([lawn(GroundPoint(x: o.x0, y: o.y1), height: H), lawn(GroundPoint(x: o.x1, y: o.y1), height: H)],
               width: 0.005 * unit, Color.white.opacity(0.25))
        stroke([lawn(GroundPoint(x: o.x0, y: f.y1), height: H), lawn(GroundPoint(x: o.x1, y: f.y1), height: H)],
               width: 0.004 * unit, Self.shadowInk.opacity(0.3))

        // Corner posts, proud of the rim. They go last so the rim does not paint over their lower part.
        let pw = Self.postWidth
        post(o.x0, o.x0 + pw, o.y1 - pw, o.y1, shade: 1.02)
        post(o.x1 - pw, o.x1, o.y1 - pw, o.y1, shade: 0.95)
    }
}
