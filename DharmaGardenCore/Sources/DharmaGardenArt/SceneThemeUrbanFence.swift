import SwiftUI
import DharmaGardenCore

/// The Urban theme's tall timber close-board fence, as canvas quads. Every corner comes from `BarrierFrame.point`
/// (the shared upright projection), so verticals stay vertical, lines run to the lawn's vanishing point, and the side
/// fences start exactly where the back fence ends (x = +-halfLength, z = `SceneCanvas.fenceZ`).
struct UrbanFence {
    enum Kind: Equatable {
        case gravel, gravelTop
        /// A vertical board, with its tone 0..<4, and the dark sliver along one edge that reads as the gap.
        case board(Int), boardEdge
        case rail, railShade
        case post, postShade, cap
        /// A knot: the quad is the bounding rectangle of an ellipse.
        case knot
    }

    struct Part {
        let quad: [CGPoint]
        let kind: Kind
    }

    /// Fence height (boards), in world units: taller than the farm's 1.1, so the neighbours' roofs show above it.
    static let height = 1.7
    static let gravelHeight = 0.22
    static let boardWidth = 0.15
    /// Posts stand every `panelWidth` along the fence.
    static let panelWidth = 1.5
    static let postWidth = 0.17
    /// Posts stand a little above the top rail, and the corner posts a little more.
    static let postRise = 0.05
    static let cornerRise = 0.12
    static let capHeight = 0.09
    /// The side fences stop here, short of the camera (as `BarrierFrame` does).
    static let sideEnd = 2.9
    /// How far the gravel board dips below the lawn's edge, in points, so parallax never opens a gap.
    static let dip: CGFloat = 5

    let frame: BarrierFrame
    /// The back fence runs from -halfLength to +halfLength.
    var halfLength: Double = BarrierFrame.halfLength
    /// True when side fences meet the back fence: its end posts are the taller corner posts.
    var corners = true

    private var z0: Double { SceneCanvas.fenceZ }

    private func pt(_ x: Double, _ z: Double, _ h: Double = 0) -> CGPoint { frame.point(x: x, z: z, height: h) }

    private func quad(_ a: (x: Double, z: Double), _ b: (x: Double, z: Double), _ h0: Double, _ h1: Double) -> [CGPoint] {
        [pt(a.x, a.z, h0), pt(b.x, b.z, h0), pt(b.x, b.z, h1), pt(a.x, a.z, h1)]
    }

    /// Posts' tops, with the extra rise for corner posts.
    private func postTop(corner: Bool) -> Double { Self.height + (corner ? Self.cornerRise : Self.postRise) }

    // MARK: Back fence

    /// The back fence from end to end: gravel boards, close boards, knots, top rail, then the posts and their caps.
    func backParts() -> [Part] {
        let z = z0, h = halfLength
        var parts: [Part] = []
        let panels = Int((2 * h / Self.panelWidth).rounded())
        for i in 0..<panels {
            let a = -h + Double(i) * Self.panelWidth, b = a + Self.panelWidth
            parts.append(gravel(quad((a, z), (b, z), 0, Self.gravelHeight)))
            parts.append(Part(quad: [pt(a, z, Self.gravelHeight - 0.03), pt(b, z, Self.gravelHeight - 0.03),
                                     pt(b, z, Self.gravelHeight + 0.01), pt(a, z, Self.gravelHeight + 0.01)], kind: .gravelTop))
        }
        let count = Int((2 * h / Self.boardWidth).rounded())
        let bw = 2 * h / Double(count)
        for i in 0..<count {
            let a = -h + Double(i) * bw, b = a + bw
            parts.append(Part(quad: quad((a, z), (b, z), Self.gravelHeight, Self.height), kind: .board(tone(i))))
            parts.append(Part(quad: quad((b - bw * 0.26, z), (b, z), Self.gravelHeight, Self.height), kind: .boardEdge))
            if let k = knot(i, a: a, b: b, along: { self.pt($0, z, $1) }) { parts.append(k) }
        }
        parts += rails(from: (-h, z), to: (h, z))
        for k in 0...panels {
            let x = -h + Double(k) * Self.panelWidth
            parts += postParts(centre: (x, z), along: (1, 0), corner: corners && (k == 0 || k == panels))
        }
        return parts
    }

    // MARK: Side fences

    /// A side fence at x, from the back fence's end toward the viewer. The first post, at the join, is the taller
    /// corner post.
    func sideParts(x: Double) -> [Part] {
        let za = z0, zb = Self.sideEnd
        var parts: [Part] = []
        let panels = Int(((zb - za) / Self.panelWidth).rounded(.up))
        for i in 0..<panels {
            let a = za + Double(i) * Self.panelWidth, b = min(zb, a + Self.panelWidth)
            parts.append(gravel(quad((x, a), (x, b), 0, Self.gravelHeight)))
            parts.append(Part(quad: [pt(x, a, Self.gravelHeight - 0.03), pt(x, b, Self.gravelHeight - 0.03),
                                     pt(x, b, Self.gravelHeight + 0.01), pt(x, a, Self.gravelHeight + 0.01)], kind: .gravelTop))
        }
        let count = Int(((zb - za) / Self.boardWidth).rounded())
        let bw = (zb - za) / Double(count)
        for i in 0..<count {
            let a = za + Double(i) * bw, b = a + bw
            parts.append(Part(quad: quad((x, a), (x, b), Self.gravelHeight, Self.height), kind: .board(tone(i + 7))))
            parts.append(Part(quad: quad((x, b - bw * 0.26), (x, b), Self.gravelHeight, Self.height), kind: .boardEdge))
            if let k = knot(i + 7, a: a, b: b, along: { self.pt(x, $0, $1) }) { parts.append(k) }
        }
        parts += rails(from: (x, za), to: (x, zb))
        for k in 0...panels {
            let z = za + Double(k) * Self.panelWidth
            guard z <= zb + 1e-9 else { break }
            parts += postParts(centre: (x, z), along: (0, 1), corner: corners && k == 0)
        }
        return parts
    }

    // MARK: Pieces

    /// A gravel board quad, dipped a few points below the lawn's edge.
    private func gravel(_ q: [CGPoint]) -> Part {
        var q = q
        q[0].y += Self.dip
        q[1].y += Self.dip
        return Part(quad: q, kind: .gravel)
    }

    /// Board tone 0..<4, fixed per board index.
    private func tone(_ i: Int) -> Int { Int(unitHash(0xB04D, UInt64(i)) * 4) % 4 }

    /// A knot on about one board in ten: a small ellipse at a fixed height. `along` maps (position, height) to a point.
    private func knot(_ i: Int, a: Double, b: Double, along: (Double, Double) -> CGPoint) -> Part? {
        guard unitHash(0x4B07, UInt64(i)) > 0.9 else { return nil }
        let h = Self.gravelHeight + 0.25 + unitHash(0x4B08, UInt64(i)) * (Self.height - Self.gravelHeight - 0.5)
        let m = (a + b) / 2, w = (b - a) * 0.28
        let p0 = along(m - w, h - 0.05), p1 = along(m + w, h + 0.05)
        return Part(quad: [p0, CGPoint(x: p1.x, y: p0.y), p1, CGPoint(x: p0.x, y: p1.y)], kind: .knot)
    }

    /// The top capping rail along the fence, with a darker underside.
    private func rails(from a: (x: Double, z: Double), to b: (x: Double, z: Double)) -> [Part] {
        [Part(quad: quad(a, b, Self.height - 0.045, Self.height), kind: .railShade),
         Part(quad: quad(a, b, Self.height, Self.height + 0.04), kind: .rail)]
    }

    /// A post centred on its base at `centre`, `postWidth` wide along the unit vector `along` (in x, z), with a
    /// shaded edge and a capped top.
    private func postParts(centre c: (x: Double, z: Double), along u: (x: Double, z: Double), corner: Bool) -> [Part] {
        let w = Self.postWidth / 2, top = postTop(corner: corner)
        func at(_ d: Double) -> (x: Double, z: Double) { (c.x + u.x * d, c.z + u.z * d) }
        let a = at(-w), b = at(w), mid = at(w * 0.35)
        let cap0 = at(-w * 1.35), cap1 = at(w * 1.35), cap2 = at(-w * 0.7), cap3 = at(w * 0.7)
        return [
            Part(quad: quad(a, b, 0, top), kind: .post),
            Part(quad: quad(mid, b, 0, top), kind: .postShade),
            Part(quad: [pt(cap0.x, cap0.z, top), pt(cap1.x, cap1.z, top), pt(cap3.x, cap3.z, top + Self.capHeight),
                        pt(cap2.x, cap2.z, top + Self.capHeight)], kind: .cap),
        ]
    }
}

extension SceneCanvas {
    /// Fills fence parts in order. `side` fences face across the yard, so they sit a touch darker.
    func drawUrbanFence(_ parts: [UrbanFence.Part], side: Bool) {
        let f = side ? 0.9 : 1.0
        let boards: [UInt32] = [0xBC8F63, 0xB08158, 0xC79B6E, 0xA8794F]
        for part in parts {
            switch part.kind {
            case .gravel: fill(part.quad, urbanTone(0x7A6B5B, f))
            case .gravelTop: fill(part.quad, urbanTone(0x9A8A76, f))
            case .board(let t): fill(part.quad, urbanTone(boards[t], f))
            case .boardEdge: fill(part.quad, urbanTone(0x7E5A39, f))
            case .railShade: fill(part.quad, urbanTone(0x7A5638, f))
            case .rail: fill(part.quad, urbanTone(0xD3AE82, f))
            case .post: fill(part.quad, urbanTone(0xCDA577, f))
            case .postShade: fill(part.quad, urbanTone(0xA77E52, f))
            case .cap: fill(part.quad, urbanTone(0xE0BC8E, f))
            case .knot:
                let r = CGRect(x: part.quad[0].x, y: part.quad[2].y, width: part.quad[1].x - part.quad[0].x,
                               height: part.quad[0].y - part.quad[2].y)
                ctx.fill(Path(ellipseIn: r), with: .color(urbanTone(0x6B4B30, f)))
            }
        }
    }

    func urbanBarrier() {
        let frame = BarrierFrame(camera: camera, size: size, style: .timberPanel)
        // The first-person view has no side fences, so its back fence runs past both edges of the frame.
        let backyard = style == .backyard
        let fence = UrbanFence(frame: frame, halfLength: backyard ? BarrierFrame.halfLength : UrbanScene.firstPersonHalfLength,
                               corners: backyard)
        drawUrbanFence(fence.backParts(), side: false)
    }

    /// Backyard only: the side fences, then the clutter that stands in front of them.
    func urbanSideBarriers() {
        let fence = UrbanFence(frame: BarrierFrame(camera: camera, size: size, style: .timberPanel))
        for x in [-BarrierFrame.halfLength, BarrierFrame.halfLength] {
            drawUrbanFence(fence.sideParts(x: x), side: true)
        }
        urbanGroundAligned().drawUrbanProps()
    }
}
