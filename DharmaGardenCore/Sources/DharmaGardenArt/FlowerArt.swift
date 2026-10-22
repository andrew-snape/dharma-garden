import SwiftUI
import DharmaGardenCore

/// Flat, outline-free, rounded shapes with a darker offset "shade" layer under each shape,
/// in warm sun-faded colours. Everything is drawn from simple shapes, no image assets.
public enum Ink {
    public static let leaf = Color(hex: 0x86AE55)
    public static let leafShade = Color(hex: 0x678F3F)
    public static let stem = Color(hex: 0x739B47)
    public static let soil = Color(hex: 0xB8764D)
    public static let soilShade = Color(hex: 0x935A39)
    public static let seed = Color(hex: 0xF1DFB8)
    public static let cream = Color(hex: 0xFFF6E0)
    public static let creamShade = Color(hex: 0xE9D9B5)
    public static let gold = Color(hex: 0xF6BE3B)
    public static let goldShade = Color(hex: 0xD9962A)
    public static let sunPetal = Color(hex: 0xFAC93E)
    public static let sunPetalShade = Color(hex: 0xE0A02A)
    public static let brown = Color(hex: 0x6E4430)
    public static let brownShade = Color(hex: 0x4F2F21)
    public static let lilac = Color(hex: 0xA58BD3)
    public static let lilacShade = Color(hex: 0x7F66B0)
    public static let poppy = Color(hex: 0xEE5B3F)
    public static let poppyShade = Color(hex: 0xC9412B)
    public static let dark = Color(hex: 0x3B2A25)
    public static let mauve = Color(hex: Hue.mauve)
    public static let mauveShade = Color(hex: Hue.mauveShade)
    public static let calendula = Color(hex: Hue.calendula)
    public static let calendulaShade = Color(hex: Hue.calendulaShade)
    public static let cosmosPink = Color(hex: Hue.cosmosPink)
    public static let cosmosPinkShade = Color(hex: Hue.cosmosPinkShade)
    public static let silverLeaf = Color(hex: Hue.silverLeaf)
    public static let silverLeafShade = Color(hex: Hue.silverLeafShade)
    public static let basilLeaf = Color(hex: Hue.basilLeaf)
    public static let basilLeafShade = Color(hex: Hue.basilLeafShade)
    public static let zucchiniLeaf = Color(hex: Hue.zucchiniLeaf)
    public static let zucchiniLeafShade = Color(hex: Hue.zucchiniLeafShade)
    public static let trumpet = Color(hex: Hue.trumpet)
    public static let trumpetShade = Color(hex: Hue.trumpetShade)
    public static let lettuceOuter = Color(hex: Hue.lettuceOuter)
    public static let lettuceInner = Color(hex: Hue.lettuceInner)
}

public extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}

/// A flower plant drawn from parameters. Pure function of its inputs: the same inputs always draw the same picture.
public struct FlowerArt: View, Sendable {
    /// nil draws bare soil.
    public var flower: FlowerType?
    /// 0...1 continuous growth. 0 = seed on soil, about 0.08 sprout, 0.7 bud, 0.9 opening, 1 full bloom.
    public var progress: Double
    /// 0...1 leaves and stem sag smoothly, the head bows.
    public var droop: Double
    /// 0...1 petals lose colour and drop off progressively (meaningful at progress 1). At 1 only the centre remains.
    public var fade: Double
    /// 0...1 how open the head is at bloom; petals scale out from the centre.
    public var openness: Double
    /// Seeds a deterministic per-plant variation: height +/-8%, lean, leaf angles, petal count +/-2.
    public var variation: UInt64
    /// -1...1 horizontal bend of the stem top (the top bends most).
    public var sway: Double
    /// Draws a dried, brownish seed head in place of the flower.
    public var isSeedHead: Bool
    /// Withered stem.
    public var dead: Bool
    /// Colour of the soil mound under the plant, so it blends into the patch. nil uses Ink.soil.
    public var soilColor: Color?
    /// Shade under the soil mound, matching `soilColor`. nil uses Ink.soilShade.
    public var soilShade: Color?

    public init(flower: FlowerType?, progress: Double, droop: Double = 0, fade: Double = 0, openness: Double = 1,
                variation: UInt64 = 0, sway: Double = 0, isSeedHead: Bool = false, dead: Bool = false,
                soilColor: Color? = nil, soilShade: Color? = nil) {
        self.flower = flower
        self.progress = progress
        self.droop = droop
        self.fade = fade
        self.openness = openness
        self.variation = variation
        self.sway = sway
        self.isSeedHead = isSeedHead
        self.dead = dead
        self.soilColor = soilColor
        self.soilShade = soilShade
    }

    /// Compatibility with the stage-based API: maps the stage to a progress value and wilting to droop.
    public init(flower: FlowerType?, stage: GrowthStage, wilted: Bool = false, dead: Bool = false) {
        let p: Double
        switch stage {
        case .seed: p = 0
        case .sprout: p = 0.25
        case .bud: p = 0.7
        case .bloom: p = 1.0
        }
        self.init(flower: flower, progress: p, droop: wilted ? 0.8 : 0, dead: dead)
    }

    public var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            let d = Drawer(ctx: ctx, s: s, origin: CGPoint(x: (size.width - s) / 2, y: (size.height - s) / 2))
            d.draw(flower: flower, progress: progress, droop: droop, fade: fade, openness: openness,
                   variation: variation, sway: sway, isSeedHead: isSeedHead, dead: dead,
                   soil: soilColor ?? Ink.soil, soilShade: soilShade ?? Ink.soilShade)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Maths and palette helpers

func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }

/// Smooth 0...1 ramp between a and b.
func smooth(_ x: Double, _ a: Double, _ b: Double) -> Double {
    let t = clamp01((x - a) / (b - a))
    return t * t * (3 - 2 * t)
}

/// Deterministic hash of (seed, index) to 0...1 (splitmix64 finaliser).
func unitHash(_ seed: UInt64, _ index: UInt64) -> Double {
    var z = seed &+ (index &+ 1) &* 0x9E37_79B9_7F4A_7C15
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    z ^= z >> 31
    return Double(z >> 11) / 9_007_199_254_740_992
}

/// Blends two 0xRRGGBB colours; t = 0 gives a, t = 1 gives b.
func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> Color {
    let k = clamp01(t)
    func lerp(_ shift: UInt32) -> Double {
        let x = Double((a >> shift) & 255), y = Double((b >> shift) & 255)
        return (x + (y - x) * k) / 255
    }
    return Color(red: lerp(16), green: lerp(8), blue: lerp(0))
}

/// Hex copies of the petal tints, so they can be blended toward the faded colour.
enum Hue {
    static let sun: UInt32 = 0xFAC93E
    static let sunShade: UInt32 = 0xE0A02A
    static let cream: UInt32 = 0xFFF6E0
    static let creamShade: UInt32 = 0xE9D9B5
    static let poppy: UInt32 = 0xEE5B3F
    static let poppyShade: UInt32 = 0xC9412B
    static let lilac: UInt32 = 0xA58BD3
    static let lilacShade: UInt32 = 0x7F66B0
    static let faded: UInt32 = 0xB9A98F
    static let dryTan: UInt32 = 0xC9A36B
    static let dryTanShade: UInt32 = 0x9C7A48
    static let fluff: UInt32 = 0xE6D6AE
    static let fluffShade: UInt32 = 0xB9A07A
    static let deadStem: UInt32 = 0x9C8462
    static let leaf: UInt32 = 0x86AE55
    static let leafShade: UInt32 = 0x678F3F
    static let plum: UInt32 = 0x4A2B4F
    static let plumShade: UInt32 = 0x321C37
    // Chocolate lily
    static let mauve: UInt32 = 0x9B6DB8
    static let mauveShade: UInt32 = 0x724A8F
    static let budGreen: UInt32 = 0x9DB36B
    static let budGreenShade: UInt32 = 0x7C9450
    // Common everlasting
    static let silverLeaf: UInt32 = 0x9CB39B
    static let silverLeafShade: UInt32 = 0x748F77
    static let straw: UInt32 = 0xF7D24B
    static let strawShade: UInt32 = 0xD8AE2E
    // Calendula
    static let calendula: UInt32 = 0xF58A1F
    static let calendulaShade: UInt32 = 0xD06A12
    static let calendulaCentre: UInt32 = 0xC8560F
    static let calendulaCentreShade: UInt32 = 0x9E4209
    static let calLeaf: UInt32 = 0xA7C866
    static let calLeafShade: UInt32 = 0x84A44C
    // Cosmos
    static let cosmosPink: UInt32 = 0xF28AB2
    static let cosmosPinkShade: UInt32 = 0xD86A97
    static let cosmosCentre: UInt32 = 0xF6C92E
    static let cosmosCentreShade: UInt32 = 0xD9A21B
    static let cosmosLeaf: UInt32 = 0x7FB35A
    static let cosmosLeafShade: UInt32 = 0x5F9243
    // Basil
    static let basilLeaf: UInt32 = 0x6BAA4A
    static let basilLeafShade: UInt32 = 0x4D8637
    static let basilGlint: UInt32 = 0xB5DE93
    // Zucchini
    static let trumpet: UInt32 = 0xFFC61E
    static let trumpetShade: UInt32 = 0xE39B12
    static let throat: UInt32 = 0xE8A60F
    static let throatShade: UInt32 = 0xC9830A
    static let zucchiniLeaf: UInt32 = 0x5E9A3D
    static let zucchiniLeafShade: UInt32 = 0x46772C
    static let fruit: UInt32 = 0x4F9A3A
    static let fruitShade: UInt32 = 0x37742A
    static let fruitStripe: UInt32 = 0x9ED07A
    // Lettuce
    static let lettuceOuter: UInt32 = 0x5C9A3C
    static let lettuceOuterShade: UInt32 = 0x42742A
    static let lettuceInner: UInt32 = 0xC7E08E
    static let lettuceInnerShade: UInt32 = 0xA2C36A
    static let lettuceCore: UInt32 = 0xDDEFB0
    static let lettuceCoreShade: UInt32 = 0xB6D37F
    static let lettuceTip: UInt32 = 0xD9707A
    // Beetroot, broccoli, carrot, rocket, corn, broad bean, radish, spinach
    static let beetRoot: UInt32 = 0x9E1F4A
    static let beetRootShade: UInt32 = 0x7A1538
    static let beetLeaf: UInt32 = 0x5E8F3E
    static let beetLeafShade: UInt32 = 0x47712F
    static let broccoliHead: UInt32 = 0x3E7A3A
    static let broccoliHeadShade: UInt32 = 0x2B5C2A
    static let carrotFlower: UInt32 = 0xF6F0DC
    static let carrotFlowerShade: UInt32 = 0xD9CFB0
    static let rocketLeaf: UInt32 = 0x5F9E3E
    static let rocketLeafShade: UInt32 = 0x477C2D
    static let beanFlower: UInt32 = 0xF4F1E6
    static let beanFlowerShade: UInt32 = 0xD3CDB8
    static let radishRed: UInt32 = 0xE0455A
    static let radishRedShade: UInt32 = 0xB82E44
    static let spinachLeaf: UInt32 = 0x3E8E41
    static let spinachLeafShade: UInt32 = 0x2C6B2E
    // Alyssum, native violet, zinnia, marigold
    static let alyssumViolet: UInt32 = 0x8E5BC4
    static let alyssumVioletShade: UInt32 = 0x6C3FA0
    static let violetPurple: UInt32 = 0x6E4AB0
    static let violetPurpleShade: UInt32 = 0x523383
    static let zinniaPink: UInt32 = 0xE8537A
    static let zinniaPinkShade: UInt32 = 0xC23A5E
    static let marigoldOrange: UInt32 = 0xF7A11A
    static let marigoldOrangeShade: UInt32 = 0xD9800F
    // Parsley, chives, coriander, dill, thyme
    static let parsleyLeaf: UInt32 = 0x4F9A3A
    static let parsleyLeafShade: UInt32 = 0x3A7A2B
    static let chiveLilac: UInt32 = 0xB07CC6
    static let chiveLilacShade: UInt32 = 0x8A5AA3
    static let corianderLeaf: UInt32 = 0x6FAE4E
    static let corianderLeafShade: UInt32 = 0x52903A
    static let dillYellow: UInt32 = 0xF2D54E
    static let dillYellowShade: UInt32 = 0xD4B232
    static let thymeLeaf: UInt32 = 0x8FA66A
    static let thymeLeafShade: UInt32 = 0x6B7F4C
}

/// Blends two 0xRRGGBB values as hex, so blends can be chained (for example a fade over a colour change).
func blendHex(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
    let k = clamp01(t)
    func lerp(_ shift: UInt32) -> UInt32 {
        let x = Double((a >> shift) & 255), y = Double((b >> shift) & 255)
        return UInt32((x + (y - x) * k).rounded())
    }
    return (lerp(16) << 16) | (lerp(8) << 8) | lerp(0)
}

/// Per-species proportions, in unit-square terms.
struct Species {
    let maxHeight: Double
    let stemWidth: Double
    let leafCount: Int
    let leafLength: Double
    let leafAspect: Double
    let leafSpread: Double   // how far leaves fan out from straight up (radians)
    let leafFrom: Double     // stem fraction where the first leaf attaches
    let leafTo: Double      // stem fraction where the last leaf attaches
    let canopy: Double      // full-grown half width of the plant (unit square), used for its shadow

    static func of(_ f: FlowerType) -> Species {
        switch f {
        case .sunflower:
            Species(maxHeight: 0.44, stemWidth: 0.03, leafCount: 5, leafLength: 0.25, leafAspect: 0.42,
                    leafSpread: 0.95, leafFrom: 0.2, leafTo: 0.8, canopy: 0.2)
        case .daisy:
            Species(maxHeight: 0.42, stemWidth: 0.024, leafCount: 4, leafLength: 0.2, leafAspect: 0.42,
                    leafSpread: 0.95, leafFrom: 0.22, leafTo: 0.8, canopy: 0.17)
        case .poppy:
            Species(maxHeight: 0.42, stemWidth: 0.022, leafCount: 4, leafLength: 0.22, leafAspect: 0.5,
                    leafSpread: 0.9, leafFrom: 0.2, leafTo: 0.75, canopy: 0.17)
        case .lavender:
            Species(maxHeight: 0.46, stemWidth: 0.018, leafCount: 5, leafLength: 0.24, leafAspect: 0.2,
                    leafSpread: 1.3, leafFrom: 0.1, leafTo: 0.4, canopy: 0.12)
        // Chocolate lily: slender stem, strap leaves at the base (drawn in FlowerArtPlants.swift).
        case .chocolateLily:
            Species(maxHeight: 0.4, stemWidth: 0.014, leafCount: 5, leafLength: 0.3, leafAspect: 0.12,
                    leafSpread: 0.4, leafFrom: 0, leafTo: 0, canopy: 0.13)
        // Common everlasting: a low silvery mat with short stems of button heads.
        case .commonEverlasting:
            Species(maxHeight: 0.24, stemWidth: 0.01, leafCount: 9, leafLength: 0.17, leafAspect: 0.38,
                    leafSpread: 1.0, leafFrom: 0, leafTo: 0, canopy: 0.26)
        case .calendula:
            Species(maxHeight: 0.38, stemWidth: 0.022, leafCount: 4, leafLength: 0.2, leafAspect: 0.42,
                    leafSpread: 0.95, leafFrom: 0.22, leafTo: 0.8, canopy: 0.17)
        // Cosmos: tall and thin, with feathery leaves.
        case .cosmos:
            Species(maxHeight: 0.5, stemWidth: 0.014, leafCount: 12, leafLength: 0.2, leafAspect: 0.12,
                    leafSpread: 1.0, leafFrom: 0.12, leafTo: 0.72, canopy: 0.13)
        case .basil:
            Species(maxHeight: 0.3, stemWidth: 0.02, leafCount: 8, leafLength: 0.2, leafAspect: 0.6,
                    leafSpread: 1.1, leafFrom: 0.15, leafTo: 0.9, canopy: 0.22)
        case .zucchini:
            Species(maxHeight: 0.3, stemWidth: 0.03, leafCount: 4, leafLength: 0.36, leafAspect: 0.5,
                    leafSpread: 0.95, leafFrom: 0.2, leafTo: 0.7, canopy: 0.3)
        case .lettuce:
            Species(maxHeight: 0.08, stemWidth: 0.01, leafCount: 9, leafLength: 0.2, leafAspect: 0.5,
                    leafSpread: 1.3, leafFrom: 0, leafTo: 0, canopy: 0.22)
        case .beetroot:
            Species(maxHeight: 0.2, stemWidth: 0.014, leafCount: 6, leafLength: 0.2, leafAspect: 0.6,
                    leafSpread: 1.2, leafFrom: 0.05, leafTo: 0.4, canopy: 0.2)
        case .broccoli:
            Species(maxHeight: 0.3, stemWidth: 0.03, leafCount: 6, leafLength: 0.22, leafAspect: 0.5,
                    leafSpread: 0.9, leafFrom: 0.2, leafTo: 0.8, canopy: 0.2)
        case .carrot:
            Species(maxHeight: 0.26, stemWidth: 0.012, leafCount: 10, leafLength: 0.18, leafAspect: 0.2,
                    leafSpread: 1.1, leafFrom: 0.15, leafTo: 0.9, canopy: 0.16)
        case .rocket:
            Species(maxHeight: 0.18, stemWidth: 0.012, leafCount: 8, leafLength: 0.16, leafAspect: 0.5,
                    leafSpread: 1.2, leafFrom: 0, leafTo: 0.5, canopy: 0.18)
        case .corn:
            Species(maxHeight: 0.5, stemWidth: 0.035, leafCount: 5, leafLength: 0.3, leafAspect: 0.3,
                    leafSpread: 0.8, leafFrom: 0.2, leafTo: 0.8, canopy: 0.12)
        case .broadBean:
            Species(maxHeight: 0.4, stemWidth: 0.02, leafCount: 5, leafLength: 0.2, leafAspect: 0.5,
                    leafSpread: 0.9, leafFrom: 0.2, leafTo: 0.7, canopy: 0.16)
        case .radish:
            Species(maxHeight: 0.12, stemWidth: 0.01, leafCount: 7, leafLength: 0.14, leafAspect: 0.5,
                    leafSpread: 1.3, leafFrom: 0, leafTo: 0.4, canopy: 0.16)
        case .spinach:
            Species(maxHeight: 0.14, stemWidth: 0.01, leafCount: 8, leafLength: 0.16, leafAspect: 0.5,
                    leafSpread: 1.3, leafFrom: 0, leafTo: 0.4, canopy: 0.17)
        case .alyssum:
            Species(maxHeight: 0.1, stemWidth: 0.008, leafCount: 7, leafLength: 0.1, leafAspect: 0.5,
                    leafSpread: 1.2, leafFrom: 0.1, leafTo: 0.6, canopy: 0.18)
        case .nativeViolet:
            Species(maxHeight: 0.1, stemWidth: 0.006, leafCount: 6, leafLength: 0.08, leafAspect: 0.6,
                    leafSpread: 1.3, leafFrom: 0, leafTo: 0.5, canopy: 0.18)
        case .zinnia:
            Species(maxHeight: 0.44, stemWidth: 0.022, leafCount: 4, leafLength: 0.18, leafAspect: 0.5,
                    leafSpread: 0.9, leafFrom: 0.2, leafTo: 0.7, canopy: 0.16)
        case .billyButtons:
            Species(maxHeight: 0.5, stemWidth: 0.012, leafCount: 3, leafLength: 0.12, leafAspect: 0.3,
                    leafSpread: 0.8, leafFrom: 0.1, leafTo: 0.5, canopy: 0.1)
        case .bulbineLily:
            Species(maxHeight: 0.3, stemWidth: 0.01, leafCount: 6, leafLength: 0.22, leafAspect: 0.2,
                    leafSpread: 0.9, leafFrom: 0, leafTo: 0.5, canopy: 0.15)
        case .marigold:
            Species(maxHeight: 0.36, stemWidth: 0.024, leafCount: 6, leafLength: 0.18, leafAspect: 0.5,
                    leafSpread: 1.0, leafFrom: 0.2, leafTo: 0.8, canopy: 0.16)
        case .parsley:
            Species(maxHeight: 0.22, stemWidth: 0.01, leafCount: 8, leafLength: 0.14, leafAspect: 0.6,
                    leafSpread: 1.2, leafFrom: 0, leafTo: 0.6, canopy: 0.18)
        case .chives:
            Species(maxHeight: 0.36, stemWidth: 0.008, leafCount: 3, leafLength: 0.36, leafAspect: 0.1,
                    leafSpread: 0.3, leafFrom: 0, leafTo: 0.6, canopy: 0.08)
        case .coriander:
            Species(maxHeight: 0.3, stemWidth: 0.012, leafCount: 6, leafLength: 0.14, leafAspect: 0.5,
                    leafSpread: 1.0, leafFrom: 0.2, leafTo: 0.8, canopy: 0.14)
        case .dill:
            Species(maxHeight: 0.46, stemWidth: 0.012, leafCount: 6, leafLength: 0.16, leafAspect: 0.4,
                    leafSpread: 1.0, leafFrom: 0.2, leafTo: 0.8, canopy: 0.14)
        case .thyme:
            Species(maxHeight: 0.14, stemWidth: 0.01, leafCount: 6, leafLength: 0.08, leafAspect: 0.4,
                    leafSpread: 1.3, leafFrom: 0.1, leafTo: 0.6, canopy: 0.14)
        }
    }
}

/// The main stem as a gently bending curve from the soil (t = 0) to its tip (t = 1).
struct Stalk {
    let height: Double
    let lean: Double      // sideways offset of the tip at full height
    let sway: Double      // -1...1
    let droop: Double     // 0...1
    let droopDir: Double  // +1 or -1: which way the top bows

    /// Unit-square point at fraction t along the stem. Bending grows with t squared.
    func point(_ t: Double) -> (x: Double, y: Double) {
        let bend = t * t
        let x = 0.5 + lean * pow(t, 1.5) + sway * 0.07 * bend + droop * droopDir * 0.27 * bend
        let y = 0.84 - height * t + droop * 0.2 * bend
        return (x, y)
    }
}

struct Drawer {
    var ctx: GraphicsContext
    let s: CGFloat
    let origin: CGPoint

    /// Unit-square coordinates to canvas points.
    func pt(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: origin.x + CGFloat(x) * s, y: origin.y + CGFloat(y) * s)
    }

    /// Offsets a canvas point by unit-square distances.
    func at(_ c: CGPoint, _ dx: Double, _ dy: Double) -> CGPoint {
        CGPoint(x: c.x + CGFloat(dx) * s, y: c.y + CGFloat(dy) * s)
    }

    func oval(_ c: CGPoint, _ w: Double, _ h: Double, angle: Double = 0, _ color: Color) {
        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: .radians(angle))
        let W = CGFloat(w) * s, H = CGFloat(h) * s
        g.fill(Path(ellipseIn: CGRect(x: -W / 2, y: -H / 2, width: W, height: H)), with: .color(color))
    }

    /// Shape with a darker copy nudged down-right beneath it.
    func shaded(_ c: CGPoint, _ w: Double, _ h: Double, angle: Double = 0, _ color: Color, _ shade: Color) {
        oval(at(c, 0.012, 0.016), w, h, angle: angle, shade)
        oval(c, w, h, angle: angle, color)
    }

    func disc(_ c: CGPoint, _ d: Double, _ color: Color, _ shade: Color, alpha a: Double = 1) {
        shaded(c, d, d, color.opacity(a), shade.opacity(a))
    }

    func leaf(from base: CGPoint, angle: Double, length: Double, aspect: Double = 0.42,
              _ color: Color = Ink.leaf, _ shade: Color = Ink.leafShade) {
        let c = at(base, cos(angle) * length / 2, sin(angle) * length / 2)
        shaded(c, length, length * aspect, angle: angle, color, shade)
    }

    func polyline(_ pts: [CGPoint], width: Double, _ color: Color) {
        guard let first = pts.first else { return }
        var p = Path()
        p.move(to: first)
        for q in pts.dropFirst() { p.addLine(to: q) }
        ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: CGFloat(width) * s, lineCap: .round, lineJoin: .round))
    }

    func stalk(_ st: Stalk, width: Double, _ color: Color) {
        let pts = (0...12).map { i -> CGPoint in
            let q = st.point(Double(i) / 12)
            return pt(q.x, q.y)
        }
        polyline(pts, width: width, color)
    }

    /// A tiny, soft dab of soil at the stem's foot, in the soil colour, so the plant seems to stand in the patch
    /// rather than on a pancake of its own.
    func mound(soil: Color = Ink.soil, soilShade: Color = Ink.soilShade) {
        let base = pt(0.5, 0.86)
        oval(base, 0.30, 0.07, soil.opacity(0.45))
        oval(at(base, 0, 0.008), 0.2, 0.045, soilShade.opacity(0.2))
    }

    func draw(flower: FlowerType?, progress: Double, droop: Double, fade: Double, openness: Double,
              variation: UInt64, sway: Double, isSeedHead: Bool, dead: Bool,
              soil: Color = Ink.soil, soilShade: Color = Ink.soilShade) {
        mound(soil: soil, soilShade: soilShade)
        guard let flower else { return }

        let sp = Species.of(flower)
        let p = clamp01(progress)
        let fadeV = clamp01(fade)
        let openV = clamp01(openness)
        let rnd: (UInt64) -> Double = { unitHash(variation, $0) }

        // Per-plant variation, drawn in a fixed order so it is deterministic.
        let heightVar = (rnd(0) * 2 - 1) * 0.08
        let lean = (rnd(1) * 2 - 1) * 0.05
        let headTurn = (rnd(2) * 2 - 1) * 0.2
        let petalDelta = Int(rnd(3) * 5) - 2

        let droopV = dead ? max(clamp01(droop), 0.9) : clamp01(droop)
        let grow = isSeedHead ? 1 : 1 - (1 - p) * (1 - p)   // ease-out: quick first sprout, smooth after
        let pl = isSeedHead ? 1 : p
        let stalkModel = Stalk(height: sp.maxHeight * (1 + heightVar) * grow * (1 - 0.1 * droopV),
                               lean: lean, sway: min(1, max(-1, sway)), droop: droopV,
                               droopDir: lean < 0 ? -1 : 1)

        // The seed sits on the soil and gives way to the sprout.
        if !dead && !isSeedHead {
            let seedA = 1 - smooth(p, 0.02, 0.1)
            if seedA > 0.001 {
                shaded(pt(0.5, 0.8), 0.1, 0.065, angle: -0.4, Ink.seed.opacity(seedA), Ink.creamShade.opacity(seedA))
            }
        }
        // Plants with their own silhouette (FlowerArtPlants.swift) draw their stem and leaves themselves.
        // Lettuce has no tall stem, so it is allowed to draw from its very first sprout.
        if !dead, Drawer.customFlowers.contains(flower) {
            if flower == .lettuce || stalkModel.height >= 0.004 {
                drawCustomPlant(PlantPose(flower: flower, sp: sp, stalk: stalkModel, progress: pl, grow: grow,
                                          droop: droopV, fade: fadeV, openness: openV, seed: variation,
                                          turn: headTurn, isSeedHead: isSeedHead))
            }
            return
        }
        if stalkModel.height < 0.004 { return }

        if dead {
            stalk(stalkModel, width: 0.026, Color(hex: Hue.deadStem))
            for (i, u) in [0.3, 0.6].enumerated() {
                let q = stalkModel.point(u)
                let side: Double = i % 2 == 0 ? -1 : 1
                leaf(from: pt(q.x, q.y), angle: side < 0 ? -2.7 : -0.3, length: sp.leafLength * 0.8, aspect: 0.4,
                     Color(hex: Hue.dryTan), Color(hex: Hue.dryTanShade))
            }
            return
        }

        stalk(stalkModel, width: sp.stemWidth * (0.7 + 0.3 * grow), Ink.stem)

        // Calendula has light green leaves, cosmos has feathery darker green ones; the rest use the usual green.
        let leafHex: UInt32, leafShadeHex: UInt32
        switch flower {
        case .calendula: (leafHex, leafShadeHex) = (Hue.calLeaf, Hue.calLeafShade)
        case .cosmos: (leafHex, leafShadeHex) = (Hue.cosmosLeaf, Hue.cosmosLeafShade)
        default: (leafHex, leafShadeHex) = (Hue.leaf, Hue.leafShade)
        }

        for i in 0..<sp.leafCount {
            let fi = Double(i)
            let grown = smooth(pl, 0.05 + 0.07 * fi, 0.2 + 0.07 * fi)
            let size = sp.leafLength * (0.35 + 0.65 * smooth(pl, 0, 0.5)) * grown
            if size < 0.004 { continue }
            let u = sp.leafCount > 1 ? sp.leafFrom + (sp.leafTo - sp.leafFrom) * fi / Double(sp.leafCount - 1) : sp.leafFrom
            let side: Double = i % 2 == 0 ? -1 : 1
            // Leaves fan out from straight up, then sag with droop.
            let angle = -Double.pi / 2 + side * sp.leafSpread + side * droopV * 1.2
                + (rnd(10 + UInt64(i)) * 2 - 1) * 0.22
            let q = stalkModel.point(u)
            leaf(from: pt(q.x, q.y), angle: angle, length: size, aspect: sp.leafAspect,
                 Color(hex: leafHex), Color(hex: leafShadeHex))
        }

        let tipQ = stalkModel.point(1)
        let tip = pt(tipQ.x, tipQ.y)

        if isSeedHead {
            if flower == .lavender {
                spike(stalkModel, scale: 1, fade: 0, seed: variation, dry: true)
            } else {
                seedHead(flower, at: tip, turn: headTurn, seed: variation)
            }
            return
        }

        let budA = smooth(p, 0.64, 0.72)     // bud appears
        let swell = smooth(p, 0.72, 0.9)     // bud swells
        let openK = openV * smooth(p, 0.9, 1.0) // flower begins opening at 0.9

        if flower == .lavender {
            if budA > 0.001 {
                spike(stalkModel, scale: budA * (0.7 + 0.5 * swell), fade: fadeV, seed: variation)
            }
            return
        }

        if budA > 0.001 {
            let alpha = 1 - smooth(openK, 0.05, 0.6)
            if alpha > 0.01 {
                bud(flower, at: tip, scale: budA * (1.0 + 0.5 * swell), alpha: alpha)
            }
        }
        if openK > 0.01 {
            bloom(flower, at: tip, openK: openK, fade: fadeV, delta: petalDelta, turn: headTurn, seed: variation)
        }
    }

    func bud(_ f: FlowerType, at c: CGPoint, scale k: Double, alpha a: Double) {
        let tint: (UInt32, UInt32)
        switch f {
        case .sunflower: tint = (Hue.sun, Hue.sunShade)
        case .daisy: tint = (Hue.cream, Hue.creamShade)
        case .poppy: tint = (Hue.poppy, Hue.poppyShade)
        case .lavender: tint = (Hue.lilac, Hue.lilacShade)
        case .calendula: tint = (Hue.calendula, Hue.calendulaShade)
        case .cosmos: tint = (Hue.cosmosPink, Hue.cosmosPinkShade)
        case .beetroot: tint = (Hue.beetRoot, Hue.beetRootShade)
        case .broccoli: tint = (Hue.broccoliHead, Hue.broccoliHeadShade)
        case .carrot: tint = (Hue.carrotFlower, Hue.carrotFlowerShade)
        case .rocket: tint = (Hue.rocketLeaf, Hue.rocketLeafShade)
        case .corn, .billyButtons, .bulbineLily: tint = (Hue.straw, Hue.strawShade)
        case .broadBean: tint = (Hue.beanFlower, Hue.beanFlowerShade)
        case .radish: tint = (Hue.radishRed, Hue.radishRedShade)
        case .spinach: tint = (Hue.spinachLeaf, Hue.spinachLeafShade)
        case .alyssum: tint = (Hue.alyssumViolet, Hue.alyssumVioletShade)
        case .nativeViolet: tint = (Hue.violetPurple, Hue.violetPurpleShade)
        case .zinnia: tint = (Hue.zinniaPink, Hue.zinniaPinkShade)
        case .marigold: tint = (Hue.marigoldOrange, Hue.marigoldOrangeShade)
        case .parsley: tint = (Hue.parsleyLeaf, Hue.parsleyLeafShade)
        case .chives: tint = (Hue.chiveLilac, Hue.chiveLilacShade)
        case .coriander: tint = (Hue.corianderLeaf, Hue.corianderLeafShade)
        case .dill: tint = (Hue.dillYellow, Hue.dillYellowShade)
        case .thyme: tint = (Hue.thymeLeaf, Hue.thymeLeafShade)
        case .chocolateLily, .commonEverlasting, .basil, .zucchini, .lettuce: return // drawn in FlowerArtPlants.swift
        }
        // green sepals wrap the closed bud
        shaded(at(c, -0.03 * k, 0.03 * k), 0.085 * k, 0.2 * k, angle: -0.5, Ink.leaf.opacity(a), Ink.leafShade.opacity(a))
        shaded(at(c, 0.03 * k, 0.03 * k), 0.085 * k, 0.2 * k, angle: 0.5, Ink.leaf.opacity(a), Ink.leafShade.opacity(a))
        shaded(at(c, 0, -0.03 * k), 0.1 * k, 0.14 * k, Color(hex: tint.0).opacity(a), Color(hex: tint.1).opacity(a))
    }

    /// Petals arranged in a ring. Openness scales them out from the centre; fade drops them one by one.
    func petalRing(_ c: CGPoint, count n: Int, length: Double, width: Double, radius: Double,
                   _ colour: UInt32, _ shade: UInt32, openK: Double, fade: Double, turn: Double, seed: UInt64) {
        let appear = smooth(openK, 0, 0.25)
        for i in 0..<n {
            let rank = unitHash(seed, 100 + UInt64(i))
            let fall = smooth(fade, rank * 0.85, rank * 0.85 + 0.15)
            let vis = (1 - fall) * appear
            if vis < 0.01 { continue }
            let a = Double(i) / Double(n) * 2 * Double.pi + turn
            let rad = radius * (0.25 + 0.75 * openK)
            let centre = at(c, cos(a) * rad, sin(a) * rad + fall * 0.1)
            let size = 0.4 + 0.6 * openK
            shaded(centre, length * size * vis, width * size * vis, angle: a + fall * 0.6,
                   mix(colour, Hue.faded, fade * 0.8), mix(shade, Hue.faded, fade * 0.8))
        }
    }

    func bloom(_ f: FlowerType, at c: CGPoint, openK: Double, fade: Double, delta: Int, turn: Double, seed: UInt64) {
        let discA = smooth(openK, 0.02, 0.3)
        switch f {
        case .sunflower:
            petalRing(c, count: 16 + delta, length: 0.17, width: 0.07, radius: 0.15,
                      Hue.sun, Hue.sunShade, openK: openK, fade: fade, turn: turn, seed: seed)
            let d = 0.25 * (0.5 + 0.5 * openK)
            disc(c, d, Ink.brown, Ink.brownShade, alpha: discA)
            let k = d / 0.25
            for (dx, dy) in [(-0.04, -0.03), (0.04, -0.02), (0.0, 0.04), (-0.03, 0.03), (0.04, 0.04)] {
                oval(at(c, dx * k, dy * k), 0.025 * k, 0.025 * k, Ink.brownShade.opacity(discA))
            }
        case .daisy:
            petalRing(c, count: 12 + delta, length: 0.16, width: 0.075, radius: 0.1,
                      Hue.cream, Hue.creamShade, openK: openK, fade: fade, turn: turn, seed: seed)
            disc(c, 0.13 * (0.6 + 0.4 * openK), Ink.gold, Ink.goldShade, alpha: discA)
        case .poppy:
            petalRing(c, count: max(3, 4 + delta), length: 0.2, width: 0.19, radius: 0.1,
                      Hue.poppy, Hue.poppyShade, openK: openK, fade: fade, turn: turn, seed: seed)
            disc(c, 0.09, Ink.dark, Ink.dark, alpha: discA)
        case .lavender:
            break
        case .calendula:
            petalRing(c, count: 18 + delta, length: 0.17, width: 0.042, radius: 0.1,
                      Hue.calendula, Hue.calendulaShade, openK: openK, fade: fade, turn: turn, seed: seed)
            disc(c, 0.09 * (0.6 + 0.4 * openK), Color(hex: Hue.calendulaCentre), Color(hex: Hue.calendulaCentreShade), alpha: discA)
        case .cosmos:
            // Exactly eight broad petals, unlike the varied rings above.
            petalRing(c, count: 8, length: 0.2, width: 0.12, radius: 0.09,
                      Hue.cosmosPink, Hue.cosmosPinkShade, openK: openK, fade: fade, turn: turn, seed: seed)
            disc(c, 0.09 * (0.6 + 0.4 * openK), Color(hex: Hue.cosmosCentre), Color(hex: Hue.cosmosCentreShade), alpha: discA)
        case .beetroot:
            petalRing(c, count: 8, length: 0.13, width: 0.06, radius: 0.06, Hue.beetLeaf, Hue.beetLeafShade,
                      openK: openK, fade: fade, turn: turn, seed: seed)
            disc(c, 0.06, Color(hex: Hue.beetRoot), Color(hex: Hue.beetRootShade), alpha: discA)
        case .broccoli:
            petalRing(c, count: 9, length: 0.1, width: 0.1, radius: 0.05, Hue.broccoliHead, Hue.broccoliHeadShade,
                      openK: openK, fade: fade, turn: turn, seed: seed)
        case .carrot:
            petalRing(c, count: 12, length: 0.12, width: 0.035, radius: 0.05, Hue.carrotFlower, Hue.carrotFlowerShade,
                      openK: openK, fade: fade, turn: turn, seed: seed)
        case .rocket:
            petalRing(c, count: 8, length: 0.09, width: 0.05, radius: 0.05, Hue.rocketLeaf, Hue.rocketLeafShade,
                      openK: openK, fade: fade, turn: turn, seed: seed)
        case .corn:
            petalRing(c, count: 4, length: 0.12, width: 0.06, radius: 0.03, Hue.straw, Hue.strawShade,
                      openK: openK, fade: fade, turn: turn, seed: seed)
        case .broadBean:
            petalRing(c, count: 5, length: 0.09, width: 0.08, radius: 0.06, Hue.beanFlower, Hue.beanFlowerShade,
                      openK: openK, fade: fade, turn: turn, seed: seed)
        case .radish:
            petalRing(c, count: 7, length: 0.12, width: 0.07, radius: 0.05, Hue.radishRed, Hue.radishRedShade,
                      openK: openK, fade: fade, turn: turn, seed: seed)
        case .spinach:
            petalRing(c, count: 9, length: 0.11, width: 0.06, radius: 0.06, Hue.spinachLeaf, Hue.spinachLeafShade,
                      openK: openK, fade: fade, turn: turn, seed: seed)
        case .alyssum:
            petalRing(c, count: 14, length: 0.06, width: 0.05, radius: 0.08, Hue.alyssumViolet, Hue.alyssumVioletShade,
                      openK: openK, fade: fade, turn: turn, seed: seed)
        case .nativeViolet:
            petalRing(c, count: 5, length: 0.07, width: 0.06, radius: 0.05, Hue.violetPurple, Hue.violetPurpleShade,
                      openK: openK, fade: fade, turn: turn, seed: seed)
        case .zinnia:
            petalRing(c, count: 16, length: 0.16, width: 0.07, radius: 0.09, Hue.zinniaPink, Hue.zinniaPinkShade,
                      openK: openK, fade: fade, turn: turn, seed: seed)
            disc(c, 0.08 * (0.6 + 0.4 * openK), Color(hex: Hue.straw), Color(hex: Hue.strawShade), alpha: discA)
        case .billyButtons:
            petalRing(c, count: 18, length: 0.05, width: 0.05, radius: 0.06, Hue.straw, Hue.strawShade,
                      openK: openK, fade: fade, turn: turn, seed: seed)
        case .bulbineLily:
            petalRing(c, count: 6, length: 0.14, width: 0.04, radius: 0.05, Hue.straw, Hue.strawShade,
                      openK: openK, fade: fade, turn: turn, seed: seed)
        case .marigold:
            petalRing(c, count: 16, length: 0.14, width: 0.07, radius: 0.09, Hue.marigoldOrange, Hue.marigoldOrangeShade,
                      openK: openK, fade: fade, turn: turn, seed: seed)
            disc(c, 0.08 * (0.6 + 0.4 * openK), Color(hex: Hue.calendulaCentre), Color(hex: Hue.calendulaCentreShade), alpha: discA)
        case .parsley:
            petalRing(c, count: 10, length: 0.08, width: 0.05, radius: 0.05, Hue.parsleyLeaf, Hue.parsleyLeafShade,
                      openK: openK, fade: fade, turn: turn, seed: seed)
        case .chives:
            petalRing(c, count: 14, length: 0.04, width: 0.04, radius: 0.06, Hue.chiveLilac, Hue.chiveLilacShade,
                      openK: openK, fade: fade, turn: turn, seed: seed)
        case .coriander:
            petalRing(c, count: 10, length: 0.08, width: 0.05, radius: 0.05, Hue.corianderLeaf, Hue.corianderLeafShade,
                      openK: openK, fade: fade, turn: turn, seed: seed)
        case .dill:
            petalRing(c, count: 12, length: 0.06, width: 0.03, radius: 0.08, Hue.dillYellow, Hue.dillYellowShade,
                      openK: openK, fade: fade, turn: turn, seed: seed)
        case .thyme:
            petalRing(c, count: 8, length: 0.04, width: 0.03, radius: 0.03, Hue.thymeLeaf, Hue.thymeLeafShade,
                      openK: openK, fade: fade, turn: turn, seed: seed)
        case .chocolateLily, .commonEverlasting, .basil, .zucchini, .lettuce:
            break // drawn in FlowerArtPlants.swift
        }
    }

    /// Dried seed head: papery stubs and a brown disc, a fluffy puff, or a pod with pores.
    func seedHead(_ f: FlowerType, at c: CGPoint, turn: Double, seed: UInt64) {
        switch f {
        case .calendula:
            // A ring of curved, dry seeds around a small brown disc.
            for k in 0..<10 {
                let a = Double(k) / 10 * 2 * Double.pi + turn
                shaded(at(c, cos(a) * 0.075, sin(a) * 0.075), 0.055, 0.024, angle: a + 0.6,
                       Color(hex: Hue.dryTan), Color(hex: Hue.dryTanShade))
            }
            disc(c, 0.05, Ink.brown, Ink.brownShade)
        case .cosmos:
            // Eight thin dry stubs with a brown centre.
            for k in 0..<8 {
                let a = Double(k) / 8 * 2 * Double.pi + turn
                shaded(at(c, cos(a) * 0.06, sin(a) * 0.06), 0.09, 0.018, angle: a,
                       Color(hex: Hue.dryTan), Color(hex: Hue.dryTanShade))
            }
            disc(c, 0.045, Ink.brown, Ink.brownShade)
        case .beetroot, .broccoli, .carrot, .rocket, .corn, .broadBean, .radish, .spinach, .alyssum, .nativeViolet,
             .zinnia, .billyButtons, .bulbineLily, .marigold, .parsley, .chives, .coriander, .dill, .thyme:
            // Spent heads of the newer plants: a faded ring of dry stubs around a brown centre.
            petalRing(c, count: 8, length: 0.06, width: 0.03, radius: 0.07, Hue.dryTan, Hue.dryTanShade,
                      openK: 1, fade: 0, turn: turn, seed: seed)
            disc(c, 0.04, Ink.brown, Ink.brownShade)
        case .chocolateLily, .commonEverlasting, .basil, .zucchini, .lettuce:
            break // drawn in FlowerArtPlants.swift
        case .sunflower:
            petalRing(c, count: 14, length: 0.085, width: 0.05, radius: 0.16,
                      Hue.dryTan, Hue.dryTanShade, openK: 1, fade: 0, turn: turn, seed: seed)
            disc(c, 0.22, Ink.brown, Ink.brownShade)
            for k in 0..<12 {
                let a = Double(k) / 12 * 2 * Double.pi + turn
                let r = k % 2 == 0 ? 0.035 : 0.075
                oval(at(c, cos(a) * r, sin(a) * r), 0.02, 0.02, Ink.brownShade)
            }
        case .daisy:
            for k in 0..<14 {
                let a = Double(k) / 14 * 2 * Double.pi + turn
                shaded(at(c, cos(a) * 0.06, sin(a) * 0.06), 0.1, 0.035, angle: a,
                       Color(hex: Hue.fluff), Color(hex: Hue.fluffShade))
            }
            disc(c, 0.05, Ink.brown, Ink.brownShade)
        case .poppy:
            disc(c, 0.14, Ink.brown, Ink.brownShade)
            oval(at(c, 0, -0.06), 0.15, 0.06, Ink.brownShade)
            for k in 0..<6 {
                oval(at(c, (Double(k) - 2.5) * 0.028, -0.06), 0.02, 0.02, Ink.dark)
            }
        case .lavender:
            break
        }
    }

    /// Lavender: a tapered spike of open whorls. Each whorl is three small florets set around a point on the
    /// stem, spaced so the stem shows between them (a dense column reads as a blob at small sizes).
    /// `scale` 0...1 grows the spike from the top of the stem down.
    func spike(_ st: Stalk, scale k: Double, fade: Double, seed: UInt64, dry: Bool = false) {
        let fill = dry ? Hue.dryTan : Hue.lilac
        let shadeHex = dry ? Hue.dryTanShade : Hue.lilacShade
        let fadeC = dry ? 0 : fade * 0.8
        var idx: UInt64 = 0

        func whorl(_ c: CGPoint, _ r: Double) {
            // Florets alternate left, right and up, so each whorl is a loose ring rather than a clump.
            let offsets: [(Double, Double)] = [(-0.8, 0.1), (0.8, -0.1), (0, -0.9)]
            for (dx, dy) in offsets {
                idx += 1
                let rank = unitHash(seed, 300 + idx)
                let fall = dry ? 0 : smooth(fade, rank * 0.85, rank * 0.85 + 0.15)
                let vis = 1 - fall
                if vis < 0.02 { continue }
                let d = r * 0.6 * vis
                shaded(at(c, dx * r, dy * r + fall * 0.08), d, d,
                       mix(fill, Hue.faded, fadeC), mix(shadeHex, Hue.faded, fadeC))
            }
        }

        // Side spikes first, so the main spike sits on top.
        let branches: [(t: Double, angle: Double, length: Double, n: Int)] = [
            (1 - 0.42 * k, -2.3, 0.2 * k, 3),
            (1 - 0.24 * k, -0.85, 0.16 * k, 2),
        ]
        for b in branches where k > 0.01 {
            let q = st.point(b.t)
            let o = pt(q.x, q.y)
            let end = at(o, cos(b.angle) * b.length, sin(b.angle) * b.length)
            polyline([o, end], width: 0.01, Ink.stem)
            for j in 0..<b.n {
                let u = Double(j + 1) / Double(b.n)
                let r = (0.05 - 0.015 * u) * (0.6 + 0.4 * k)
                whorl(at(o, cos(b.angle) * b.length * u, sin(b.angle) * b.length * u), r)
            }
        }

        // Main spike: whorls taper toward the tip, with the stem visible between them.
        let tStart = 1 - 0.5 * k
        let n = 6
        for j in 0..<n {
            let u = Double(j) / Double(n - 1)
            let q = st.point(tStart + (1 - tStart) * u)
            let r = (0.06 - 0.02 * u) * (0.6 + 0.4 * k)
            whorl(pt(q.x, q.y), r)
        }
    }
}
