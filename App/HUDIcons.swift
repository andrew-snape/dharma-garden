import SwiftUI

/// The currency icon: an orange carrot with green tops. Sized by `size`, the height of the icon.
struct CarrotIcon: View {
    var size: CGFloat = 16

    var body: some View {
        ZStack {
            CarrotTops().fill(Color(red: 0.30, green: 0.66, blue: 0.28))
            CarrotBody().fill(Color(red: 0.96, green: 0.52, blue: 0.10))
            CarrotRidges().stroke(Color(red: 0.74, green: 0.36, blue: 0.05), lineWidth: max(0.6, size / 18))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The root of the carrot: a rounded cone running from the top left down to a point at the bottom right.
private struct CarrotBody: Shape {
    func path(in r: CGRect) -> Path {
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y) }
        var path = Path()
        path.move(to: p(0.30, 0.30))
        path.addQuadCurve(to: p(0.70, 0.46), control: p(0.52, 0.26))
        path.addQuadCurve(to: p(0.92, 0.96), control: p(0.82, 0.70))
        path.addQuadCurve(to: p(0.30, 0.30), control: p(0.34, 0.74))
        path.closeSubpath()
        return path
    }
}

/// Short lines across the root.
private struct CarrotRidges: Shape {
    func path(in r: CGRect) -> Path {
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y) }
        var path = Path()
        path.move(to: p(0.40, 0.42)); path.addLine(to: p(0.50, 0.46))
        path.move(to: p(0.50, 0.58)); path.addLine(to: p(0.60, 0.62))
        path.move(to: p(0.62, 0.74)); path.addLine(to: p(0.70, 0.78))
        return path
    }
}

/// Three leaves fanning from the shoulder of the carrot.
private struct CarrotTops: Shape {
    func path(in r: CGRect) -> Path {
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y) }
        var path = Path()
        for (tip, c1, c2) in [(p(0.10, 0.02), p(0.24, 0.02), p(0.10, 0.14)),
                              (p(0.34, 0.00), p(0.44, 0.06), p(0.26, 0.10)),
                              (p(0.58, 0.10), p(0.54, 0.20), p(0.44, 0.10))] {
            path.move(to: p(0.46, 0.34))
            path.addQuadCurve(to: tip, control: c1)
            path.addQuadCurve(to: p(0.46, 0.34), control: c2)
        }
        return path
    }
}

/// A hand weeder: a narrow steel blade with a forked V tip, on a wooden handle. Drawn upright with the tip at the top.
struct HandWeederIcon: View {
    var color: Color = .primary
    var body: some View {
        ZStack {
            WeederBlade().fill(color)
            WeederHandle().fill(color.opacity(0.7))
        }
        .accessibilityHidden(true)
    }
}

private struct WeederBlade: Shape {
    func path(in r: CGRect) -> Path {
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y) }
        var path = Path()
        path.move(to: p(0.38, 0.00))      // left prong
        path.addLine(to: p(0.50, 0.20))   // bottom of the V
        path.addLine(to: p(0.62, 0.00))   // right prong
        path.addLine(to: p(0.60, 0.50))
        path.addLine(to: p(0.54, 0.60))
        path.addLine(to: p(0.46, 0.60))
        path.addLine(to: p(0.40, 0.50))
        path.closeSubpath()
        return path
    }
}

private struct WeederHandle: Shape {
    func path(in r: CGRect) -> Path {
        Path(roundedRect: CGRect(x: r.minX + r.width * 0.42, y: r.minY + r.height * 0.58,
                                 width: r.width * 0.16, height: r.height * 0.42), cornerRadius: r.width * 0.08)
    }
}

/// A garden fork: four tines, a shaft and a D-shaped handle. Drawn upright with the tines at the bottom.
struct GardenForkIcon: View {
    var color: Color = .primary
    var body: some View {
        ZStack {
            ForkHead().fill(color)
            ForkHandle().stroke(color.opacity(0.75), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

private struct ForkHead: Shape {
    func path(in r: CGRect) -> Path {
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y) }
        var path = Path()
        // The bar across the top of the tines, then four tines ending in points.
        path.addRect(CGRect(x: r.minX + r.width * 0.22, y: r.minY + r.height * 0.52,
                            width: r.width * 0.56, height: r.height * 0.09))
        for x in [0.22, 0.38, 0.54, 0.70] {
            path.move(to: p(x, 0.58))
            path.addLine(to: p(x + 0.08, 0.58))
            path.addLine(to: p(x + 0.04, 1.00))
            path.closeSubpath()
        }
        return path
    }
}

private struct ForkHandle: Shape {
    func path(in r: CGRect) -> Path {
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y) }
        var path = Path()
        path.move(to: p(0.50, 0.52))
        path.addLine(to: p(0.50, 0.20))
        // The D: a loop across the top of the shaft.
        path.move(to: p(0.34, 0.20))
        path.addLine(to: p(0.66, 0.20))
        path.move(to: p(0.34, 0.20))
        path.addQuadCurve(to: p(0.34, 0.04), control: p(0.26, 0.12))
        path.addLine(to: p(0.66, 0.04))
        path.addQuadCurve(to: p(0.66, 0.20), control: p(0.74, 0.12))
        return path
    }
}
