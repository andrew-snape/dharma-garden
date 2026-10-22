import SwiftUI
import WeedsCore

/// What the custom plant drawings need from the shared pass in `Drawer.draw`.
struct PlantPose {
    let flower: FlowerType
    let sp: Species
    /// Main stem, already scaled by growth and droop.
    let stalk: Stalk
    /// 0...1 growth; 1 when drawing a seed head.
    let progress: Double
    /// Ease-out growth, used for stem thickness.
    let grow: Double
    let droop: Double
    let fade: Double
    let openness: Double
    let seed: UInt64
    let turn: Double
    let isSeedHead: Bool

    /// The bud appears between 0.64 and 0.72, then swells until 0.9.
    var budA: Double { smooth(progress, 0.64, 0.72) }
    var swell: Double { smooth(progress, 0.72, 0.9) }
    /// Petals open between 0.9 and 1. Seed heads count as fully open (they are dry).
    var openK: Double { isSeedHead ? 1 : openness * smooth(progress, 0.9, 1.0) }
}

/// Art for the plants whose silhouette is too different for the generic stem-and-leaf pass:
/// chocolate lily, common everlasting, basil, zucchini and lettuce. Calendula and cosmos use the generic pass.
extension Drawer {
    static let customFlowers: Set<FlowerType> = [.chocolateLily, .commonEverlasting, .basil, .zucchini, .lettuce]

    func drawCustomPlant(_ x: PlantPose) {
        switch x.flower {
        case .chocolateLily: chocolateLily(x)
        case .commonEverlasting: commonEverlasting(x)
        case .basil: basil(x)
        case .zucchini: zucchini(x)
        case .lettuce: lettuce(x)
        default: break
        }
    }

    // MARK: Shared shapes

    /// A bud with explicit colours, with the same green sepals as the original buds.
    func budShape(_ c: CGPoint, scale k: Double, alpha a: Double, tint: UInt32, shade: UInt32) {
        shaded(at(c, -0.03 * k, 0.03 * k), 0.085 * k, 0.2 * k, angle: -0.5, Ink.leaf.opacity(a), Ink.leafShade.opacity(a))
        shaded(at(c, 0.03 * k, 0.03 * k), 0.085 * k, 0.2 * k, angle: 0.5, Ink.leaf.opacity(a), Ink.leafShade.opacity(a))
        shaded(at(c, 0, -0.03 * k), 0.1 * k, 0.14 * k, Color(hex: tint).opacity(a), Color(hex: shade).opacity(a))
    }

    /// Palmate leaf: a big middle lobe with smaller side lobes fanning out from the same point.
    func lobedLeaf(from base: CGPoint, angle a: Double, length len: Double, _ colour: UInt32, _ shade: UInt32) {
        let lobes: [(offset: Double, scale: Double)] = [(-0.95, 0.45), (0.95, 0.45), (-0.45, 0.7), (0.45, 0.7), (0, 1)]
        for lobe in lobes {
            leaf(from: base, angle: a + lobe.offset, length: len * lobe.scale, aspect: 0.5,
                 Color(hex: colour), Color(hex: shade))
        }
    }

    /// Glossy oval leaf with a small pale glint near its middle.
    func glossyLeaf(from base: CGPoint, angle a: Double, length len: Double, aspect: Double,
                    _ colour: UInt32, _ shade: UInt32, glint: UInt32) {
        leaf(from: base, angle: a, length: len, aspect: aspect, Color(hex: colour), Color(hex: shade))
        let c = at(base, cos(a) * len * 0.42, sin(a) * len * 0.42)
        oval(c, len * 0.36, len * aspect * 0.3, angle: a, Color(hex: glint).opacity(0.8))
    }

    // MARK: Chocolate lily

    /// Grass-like strap leaves, a slender stem with two side buds, and a six-petalled star flower.
    private func chocolateLily(_ x: PlantPose) {
        let base = pt(0.5, 0.84)
        let leafLen = 0.3 * (0.35 + 0.65 * smooth(x.progress, 0, 0.5))
        let offsets: [Double] = [-0.42, -0.2, 0.02, 0.22, 0.42]
        for (i, off) in offsets.enumerated() {
            let jitter = (unitHash(x.seed, UInt64(20 + i)) * 2 - 1) * 0.06
            let a = -Double.pi / 2 + off + jitter + (off < 0 ? -1.0 : 1.0) * x.droop * 0.7
            let len = leafLen * (0.85 + 0.3 * unitHash(x.seed, UInt64(30 + i)))
            if len < 0.004 { continue }
            leaf(from: base, angle: a, length: len, aspect: 0.12, Ink.leaf, Ink.leafShade)
        }

        let stem = x.stalk
        stalk(stem, width: 0.014 * (0.75 + 0.25 * x.grow), Ink.stem)
        if !x.isSeedHead && x.budA > 0.001 {
            let sideBuds: [(t: Double, dx: Double, k: Double)] = [(0.6, -0.022, 0.6), (0.77, 0.022, 0.5)]
            for b in sideBuds {
                let q = stem.point(b.t)
                budShape(at(pt(q.x, q.y), b.dx, 0), scale: x.budA * b.k * (0.6 + 0.4 * x.swell), alpha: 1,
                         tint: Hue.mauve, shade: Hue.mauveShade)
            }
        }

        let q = stem.point(1)
        let tip = pt(q.x, q.y)
        if x.isSeedHead {
            // A dry seed pod on the stem top.
            shaded(tip, 0.075, 0.11, Color(hex: Hue.dryTan), Color(hex: Hue.dryTanShade))
            disc(tip, 0.03, Ink.brown, Ink.brownShade)
            return
        }
        if x.budA > 0.001 {
            let alpha = 1 - smooth(x.openK, 0.05, 0.6)
            if alpha > 0.01 {
                budShape(tip, scale: x.budA * (0.55 + 0.45 * x.swell), alpha: alpha, tint: Hue.mauve, shade: Hue.mauveShade)
            }
        }
        if x.openK > 0.01 {
            petalRing(tip, count: 6, length: 0.19, width: 0.065, radius: 0.05, Hue.mauve, Hue.mauveShade,
                      openK: x.openK, fade: x.fade, turn: x.turn, seed: x.seed)
            disc(tip, 0.05 * (0.6 + 0.4 * x.openK), Color(hex: Hue.plum), Color(hex: Hue.plumShade),
                 alpha: smooth(x.openK, 0.02, 0.3))
        }
    }

    // MARK: Common everlasting

    /// A low silvery-green mat, with short stems that each end in a cluster of papery yellow button heads.
    private func commonEverlasting(_ x: PlantPose) {
        let base = pt(0.5, 0.84)
        let matLeaves = 9
        for k in 0..<matLeaves {
            let f = Double(k) / Double(matLeaves - 1)
            var a = -(0.08 + 0.84 * f) * Double.pi
            a += (unitHash(x.seed, UInt64(50 + k)) * 2 - 1) * 0.12
            // Leaves lie flatter when the plant droops.
            a += x.droop * 0.35 * (cos(a) >= 0 ? 1.0 : -1.0)
            let len = 0.17 * (0.3 + 0.7 * smooth(x.progress, 0, 0.6)) * (0.85 + 0.3 * unitHash(x.seed, UInt64(70 + k)))
            if len < 0.004 { continue }
            leaf(from: base, angle: a, length: len, aspect: 0.38, Ink.silverLeaf, Ink.silverLeafShade)
        }

        let stems: [(off: Double, h: Double)] = [(-0.13, 0.7), (-0.06, 1.0), (0.01, 0.82), (0.09, 0.62), (0.16, 0.92)]
        let headA = smooth(x.progress, 0.55, 0.78)
        for (i, s) in stems.enumerated() {
            let hv = 1 + (unitHash(x.seed, UInt64(90 + i)) * 2 - 1) * 0.1
            let h = x.sp.maxHeight * s.h * hv * x.grow * (1 - 0.06 * x.droop)
            let topX = 0.5 + s.off + x.droop * 0.05 * (s.off < 0 ? -1.0 : 1.0)
            let rootX = 0.5 + s.off * 0.4
            let top = pt(topX, 0.84 - h)
            polyline([pt(rootX, 0.84), pt((rootX + topX) / 2, 0.84 - h / 2), top],
                     width: 0.009 * (0.7 + 0.3 * x.grow), Ink.stem)

            if x.isSeedHead || headA > 0.001 {
                // Buds are olive green, opening to straw yellow, and dry to tan.
                let bloomK = x.openK
                let hex = x.isSeedHead ? Hue.dryTan
                    : blendHex(blendHex(Hue.budGreen, Hue.straw, bloomK), Hue.faded, x.fade * 0.6)
                let shadeHex = x.isSeedHead ? Hue.dryTanShade
                    : blendHex(blendHex(Hue.budGreenShade, Hue.strawShade, bloomK), Hue.faded, x.fade * 0.6)
                let alpha = x.isSeedHead ? 1.0 : headA
                for (dx, dy, d) in [(0.0, 0.0, 0.07), (-0.04, 0.02, 0.05), (0.04, 0.018, 0.05)] {
                    disc(at(top, dx, dy), d * (0.7 + 0.3 * bloomK), Color(hex: hex), Color(hex: shadeHex), alpha: alpha)
                }
            }
        }
    }

    // MARK: Basil

    /// A bushy plant of glossy oval leaves. At progress 1 a small white flower spike rises from the top.
    private func basil(_ x: PlantPose) {
        let pl = x.progress
        let leafHex: UInt32 = x.isSeedHead ? Hue.dryTan : Hue.basilLeaf
        let leafShadeHex: UInt32 = x.isSeedHead ? Hue.dryTanShade : Hue.basilLeafShade
        stalk(x.stalk, width: 0.02 * (0.7 + 0.3 * x.grow), Ink.stem)

        // A bushy plant: layers of leaf pairs radiate outward at several heights, longest at the bottom, so it
        // spreads wide instead of stacking in a column. A small cluster of young leaves crowns the top.
        let layers = 5
        let sizeK = 0.3 + 0.7 * smooth(pl, 0, 0.5)
        for i in 0..<layers {
            let fi = Double(i)
            let u = 0.08 + 0.72 * fi / Double(layers - 1)
            let grown = smooth(pl, 0.03 + 0.08 * fi, 0.22 + 0.08 * fi)
            let reach = 0.3 - 0.14 * u
            for (j, side) in [-1.0, 1.0].enumerated() {
                var a = -Double.pi / 2 + side * (1.45 - 0.75 * u) + side * x.droop * 0.9
                a += (unitHash(x.seed, UInt64(40 + i * 2 + j)) * 2 - 1) * 0.15
                let len = reach * sizeK * grown * (0.9 + 0.2 * unitHash(x.seed, UInt64(60 + i * 2 + j)))
                if len < 0.004 { continue }
                let q = x.stalk.point(u)
                glossyLeaf(from: pt(q.x, q.y), angle: a, length: len, aspect: 0.62, leafHex, leafShadeHex, glint: Hue.basilGlint)
            }
            // A smaller leaf facing the viewer fills the gap between each pair.
            let front = reach * 0.7 * sizeK * grown
            if front >= 0.004 {
                let q = x.stalk.point(u)
                let a = -Double.pi / 2 + (i % 2 == 0 ? 0.55 : -0.55) + (i % 2 == 0 ? 1.0 : -1.0) * x.droop * 0.7
                glossyLeaf(from: pt(q.x, q.y), angle: a, length: front, aspect: 0.62, leafHex, leafShadeHex, glint: Hue.basilGlint)
            }
        }
        let crown = smooth(pl, 0.3, 0.6)
        for (j, off) in [-0.5, 0.0, 0.5].enumerated() {
            let len = 0.1 * crown * (0.9 + 0.2 * unitHash(x.seed, UInt64(80 + j)))
            if len < 0.004 { continue }
            let q = x.stalk.point(0.92)
            glossyLeaf(from: pt(q.x, q.y), angle: -Double.pi / 2 + off + x.droop * off, length: len, aspect: 0.6,
                       leafHex, leafShadeHex, glint: Hue.basilGlint)
        }

        // Flower spike: grows up from the top, with five small florets that open near ready.
        let q = x.stalk.point(1)
        let tip = pt(q.x, q.y)
        let spike = 0.16 * smooth(pl, 0.6, 1.0)
        if spike > 0.002 {
            let top = at(tip, 0, -spike)
            polyline([tip, top], width: 0.011, x.isSeedHead ? Color(hex: Hue.dryTanShade) : Ink.stem)
            let floretScale = smooth(pl, 0.82, 0.95)
            for j in 0..<5 {
                let t = Double(j + 1) / 6
                let c = at(tip, j % 2 == 0 ? -0.012 : 0.012, -spike * t)
                if x.isSeedHead {
                    // Dry seeds left on the spike.
                    shaded(c, 0.024, 0.024, Color(hex: Hue.dryTan), Color(hex: Hue.dryTanShade))
                    continue
                }
                let rank = unitHash(x.seed, UInt64(200 + j))
                let fall = smooth(x.fade, rank * 0.8, rank * 0.8 + 0.2)
                let d = 0.055 * floretScale * (1 - fall)
                if d < 0.002 { continue }
                shaded(c, d, d * 0.8, Color(hex: blendHex(Hue.budGreen, Hue.cream, x.openK)), Color(hex: Hue.creamShade))
            }
        }
    }

    // MARK: Zucchini

    /// Big lobed leaves, a bright yellow trumpet flower, and a green fruit that swells from progress 0.68 to 0.98.
    private func zucchini(_ x: PlantPose) {
        let pl = x.progress
        let leafHex: UInt32 = x.isSeedHead ? Hue.dryTan : Hue.zucchiniLeaf
        let leafShadeHex: UInt32 = x.isSeedHead ? Hue.dryTanShade : Hue.zucchiniLeafShade
        stalk(x.stalk, width: 0.03 * (0.7 + 0.3 * x.grow), Ink.stem)

        for i in 0..<4 {
            let fi = Double(i)
            let u = 0.2 + 0.5 * fi / 3
            let side: Double = i % 2 == 0 ? -1 : 1
            var a = -Double.pi / 2 + side * 0.95 + side * x.droop * 0.9
            a += (unitHash(x.seed, UInt64(40 + i)) * 2 - 1) * 0.18
            let grown = smooth(pl, 0.05 + 0.1 * fi, 0.25 + 0.1 * fi)
            let len = 0.36 * (0.35 + 0.65 * smooth(pl, 0, 0.5)) * grown
            if len < 0.004 { continue }
            let q = x.stalk.point(u)
            lobedLeaf(from: pt(q.x, q.y), angle: a, length: len, leafHex, leafShadeHex)
        }

        // The fruit lies out in front of the leaves, low on the right: long, thick, pale green with a lighter
        // stripe, and a small yellow flower still on its far end. It swells from 0.68 to 0.98.
        let fruitK = x.isSeedHead ? 1 : smooth(pl, 0.68, 0.98)
        if fruitK > 0.001 {
            let q = x.stalk.point(0.2)
            let start = pt(q.x + 0.02, q.y)
            let hex: UInt32 = x.isSeedHead ? Hue.dryTan : 0xA8D06A
            let shadeHex: UInt32 = x.isSeedHead ? Hue.dryTanShade : 0x84AE4E
            let angle = 0.3
            let len = 0.18 + 0.22 * fruitK
            let thick = len * 0.36
            let body = at(start, cos(angle) * len / 2, sin(angle) * len / 2)
            shaded(body, len, thick, angle: angle, Color(hex: hex), Color(hex: shadeHex))
            if !x.isSeedHead {
                oval(at(body, 0, -thick * 0.14), len * 0.7, thick * 0.2, angle: angle, Color(hex: 0xD3E8A0).opacity(0.85 * fruitK))
                let end = at(start, cos(angle) * len, sin(angle) * len)
                let fk = smooth(fruitK, 0.1, 0.5) * (1 - 0.8 * smooth(x.fade, 0, 1))
                if fk > 0.01 {
                    petalRing(end, count: 5, length: 0.13 * fk, width: 0.085 * fk, radius: 0.02, Hue.trumpet, Hue.trumpetShade,
                              openK: 1, fade: 0, turn: x.turn, seed: x.seed)
                    disc(end, 0.035 * fk, Color(hex: Hue.throat), Color(hex: Hue.throatShade), alpha: 1)
                }
            }
        }

        let q = x.stalk.point(1)
        let tip = pt(q.x, q.y)
        if x.isSeedHead {
            // The flower is gone; only a dry stub remains.
            disc(tip, 0.035, Ink.brown, Ink.brownShade)
            return
        }
        if x.budA > 0.001 {
            let alpha = 1 - smooth(x.openK, 0.05, 0.6)
            if alpha > 0.01 {
                budShape(tip, scale: x.budA * (0.55 + 0.45 * x.swell), alpha: alpha, tint: Hue.trumpet, shade: Hue.trumpetShade)
            }
        }
        if x.openK > 0.01 {
            petalRing(tip, count: 5, length: 0.19, width: 0.12, radius: 0.07, Hue.trumpet, Hue.trumpetShade,
                      openK: x.openK, fade: x.fade, turn: x.turn, seed: x.seed)
            disc(tip, 0.07 * (0.5 + 0.5 * x.openK), Color(hex: Hue.throat), Color(hex: Hue.throatShade),
                 alpha: smooth(x.openK, 0.02, 0.3))
        }
    }

    // MARK: Lettuce

    /// A low rosette of frilly, overlapping leaves in two greens with soft red tips. At progress 1 a full round head.
    /// Bolted (seed head): a pale stalk with a fluffy puff.
    private func lettuce(_ x: PlantPose) {
        let base = pt(0.5, 0.84)
        let pl = x.progress
        let rosette = 9
        for k in 0..<rosette {
            let fk = Double(k)
            let outer = abs(k - 4) >= 2
            var a = -Double.pi / 2 + (fk - 4) * 0.3
            a += (unitHash(x.seed, UInt64(20 + k)) * 2 - 1) * 0.1
            // Outer leaves flatten when the plant droops.
            a += x.droop * 0.4 * (a >= -Double.pi / 2 ? 1.0 : -1.0)
            let grown = smooth(pl, 0.02 + 0.03 * fk, 0.2 + 0.03 * fk)
            let len = 0.2 * (0.3 + 0.7 * smooth(pl, 0, 0.5)) * grown * (0.9 + 0.2 * unitHash(x.seed, UInt64(40 + k)))
            if len < 0.004 { continue }
            let hex: UInt32 = x.isSeedHead ? Hue.dryTan : (outer ? Hue.lettuceOuter : Hue.lettuceInner)
            let shadeHex: UInt32 = x.isSeedHead ? Hue.dryTanShade : (outer ? Hue.lettuceOuterShade : Hue.lettuceInnerShade)
            // Frilly: three leaflets fanned slightly apart give a wavy edge.
            for j in 0..<3 {
                let fj = Double(j - 1)
                leaf(from: base, angle: a + fj * 0.14, length: len * (1 - 0.12 * abs(fj)), aspect: 0.5,
                     Color(hex: hex), Color(hex: shadeHex))
            }
            if outer && !x.isSeedHead && pl > 0.3 {
                let tipPt = at(base, cos(a) * len * 0.8, sin(a) * len * 0.8)
                oval(tipPt, len * 0.26, len * 0.2, angle: a,
                     Color(hex: Hue.lettuceTip).opacity(0.75 * smooth(pl, 0.3, 0.6)))
            }
        }

        if x.isSeedHead {
            let top = pt(0.53, 0.42)
            polyline([base, pt(0.5, 0.66), top], width: 0.012, Color(hex: Hue.dryTanShade))
            for k in 0..<7 {
                let a = Double(k) / 7 * 2 * Double.pi + x.turn
                shaded(at(top, cos(a) * 0.035, sin(a) * 0.035), 0.05, 0.03, angle: a,
                       Color(hex: Hue.fluff), Color(hex: Hue.fluffShade))
            }
            return
        }

        // The full round head grows over the rosette's centre between 0.7 and 1.
        let headK = smooth(pl, 0.7, 1.0)
        if headK > 0.001 {
            let centre = pt(0.5, 0.8)
            let fadeMix = x.fade * 0.7
            shaded(centre, 0.2 * headK, 0.19 * headK,
                   Color(hex: blendHex(Hue.lettuceInner, Hue.faded, fadeMix)),
                   Color(hex: blendHex(Hue.lettuceInnerShade, Hue.faded, fadeMix)))
            shaded(at(centre, 0, -0.012 * headK), 0.12 * headK, 0.11 * headK,
                   Color(hex: blendHex(Hue.lettuceCore, Hue.faded, fadeMix)), Color(hex: Hue.lettuceCoreShade))
            // A soft red blush along the bottom rim of the head.
            oval(at(centre, 0, 0.09 * headK), 0.14 * headK, 0.03 * headK,
                 Color(hex: Hue.lettuceTip).opacity(0.35 * headK))
        }
    }
}
