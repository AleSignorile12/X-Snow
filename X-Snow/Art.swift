import SpriteKit

/// Every picture in the app is drawn here in code, so there are no image files to ship.
/// Sizes are in points; drawings use a y-up coordinate system with the origin at the bottom-left.
enum Art {
    /// Pixels per point for the fixed artwork. 3 keeps it sharp when a tree tilts or squashes.
    static let scale: CGFloat = 3

    static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    static func texture(width: CGFloat, height: CGFloat, scale: CGFloat = Art.scale, _ draw: (CGContext) -> Void) -> SKTexture {
        let ctx = CGContext(
            data: nil, width: Int((width * scale).rounded(.up)), height: Int((height * scale).rounded(.up)),
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: scale, y: scale)
        draw(ctx)
        let texture = SKTexture(cgImage: ctx.makeImage()!)
        texture.filteringMode = .linear
        return texture
    }

    private static func gradient(_ colors: [CGColor], _ locations: [CGFloat]? = nil) -> CGGradient {
        CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
    }

    /// Shadow sizes are in pixels, not points, so they are multiplied by the drawing scale here.
    private static func shadow(_ c: CGContext, dy: CGFloat, blur: CGFloat, _ color: CGColor) {
        c.setShadow(offset: CGSize(width: 0, height: dy * scale), blur: blur * scale, color: color)
    }

    private static func radial(_ c: CGContext, size: CGFloat, _ stops: [(CGFloat, CGFloat)]) {
        let mid = CGPoint(x: size / 2, y: size / 2)
        let g = gradient(stops.map { rgb(1, 1, 1, $0.1) }, stops.map { $0.0 })
        c.drawRadialGradient(g, startCenter: mid, startRadius: 0, endCenter: mid, endRadius: size / 2, options: [])
    }

    // MARK: Snow

    /// A crisp flake: solid in the middle, soft at the rim.
    static let flake = texture(width: 16, height: 16) { radial($0, size: 16, [(0, 1), (0.5, 0.9), (1, 0)]) }
    /// A big out-of-focus flake close to the "camera".
    static let blurFlake = texture(width: 24, height: 24) { radial($0, size: 24, [(0, 0.55), (0.6, 0.3), (1, 0)]) }
    /// A glowing bulb. White, so a sprite can tint it any colour.
    static let glow = texture(width: 24, height: 24) { radial($0, size: 24, [(0, 1), (0.16, 0.95), (0.4, 0.3), (1, 0)]) }

    // MARK: Christmas tree

    static let treeSize = CGSize(width: 110, height: 154)
    /// The middle of the pot's foot: the point that stands on a window.
    static let treeBase = CGPoint(x: 55, y: 4)

    private static let treeCX: CGFloat = 55
    /// Branch layers from the bottom up: bottom y, top y, half-width.
    private static let tiers: [(yb: CGFloat, yt: CGFloat, w: CGFloat)] = [
        (36, 80, 46), (54, 96, 39), (72, 110, 31), (90, 123, 23), (106, 135, 15),
    ]

    /// The string of lights across one layer, as a quadratic curve (start, control, end).
    private static func garland(_ k: Int) -> (CGPoint, CGPoint, CGPoint) {
        let t = tiers[k], h = t.yt - t.yb
        let side: CGFloat = k % 2 == 0 ? 1 : -1
        return (
            CGPoint(x: treeCX - side * t.w * 0.52, y: t.yb + h * 0.30),
            CGPoint(x: treeCX, y: t.yb + h * 0.02),
            CGPoint(x: treeCX + side * t.w * 0.70, y: t.yb + h * 0.14)
        )
    }

    /// Where the bulbs sit, in the tree picture's coordinates.
    static let lightPoints: [CGPoint] = {
        var points: [CGPoint] = []
        for k in 0..<4 {
            let (a, ctrl, b) = garland(k)
            for t: CGFloat in [0.12, 0.37, 0.63, 0.88] {
                let u = 1 - t
                points.append(
                    CGPoint(x: u * u * a.x + 2 * u * t * ctrl.x + t * t * b.x, y: u * u * a.y + 2 * u * t * ctrl.y + t * t * b.y))
            }
        }
        let top = tiers[4]
        points.append(CGPoint(x: treeCX - 5, y: top.yb + 8))
        points.append(CGPoint(x: treeCX + 4, y: top.yb + 15))
        return points
    }()

    /// Drawn afresh each time it is asked for, with a few things left to chance.
    static var tree: SKTexture { texture(width: treeSize.width, height: treeSize.height) { c in
        let cx = treeCX
        // Needle colour: classic green, blue spruce, spring green or dark pine.
        let leaf: (CGFloat, CGFloat, CGFloat) = [(0.26, 0.68, 0.40), (0.18, 0.60, 0.54), (0.38, 0.66, 0.28), (0.16, 0.52, 0.34)].randomElement()!
        func shade(_ k: CGFloat) -> CGColor { rgb(leaf.0 * k, leaf.1 * k, leaf.2 * k) }
        drawPot(c, cx: cx)
        c.setFillColor(rgb(0.33, 0.20, 0.10))
        c.fill(CGRect(x: cx - 4, y: 30, width: 8, height: 14))

        let silhouette = CGMutablePath()
        for t in tiers {
            let (shape, hem) = tierPaths(cx: cx, yb: t.yb, yt: t.yt, w: t.w)
            silhouette.addPath(shape)
            // Each layer casts a shadow on the one below it.
            c.saveGState()
            shadow(c, dy: -2, blur: 4, rgb(0, 0.06, 0.03, 0.6))
            c.setFillColor(shade(0.5))
            c.addPath(shape)
            c.fillPath()
            c.restoreGState()

            c.saveGState()
            c.addPath(shape)
            c.clip()
            c.drawLinearGradient(
                gradient([shade(1), shade(0.7), shade(0.42)], [0, 0.55, 1]),
                start: CGPoint(x: cx, y: t.yt), end: CGPoint(x: cx, y: t.yb - 4), options: [])
            // Lit from the left.
            c.drawLinearGradient(
                gradient([rgb(1, 1, 1, 0.12), rgb(0, 0, 0, 0), rgb(0, 0.04, 0.05, 0.30)], [0, 0.45, 1]),
                start: CGPoint(x: cx - t.w, y: 0), end: CGPoint(x: cx + t.w, y: 0), options: [])
            // Frost along the branch tips.
            c.setStrokeColor(rgb(0.95, 0.98, 1, 0.92))
            c.setLineWidth(5.5)
            c.setLineJoin(.round)
            c.addPath(hem)
            c.strokePath()
            c.restoreGState()
        }

        // Light strings and baubles, kept inside the tree's outline.
        c.saveGState()
        c.addPath(silhouette)
        c.clip()
        c.setStrokeColor(rgb(1, 0.84, 0.42, 0.85))
        c.setLineWidth(1.1)
        for k in 0..<4 {
            let (a, ctrl, b) = garland(k)
            c.move(to: a)
            c.addQuadCurve(to: b, control: ctrl)
        }
        c.strokePath()
        c.restoreGState()

        let baubles: [(tier: Int, dx: CGFloat, dy: CGFloat)] = [
            (0, -0.74, 4), (0, 0.16, 15), (0, 0.50, 3), (1, -0.30, 14), (1, 0.62, 6),
            (2, -0.62, 5), (2, 0.20, 14), (3, -0.25, 12), (3, 0.55, 5), (4, 0.05, 4),
        ]
        let colors: [(CGFloat, CGFloat, CGFloat)] = [
            (0.90, 0.16, 0.20), (0.98, 0.76, 0.22), (0.24, 0.52, 0.98), (0.86, 0.89, 0.93), (0.95, 0.40, 0.75), (0.60, 0.35, 0.90),
        ].shuffled().dropLast(Int.random(in: 0...3)).map { $0 }
        for (i, b) in baubles.enumerated() {
            let t = tiers[b.tier], col = colors[i % colors.count]
            let p = CGPoint(x: cx + b.dx * t.w, y: t.yb + b.dy)
            let r: CGFloat = 3.3
            c.saveGState()
            shadow(c, dy: -0.6, blur: 1.2, rgb(0, 0, 0, 0.45))
            c.setFillColor(rgb(col.0, col.1, col.2))
            c.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            c.restoreGState()
            c.saveGState()
            c.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            c.clip()
            c.drawRadialGradient(
                gradient([rgb(1, 1, 1, 0.85), rgb(1, 1, 1, 0), rgb(0, 0, 0, 0.35)], [0, 0.45, 1]),
                startCenter: CGPoint(x: p.x - 1.1, y: p.y + 1.2), startRadius: 0,
                endCenter: p, endRadius: r * 1.15, options: [.drawsAfterEndLocation])
            c.restoreGState()
        }

        // Star.
        let star = starPath(center: CGPoint(x: cx, y: 142), outer: 9.5, inner: 4.1)
        c.saveGState()
        shadow(c, dy: 0, blur: 5, rgb(1, 0.82, 0.25, 0.95))
        c.setFillColor(rgb(1, 0.82, 0.25))
        c.addPath(star)
        c.fillPath()
        c.restoreGState()
        c.saveGState()
        c.addPath(star)
        c.clip()
        c.drawLinearGradient(
            gradient([rgb(1, 0.97, 0.68), rgb(0.99, 0.74, 0.16)]),
            start: CGPoint(x: cx - 6, y: 151), end: CGPoint(x: cx + 6, y: 133), options: [])
        c.restoreGState()
    } }

    /// One layer of branches: its outline, and just the scalloped lower edge (used for the frost).
    private static func tierPaths(cx: CGFloat, yb: CGFloat, yt: CGFloat, w: CGFloat) -> (shape: CGPath, hem: CGPath) {
        let h = yt - yb
        let lobes = max(3, Int((w / 8.5).rounded()))
        let left = CGPoint(x: cx - w, y: yb + 2), right = CGPoint(x: cx + w, y: yb + 2)
        let shape = CGMutablePath(), hem = CGMutablePath()
        shape.move(to: CGPoint(x: cx, y: yt))
        shape.addCurve(
            to: left, control1: CGPoint(x: cx - w * 0.22, y: yt - h * 0.50), control2: CGPoint(x: cx - w * 0.62, y: yb + h * 0.22))
        hem.move(to: left)
        var prev = left
        for j in 1...lobes {
            let f = CGFloat(j) / CGFloat(lobes)
            // Tips hang lower toward the middle, like a skirt.
            let tip = j == lobes ? right : CGPoint(x: cx - w + 2 * w * f, y: yb + 2 - 5 * sin(f * .pi))
            let ctrl = CGPoint(x: (prev.x + tip.x) / 2, y: max(prev.y, tip.y) + 7)
            shape.addQuadCurve(to: tip, control: ctrl)
            hem.addQuadCurve(to: tip, control: ctrl)
            prev = tip
        }
        shape.addCurve(
            to: CGPoint(x: cx, y: yt), control1: CGPoint(x: cx + w * 0.62, y: yb + h * 0.22),
            control2: CGPoint(x: cx + w * 0.22, y: yt - h * 0.50))
        shape.closeSubpath()
        return (shape, hem)
    }

    private static func drawPot(_ c: CGContext, cx: CGFloat) {
        // Gold, red or silver pot.
        let metals = [
            [rgb(0.60, 0.38, 0.09), rgb(1.0, 0.89, 0.52), rgb(0.90, 0.67, 0.24), rgb(0.52, 0.32, 0.07)],
            [rgb(0.50, 0.06, 0.08), rgb(0.98, 0.42, 0.38), rgb(0.82, 0.14, 0.16), rgb(0.42, 0.04, 0.06)],
            [rgb(0.45, 0.48, 0.54), rgb(0.97, 0.98, 1.0), rgb(0.78, 0.81, 0.86), rgb(0.38, 0.41, 0.47)],
        ]
        let gold = gradient(metals.randomElement()!, [0, 0.32, 0.62, 1])
        let bowl = CGMutablePath()
        bowl.move(to: CGPoint(x: cx - 16, y: 31))
        bowl.addCurve(to: CGPoint(x: cx - 5, y: 10), control1: CGPoint(x: cx - 16, y: 18), control2: CGPoint(x: cx - 9, y: 13))
        bowl.addLine(to: CGPoint(x: cx - 9, y: 6.5))
        bowl.addLine(to: CGPoint(x: cx - 11, y: 4))
        bowl.addLine(to: CGPoint(x: cx + 11, y: 4))
        bowl.addLine(to: CGPoint(x: cx + 9, y: 6.5))
        bowl.addLine(to: CGPoint(x: cx + 5, y: 10))
        bowl.addCurve(to: CGPoint(x: cx + 16, y: 31), control1: CGPoint(x: cx + 9, y: 13), control2: CGPoint(x: cx + 16, y: 18))
        bowl.closeSubpath()
        let rim = CGPath(roundedRect: CGRect(x: cx - 18.5, y: 29, width: 37, height: 4.6), cornerWidth: 2.3, cornerHeight: 2.3, transform: nil)
        for (path, half) in [(bowl as CGPath, CGFloat(16)), (rim, 18.5)] {
            c.saveGState()
            shadow(c, dy: -0.8, blur: 1.6, rgb(0, 0, 0, 0.4))
            c.setFillColor(rgb(0.80, 0.58, 0.18))
            c.addPath(path)
            c.fillPath()
            c.restoreGState()
            c.saveGState()
            c.addPath(path)
            c.clip()
            c.drawLinearGradient(gold, start: CGPoint(x: cx - half, y: 0), end: CGPoint(x: cx + half, y: 0), options: [])
            c.restoreGState()
        }
    }

    private static func starPath(center: CGPoint, outer: CGFloat, inner: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for i in 0..<10 {
            let r = i % 2 == 0 ? outer : inner
            let angle = CGFloat.pi / 2 + CGFloat(i) * .pi / 5
            let p = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    // MARK: Cable car

    static let carSize = CGSize(width: 60, height: 54)
    /// Where the car grips the rope.
    static let carGrip = CGPoint(x: 30, y: 50)
    /// The headlamp on the car's front (its right side).
    static let carLamp = CGPoint(x: 52, y: 10)

    static let car = texture(width: carSize.width, height: carSize.height) { c in
        let dark = rgb(0.13, 0.14, 0.17)
        // Hanger arm, grip and wheels.
        c.setStrokeColor(dark)
        c.setLineWidth(2.4)
        c.setLineCap(.round)
        c.move(to: CGPoint(x: 30, y: 32))
        c.addLine(to: CGPoint(x: 30, y: 47))
        c.strokePath()
        c.setFillColor(dark)
        c.addPath(CGPath(roundedRect: CGRect(x: 22, y: 45.4, width: 16, height: 3.6), cornerWidth: 1.8, cornerHeight: 1.8, transform: nil))
        c.fillPath()
        for x: CGFloat in [24.5, 35.5] {
            c.setFillColor(rgb(0.78, 0.80, 0.85))
            c.fillEllipse(in: CGRect(x: x - 2.3, y: 47.6, width: 4.6, height: 4.6))
            c.setFillColor(dark)
            c.fillEllipse(in: CGRect(x: x - 0.9, y: 49, width: 1.8, height: 1.8))
        }

        // Cabin.
        let body = CGPath(roundedRect: CGRect(x: 8, y: 5, width: 44, height: 26), cornerWidth: 7, cornerHeight: 7, transform: nil)
        c.saveGState()
        shadow(c, dy: -1, blur: 2.5, rgb(0, 0, 0, 0.45))
        c.setFillColor(rgb(0.80, 0.12, 0.13))
        c.addPath(body)
        c.fillPath()
        c.restoreGState()
        c.saveGState()
        c.addPath(body)
        c.clip()
        c.drawLinearGradient(
            gradient([rgb(0.95, 0.22, 0.20), rgb(0.74, 0.09, 0.11)]), start: CGPoint(x: 0, y: 31), end: CGPoint(x: 0, y: 5), options: [])
        c.setFillColor(rgb(0.52, 0.05, 0.08))
        c.fill(CGRect(x: 8, y: 5, width: 44, height: 6.5))
        c.setFillColor(rgb(1, 0.93, 0.80))
        c.fill(CGRect(x: 8, y: 11.5, width: 44, height: 1.5))
        c.restoreGState()

        // Lit windows.
        for x: CGFloat in [11.5, 24.75, 38] {
            let pane = CGPath(roundedRect: CGRect(x: x, y: 15.5, width: 10.5, height: 10.5), cornerWidth: 2.2, cornerHeight: 2.2, transform: nil)
            c.saveGState()
            shadow(c, dy: 0, blur: 2.2, rgb(1, 0.85, 0.4, 0.9))
            c.setFillColor(rgb(1, 0.90, 0.55))
            c.addPath(pane)
            c.fillPath()
            c.restoreGState()
            c.saveGState()
            c.addPath(pane)
            c.clip()
            c.drawLinearGradient(
                gradient([rgb(1, 0.97, 0.74), rgb(1, 0.78, 0.36)]), start: CGPoint(x: 0, y: 26), end: CGPoint(x: 0, y: 15.5), options: [])
            c.restoreGState()
        }

        // Roof with a cap of snow.
        c.setFillColor(rgb(0.46, 0.05, 0.07))
        c.addPath(CGPath(roundedRect: CGRect(x: 6, y: 29, width: 48, height: 4.6), cornerWidth: 2.3, cornerHeight: 2.3, transform: nil))
        c.fillPath()
        c.saveGState()
        c.clip(to: CGRect(x: 0, y: 32.6, width: 60, height: 10))
        c.setFillColor(rgb(0.97, 0.98, 1))
        c.fillEllipse(in: CGRect(x: 8, y: 29.6, width: 44, height: 7.4))
        c.restoreGState()

        // Headlamp.
        c.saveGState()
        shadow(c, dy: 0, blur: 2.5, rgb(1, 0.92, 0.6, 1))
        c.setFillColor(rgb(1, 0.97, 0.78))
        c.fillEllipse(in: CGRect(x: carLamp.x - 2.2, y: carLamp.y - 2.2, width: 4.4, height: 4.4))
        c.restoreGState()
    }

    /// The headlamp's cone of light, shining to the right from its left edge.
    static let beamSize = CGSize(width: 64, height: 34)
    static let beam = texture(width: beamSize.width, height: beamSize.height) { c in
        let cone = CGMutablePath()
        cone.move(to: CGPoint(x: 0, y: 18.5))
        cone.addLine(to: CGPoint(x: 64, y: 33))
        cone.addLine(to: CGPoint(x: 64, y: 1))
        cone.addLine(to: CGPoint(x: 0, y: 15.5))
        cone.closeSubpath()
        c.addPath(cone)
        c.clip()
        c.drawLinearGradient(
            gradient([rgb(1, 0.95, 0.72, 0.62), rgb(1, 0.95, 0.72, 0.22), rgb(1, 0.95, 0.72, 0)], [0, 0.45, 1]),
            start: CGPoint(x: 0, y: 17), end: CGPoint(x: 64, y: 17), options: [])
    }

    // MARK: Snowman, stocking, cookie

    private static func disc(_ c: CGContext, _ center: CGPoint, _ r: CGFloat, _ color: CGColor) {
        c.setFillColor(color)
        c.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
    }

    static let snowmanSize = CGSize(width: 64, height: 86)
    /// Drawn afresh each time it is asked for, with a few things left to chance.
    static var snowman: SKTexture { texture(width: snowmanSize.width, height: snowmanSize.height) { c in
        let cx: CGFloat = 32
        let scarf = [rgb(0.86, 0.14, 0.18), rgb(0.13, 0.58, 0.32), rgb(0.22, 0.45, 0.90), rgb(0.96, 0.72, 0.16), rgb(0.60, 0.30, 0.80)].randomElement()!
        c.setLineCap(.round)
        // Twig arms, behind the body.
        c.setStrokeColor(rgb(0.36, 0.22, 0.11))
        c.setLineWidth(1.8)
        for side: CGFloat in [-1, 1] {
            c.move(to: CGPoint(x: cx + side * 10, y: 46))
            c.addLine(to: CGPoint(x: cx + side * 25, y: 56))
            c.move(to: CGPoint(x: cx + side * 20, y: 52.5))
            c.addLine(to: CGPoint(x: cx + side * 23, y: 49))
            c.move(to: CGPoint(x: cx + side * 21, y: 53.3))
            c.addLine(to: CGPoint(x: cx + side * 21.5, y: 58))
        }
        c.strokePath()
        // Three snowballs, lit from the upper left.
        for (center, r) in [(CGPoint(x: cx, y: 20), CGFloat(17)), (CGPoint(x: cx, y: 44), 12.5), (CGPoint(x: cx, y: 62), 9.5)] {
            c.saveGState()
            shadow(c, dy: -0.8, blur: 2, rgb(0.05, 0.12, 0.30, 0.5))
            disc(c, center, r, rgb(0.93, 0.96, 1))
            c.restoreGState()
            c.saveGState()
            c.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            c.clip()
            c.drawRadialGradient(
                gradient([rgb(1, 1, 1), rgb(0.95, 0.97, 1), rgb(0.74, 0.82, 0.94)], [0, 0.6, 1]),
                startCenter: CGPoint(x: center.x - r * 0.35, y: center.y + r * 0.4), startRadius: 0,
                endCenter: center, endRadius: r * 1.15, options: [.drawsAfterEndLocation])
            c.restoreGState()
        }
        // Scarf.
        c.setFillColor(scarf)
        c.addPath(CGPath(roundedRect: CGRect(x: cx - 10.5, y: 52, width: 21, height: 5), cornerWidth: 2.5, cornerHeight: 2.5, transform: nil))
        c.addPath(CGPath(roundedRect: CGRect(x: cx + 4, y: 42, width: 4.6, height: 13), cornerWidth: 1.5, cornerHeight: 1.5, transform: nil))
        c.fillPath()
        // Coal buttons and eyes, carrot nose, smile.
        let coal = rgb(0.12, 0.12, 0.15)
        for y: CGFloat in [[47, 41, 26], [47, 41], [47, 41, 28, 20]].randomElement()! { disc(c, CGPoint(x: cx, y: y), 1.5, coal) }
        disc(c, CGPoint(x: cx - 3.3, y: 64.5), 1.2, coal)
        disc(c, CGPoint(x: cx + 3.3, y: 64.5), 1.2, coal)
        c.setStrokeColor(coal)
        c.setLineWidth(0.9)
        c.addArc(center: CGPoint(x: cx, y: 61), radius: 3.6, startAngle: .pi * 1.2, endAngle: .pi * 1.8, clockwise: false)
        c.strokePath()
        c.setFillColor(rgb(0.98, 0.52, 0.10))
        c.move(to: CGPoint(x: cx - 0.5, y: 63))
        c.addLine(to: CGPoint(x: cx + 9, y: 61.2))
        c.addLine(to: CGPoint(x: cx - 0.5, y: 60.2))
        c.fillPath()
        // Top hat with a red band.
        c.setFillColor(rgb(0.10, 0.10, 0.13))
        c.addPath(CGPath(roundedRect: CGRect(x: cx - 11, y: 69, width: 22, height: 2.8), cornerWidth: 1.4, cornerHeight: 1.4, transform: nil))
        c.addPath(CGPath(roundedRect: CGRect(x: cx - 6.5, y: 70, width: 13, height: 13), cornerWidth: 1.5, cornerHeight: 1.5, transform: nil))
        c.fillPath()
        c.setFillColor(scarf)
        c.fill(CGRect(x: cx - 6.5, y: 72, width: 13, height: 2.6))
    } }

    static let stockingSize = CGSize(width: 50, height: 60)
    /// Drawn afresh each time it is asked for, with a few things left to chance.
    static var stocking: SKTexture { texture(width: stockingSize.width, height: stockingSize.height) { c in
        // Wool (light, dark) and the colour of the toe and heel.
        let looks: [(CGColor, CGColor, CGColor)] = [
            (rgb(0.95, 0.24, 0.22), rgb(0.72, 0.08, 0.12), rgb(0.13, 0.58, 0.32)),
            (rgb(0.22, 0.68, 0.40), rgb(0.08, 0.42, 0.22), rgb(0.86, 0.14, 0.18)),
            (rgb(0.34, 0.58, 0.96), rgb(0.15, 0.32, 0.75), rgb(0.97, 0.98, 1)),
        ]
        let look = looks.randomElement()!
        let sock = CGMutablePath()
        sock.move(to: CGPoint(x: 15, y: 50))
        sock.addLine(to: CGPoint(x: 15, y: 14))
        sock.addQuadCurve(to: CGPoint(x: 25, y: 4), control: CGPoint(x: 15, y: 4))
        sock.addLine(to: CGPoint(x: 38, y: 4))
        sock.addQuadCurve(to: CGPoint(x: 46, y: 12), control: CGPoint(x: 46, y: 4))
        sock.addQuadCurve(to: CGPoint(x: 38, y: 20), control: CGPoint(x: 46, y: 20))
        sock.addQuadCurve(to: CGPoint(x: 33, y: 25), control: CGPoint(x: 33, y: 20))
        sock.addLine(to: CGPoint(x: 33, y: 50))
        sock.closeSubpath()
        c.saveGState()
        shadow(c, dy: -0.8, blur: 2, rgb(0, 0, 0, 0.45))
        c.setFillColor(look.1)
        c.addPath(sock)
        c.fillPath()
        c.restoreGState()
        c.saveGState()
        c.addPath(sock)
        c.clip()
        c.drawLinearGradient(
            gradient([look.0, look.1]), start: CGPoint(x: 15, y: 0), end: CGPoint(x: 46, y: 0), options: [])
        // Green toe and heel, white stripes.
        disc(c, CGPoint(x: 45, y: 10), 9, look.2)
        disc(c, CGPoint(x: 15, y: 6), 8.5, look.2)
        c.setFillColor(rgb(1, 1, 1, 0.9))
        c.fill(CGRect(x: 10, y: 35, width: 30, height: 2.4))
        c.fill(CGRect(x: 10, y: 29, width: 30, height: 2.4))
        c.restoreGState()
        // Fluffy cuff.
        c.saveGState()
        shadow(c, dy: -0.6, blur: 1.5, rgb(0.05, 0.12, 0.30, 0.45))
        c.setFillColor(rgb(0.97, 0.98, 1))
        c.addPath(CGPath(roundedRect: CGRect(x: 11.5, y: 44, width: 25, height: 11), cornerWidth: 5, cornerHeight: 5, transform: nil))
        c.fillPath()
        c.restoreGState()
    } }

    static let cookieSize = CGSize(width: 50, height: 58)
    /// Drawn afresh each time it is asked for, with a few things left to chance.
    static var cookie: SKTexture { texture(width: cookieSize.width, height: cookieSize.height) { c in
        let cx: CGFloat = 25
        let dough = [rgb(0.74, 0.46, 0.21), rgb(0.62, 0.36, 0.15), rgb(0.82, 0.56, 0.28)].randomElement()!
        let sweets = [rgb(0.90, 0.18, 0.20), rgb(0.20, 0.70, 0.38), rgb(0.30, 0.55, 0.95), rgb(1, 0.82, 0.25), rgb(0.96, 0.45, 0.75)].shuffled()
        c.setLineCap(.round)
        c.setLineJoin(.round)
        if Int.random(in: 0..<3) == 0 {
            // One in three is a star biscuit instead of a gingerbread man.
            let mid = CGPoint(x: cx, y: 25)
            c.saveGState()
            shadow(c, dy: -0.8, blur: 2, rgb(0, 0, 0, 0.5))
            c.setFillColor(dough)
            c.setStrokeColor(dough)
            c.setLineWidth(5)
            c.addPath(starPath(center: mid, outer: 21, inner: 10.5))
            c.drawPath(using: .fillStroke)
            c.restoreGState()
            c.setStrokeColor(rgb(1, 1, 1))
            c.setLineWidth(1.5)
            c.addPath(starPath(center: mid, outer: 17, inner: 8.5))
            c.strokePath()
            for i in 0..<5 {
                let angle = CGFloat.pi / 2 + CGFloat(i) * 2 * .pi / 5
                disc(c, CGPoint(x: mid.x + cos(angle) * 10, y: mid.y + sin(angle) * 10), 1.7, sweets[i % sweets.count])
            }
            disc(c, mid, 2.3, sweets[0])
            return
        }
        // Gingerbread man: thick round-ended strokes for the limbs, drawn as one shape so the shadow is shared.
        c.saveGState()
        shadow(c, dy: -0.8, blur: 2, rgb(0, 0, 0, 0.5))
        c.beginTransparencyLayer(auxiliaryInfo: nil)
        c.setStrokeColor(dough)
        c.setLineWidth(9.5)
        for side: CGFloat in [-1, 1] {
            c.move(to: CGPoint(x: cx + side * 5, y: 31))
            c.addLine(to: CGPoint(x: cx + side * 17, y: 27))
            c.move(to: CGPoint(x: cx + side * 4.5, y: 18))
            c.addLine(to: CGPoint(x: cx + side * 8.5, y: 7))
        }
        c.strokePath()
        c.setFillColor(dough)
        c.addPath(CGPath(roundedRect: CGRect(x: cx - 9, y: 13, width: 18, height: 24), cornerWidth: 7, cornerHeight: 7, transform: nil))
        c.fillPath()
        disc(c, CGPoint(x: cx, y: 45), 10, dough)
        c.endTransparencyLayer()
        c.restoreGState()
        // Icing: cuffs, smile, eyes and buttons.
        c.setStrokeColor(rgb(1, 1, 1))
        c.setLineWidth(1.5)
        for side: CGFloat in [-1, 1] {
            c.move(to: CGPoint(x: cx + side * 14.5, y: 31.5))
            c.addLine(to: CGPoint(x: cx + side * 17, y: 23.5))
            c.move(to: CGPoint(x: cx + side * 3.5, y: 9.5))
            c.addLine(to: CGPoint(x: cx + side * 11.5, y: 11.5))
        }
        c.strokePath()
        c.addArc(center: CGPoint(x: cx, y: 45.5), radius: 4.6, startAngle: .pi * 1.15, endAngle: .pi * 1.85, clockwise: false)
        c.strokePath()
        disc(c, CGPoint(x: cx - 3.6, y: 47.5), 1.3, rgb(0.20, 0.10, 0.05))
        disc(c, CGPoint(x: cx + 3.6, y: 47.5), 1.3, rgb(0.20, 0.10, 0.05))
        disc(c, CGPoint(x: cx, y: 30), 1.9, sweets[0])
        disc(c, CGPoint(x: cx, y: 23.5), 1.9, sweets[1])
        disc(c, CGPoint(x: cx, y: 17), 1.9, sweets[2])
    } }

    static let giftSize = CGSize(width: 50, height: 50)
    /// A wrapped present. Its shape, paper, pattern and ribbon are picked at random.
    static var gift: SKTexture { texture(width: giftSize.width, height: giftSize.height) { c in
        let cx: CGFloat = 25
        let w = CGFloat.random(in: 26...40), h = CGFloat.random(in: 17...29)
        let papers: [(CGFloat, CGFloat, CGFloat)] = [
            (0.86, 0.14, 0.18), (0.13, 0.55, 0.32), (0.20, 0.42, 0.86), (0.95, 0.72, 0.18), (0.58, 0.28, 0.75), (0.92, 0.94, 0.98),
        ]
        let paper = papers.randomElement()!
        let ribbons: [(CGFloat, CGFloat, CGFloat)] = [(1, 0.84, 0.30), (0.97, 0.98, 1), (0.86, 0.14, 0.18), (0.13, 0.55, 0.32)]
        let ribbon = ribbons.filter { abs($0.0 - paper.0) + abs($0.1 - paper.1) > 0.3 }.randomElement()!
        let ribbonColor = rgb(ribbon.0, ribbon.1, ribbon.2)
        let box = CGRect(x: cx - w / 2, y: 2, width: w, height: h)
        let lid = CGRect(x: cx - w / 2 - 2, y: h, width: w + 4, height: 6.5)
        let shape = CGMutablePath()
        shape.addPath(CGPath(roundedRect: box, cornerWidth: 2, cornerHeight: 2, transform: nil))
        shape.addPath(CGPath(roundedRect: lid, cornerWidth: 2, cornerHeight: 2, transform: nil))
        c.saveGState()
        shadow(c, dy: -0.8, blur: 2, rgb(0, 0, 0, 0.5))
        c.setFillColor(rgb(paper.0, paper.1, paper.2))
        c.addPath(shape)
        c.fillPath()
        c.restoreGState()
        c.saveGState()
        c.addPath(shape)
        c.clip()
        // Wrapping paper: dots, stripes or plain.
        c.setFillColor(rgb(1, 1, 1, 0.32))
        switch Int.random(in: 0..<3) {
        case 0:
            for row in 0..<5 {
                for col in 0..<8 {
                    disc(c, CGPoint(x: box.minX + 3 + CGFloat(col) * 6 + (row % 2 == 0 ? 0 : 3), y: 5 + CGFloat(row) * 6), 1.3, rgb(1, 1, 1, 0.38))
                }
            }
        case 1:
            for col in 0..<10 { c.fill(CGRect(x: box.minX + 2 + CGFloat(col) * 6, y: 2, width: 2.4, height: h - 2)) }
        default: break
        }
        // Darker toward the right, and a shadow under the lid.
        c.drawLinearGradient(
            gradient([rgb(1, 1, 1, 0.14), rgb(0, 0, 0, 0), rgb(0, 0, 0, 0.26)], [0, 0.4, 1]),
            start: CGPoint(x: lid.minX, y: 0), end: CGPoint(x: lid.maxX, y: 0), options: [])
        c.setFillColor(rgb(0, 0, 0, 0.18))
        c.fill(CGRect(x: box.minX, y: h - 2, width: w, height: 2))
        c.setFillColor(ribbonColor)
        c.fill(CGRect(x: cx - 2.8, y: 2, width: 5.6, height: h + 5))
        c.restoreGState()
        // Bow.
        c.setStrokeColor(ribbonColor)
        c.setLineWidth(2.6)
        c.strokeEllipse(in: CGRect(x: cx - 11.5, y: lid.maxY - 1, width: 11, height: 8))
        c.strokeEllipse(in: CGRect(x: cx + 0.5, y: lid.maxY - 1, width: 11, height: 8))
        disc(c, CGPoint(x: cx, y: lid.maxY + 1.5), 2.8, ribbonColor)
    } }

    // MARK: Snow plow

    static let plowSize = CGSize(width: 40, height: 24)
    /// A small truck facing right, wheels on the bottom edge, blade at the front.
    static let plow = texture(width: plowSize.width, height: plowSize.height) { c in
        let dark = rgb(0.13, 0.14, 0.17)
        // Flatbed and cab.
        let bodyShape = CGMutablePath()
        bodyShape.addPath(CGPath(roundedRect: CGRect(x: 3, y: 5, width: 27, height: 8), cornerWidth: 2, cornerHeight: 2, transform: nil))
        bodyShape.addPath(CGPath(roundedRect: CGRect(x: 15, y: 5, width: 13, height: 15), cornerWidth: 3, cornerHeight: 3, transform: nil))
        c.saveGState()
        shadow(c, dy: -0.8, blur: 1.6, rgb(0, 0, 0, 0.45))
        c.setFillColor(rgb(0.98, 0.62, 0.10))
        c.addPath(bodyShape)
        c.fillPath()
        c.restoreGState()
        c.setFillColor(rgb(0.80, 0.42, 0.05))
        c.fill(CGRect(x: 4, y: 5, width: 25, height: 2.2))
        // Windscreen, lit from inside.
        c.setFillColor(rgb(1, 0.93, 0.66))
        c.addPath(CGPath(roundedRect: CGRect(x: 19.5, y: 12.5, width: 7, height: 5.5), cornerWidth: 1.5, cornerHeight: 1.5, transform: nil))
        c.fillPath()
        // Flashing-style beacon on the roof.
        c.saveGState()
        shadow(c, dy: 0, blur: 2.5, rgb(1, 0.75, 0.2, 1))
        c.setFillColor(rgb(1, 0.80, 0.25))
        c.fillEllipse(in: CGRect(x: 19.5, y: 19.4, width: 4, height: 3.4))
        c.restoreGState()
        // Blade: a curved steel scoop out front.
        c.setStrokeColor(dark)
        c.setLineWidth(1.6)
        c.move(to: CGPoint(x: 29, y: 8))
        c.addLine(to: CGPoint(x: 34, y: 7))
        c.strokePath()
        c.setStrokeColor(rgb(0.82, 0.85, 0.90))
        c.setLineWidth(2.6)
        c.setLineCap(.round)
        c.move(to: CGPoint(x: 35, y: 15))
        c.addQuadCurve(to: CGPoint(x: 38, y: 1.5), control: CGPoint(x: 31.5, y: 5))
        c.strokePath()
        // Wheels.
        for x: CGFloat in [9, 23] {
            c.setFillColor(dark)
            c.fillEllipse(in: CGRect(x: x - 4, y: 0.5, width: 8, height: 8))
            c.setFillColor(rgb(0.75, 0.77, 0.82))
            c.fillEllipse(in: CGRect(x: x - 1.6, y: 2.9, width: 3.2, height: 3.2))
        }
    }

    // MARK: Rope hardware

    static let hookSize = CGSize(width: 16, height: 24)
    /// The eye at the top of the hook, where the rope is tied.
    static let hookEye = CGPoint(x: 9, y: 19)

    static let hook = texture(width: hookSize.width, height: hookSize.height) { c in
        let shape = CGMutablePath()
        shape.addEllipse(in: CGRect(x: hookEye.x - 2.6, y: hookEye.y - 2.6, width: 5.2, height: 5.2))
        shape.move(to: CGPoint(x: 9, y: 16.4))
        shape.addLine(to: CGPoint(x: 9, y: 7.5))
        shape.addArc(center: CGPoint(x: 5.6, y: 7.5), radius: 3.4, startAngle: 0, endAngle: .pi, clockwise: true)
        shape.addLine(to: CGPoint(x: 2.2, y: 9.5))
        c.setLineCap(.round)
        c.setLineJoin(.round)
        c.saveGState()
        shadow(c, dy: -0.6, blur: 1.4, rgb(0, 0, 0, 0.55))
        c.setStrokeColor(rgb(0.72, 0.50, 0.10))
        c.setLineWidth(2.8)
        c.addPath(shape)
        c.strokePath()
        c.restoreGState()
        c.setStrokeColor(rgb(1, 0.86, 0.36))
        c.setLineWidth(1.5)
        c.addPath(shape)
        c.strokePath()
    }

    static let bracketSize = CGSize(width: 28, height: 14)
    /// The pulley wheel the rope runs from.
    static let bracketWheel = CGPoint(x: 14, y: 5)

    static let bracket = texture(width: bracketSize.width, height: bracketSize.height) { c in
        c.saveGState()
        shadow(c, dy: -0.6, blur: 1.5, rgb(0, 0, 0, 0.5))
        c.setFillColor(rgb(0.20, 0.21, 0.25))
        c.addPath(CGPath(roundedRect: CGRect(x: 2, y: 8, width: 24, height: 5), cornerWidth: 2, cornerHeight: 2, transform: nil))
        c.fillPath()
        c.fill(CGRect(x: 12.5, y: 5, width: 3, height: 4))
        c.restoreGState()
        c.setFillColor(rgb(1, 0.82, 0.30))
        c.fillEllipse(in: CGRect(x: bracketWheel.x - 3.4, y: bracketWheel.y - 3.4, width: 6.8, height: 6.8))
        c.setFillColor(rgb(0.55, 0.36, 0.08))
        c.fillEllipse(in: CGRect(x: bracketWheel.x - 1.1, y: bracketWheel.y - 1.1, width: 2.2, height: 2.2))
        c.setFillColor(rgb(1, 0.82, 0.30))
        for x: CGFloat in [5.5, 22.5] { c.fillEllipse(in: CGRect(x: x - 1, y: 9.5, width: 2, height: 2)) }
    }

    // MARK: Hanging lights

    static let eyeletSize = CGSize(width: 16, height: 10)
    /// The ring's centre, measured from the edge of the screen the eyelet is screwed into.
    static let eyeletRing = CGPoint(x: 12, y: 5)

    /// A brass screw eye, screwed into the left edge of the screen (flipped for the right).
    static let eyelet = texture(width: eyeletSize.width, height: eyeletSize.height) { c in
        let ring = CGRect(x: eyeletRing.x - 3.2, y: eyeletRing.y - 3.2, width: 6.4, height: 6.4)
        c.setLineCap(.round)
        c.saveGState()
        shadow(c, dy: -0.5, blur: 1.2, rgb(0, 0, 0, 0.5))
        c.setStrokeColor(rgb(0.70, 0.52, 0.16))
        c.setLineWidth(2.2)
        c.move(to: CGPoint(x: 0, y: eyeletRing.y))
        c.addLine(to: CGPoint(x: eyeletRing.x - 3.4, y: eyeletRing.y))
        c.strokePath()
        c.strokeEllipse(in: ring)
        c.restoreGState()
        c.setStrokeColor(rgb(1, 0.86, 0.42))
        c.setLineWidth(0.9)
        c.strokeEllipse(in: ring)
    }

    static let bulbSize = CGSize(width: 7, height: 10)
    /// The glass of a big old-fashioned bulb, hanging point down. White, so a sprite can tint it.
    static let bulbGlass = texture(width: bulbSize.width, height: bulbSize.height) { c in
        let w = bulbSize.width, h = bulbSize.height, mid = w / 2
        let glass = CGMutablePath()
        glass.move(to: CGPoint(x: mid, y: 0.4))
        glass.addCurve(to: CGPoint(x: w - 0.4, y: h * 0.55), control1: CGPoint(x: mid + 1.6, y: 1.6), control2: CGPoint(x: w - 0.4, y: h * 0.32))
        glass.addCurve(to: CGPoint(x: mid, y: h), control1: CGPoint(x: w - 0.4, y: h * 0.82), control2: CGPoint(x: mid + 1.8, y: h))
        glass.addCurve(to: CGPoint(x: 0.4, y: h * 0.55), control1: CGPoint(x: mid - 1.8, y: h), control2: CGPoint(x: 0.4, y: h * 0.82))
        glass.addCurve(to: CGPoint(x: mid, y: 0.4), control1: CGPoint(x: 0.4, y: h * 0.32), control2: CGPoint(x: mid - 1.6, y: 1.6))
        glass.closeSubpath()
        c.addPath(glass)
        c.clip()
        c.drawLinearGradient(gradient([rgb(1, 1, 1), rgb(0.74, 0.74, 0.74)]), start: CGPoint(x: 1, y: h), end: CGPoint(x: w, y: 0), options: [])
        disc(c, CGPoint(x: mid - 1.2, y: h * 0.62), 1.1, rgb(1, 1, 1))
    }

    static let bulbCapSize = CGSize(width: 4.4, height: 3.6)
    /// The green socket a bulb screws into.
    static let bulbCap = texture(width: bulbCapSize.width, height: bulbCapSize.height) { c in
        c.setFillColor(rgb(0.12, 0.30, 0.16))
        c.addPath(CGPath(roundedRect: CGRect(x: 0.2, y: 0.2, width: 4, height: 3.2), cornerWidth: 1, cornerHeight: 1, transform: nil))
        c.fillPath()
        c.setFillColor(rgb(0.32, 0.55, 0.34))
        c.fill(CGRect(x: 0.8, y: 2.2, width: 2.8, height: 0.7))
    }

    // MARK: Santa

    static let sleighSize = CGSize(width: 96, height: 64)
    /// Where Santa holds the reins.
    static let santaHands = CGPoint(x: 65, y: 35)
    /// The back of the sleigh, where its trail of sparkles starts.
    static let sleighBack = CGPoint(x: 8, y: 20)

    /// Santa, his sack of presents and the sleigh, facing right.
    static let sleigh = texture(width: sleighSize.width, height: sleighSize.height) { c in
        let gold = rgb(0.96, 0.78, 0.30)
        let red = rgb(0.84, 0.12, 0.14)
        let fur = rgb(0.98, 0.98, 1)
        c.setLineCap(.round)
        c.setLineJoin(.round)

        // Runner, curling up at the front, and the struts that hold the sleigh on it.
        c.saveGState()
        shadow(c, dy: -0.6, blur: 1.2, rgb(0, 0, 0, 0.45))
        c.setStrokeColor(gold)
        c.setLineWidth(2.2)
        c.move(to: CGPoint(x: 5, y: 6))
        c.addLine(to: CGPoint(x: 72, y: 6))
        c.addQuadCurve(to: CGPoint(x: 86, y: 15), control: CGPoint(x: 88, y: 5))
        c.addQuadCurve(to: CGPoint(x: 80.5, y: 17), control: CGPoint(x: 84, y: 20))
        c.move(to: CGPoint(x: 22, y: 6))
        c.addLine(to: CGPoint(x: 22, y: 13))
        c.move(to: CGPoint(x: 56, y: 6))
        c.addLine(to: CGPoint(x: 56, y: 13))
        c.strokePath()
        c.restoreGState()

        // Presents poking out of the sack in the back.
        let presents: [(CGRect, CGColor)] = [
            (CGRect(x: 9, y: 39, width: 7, height: 8), rgb(0.25, 0.48, 0.92)),
            (CGRect(x: 14, y: 42, width: 9, height: 8), rgb(0.86, 0.16, 0.20)),
            (CGRect(x: 22, y: 40, width: 8, height: 9), rgb(0.16, 0.58, 0.34)),
        ]
        for (box, color) in presents {
            c.setFillColor(color)
            c.fill(box)
            c.setFillColor(gold)
            c.fill(CGRect(x: box.midX - 0.8, y: box.minY, width: 1.6, height: box.height))
        }
        c.saveGState()
        shadow(c, dy: -0.6, blur: 1.4, rgb(0, 0, 0, 0.4))
        c.setFillColor(rgb(0.58, 0.40, 0.24))
        c.fillEllipse(in: CGRect(x: 6, y: 24, width: 26, height: 21))
        c.restoreGState()
        c.setStrokeColor(rgb(0.40, 0.26, 0.14))
        c.setLineWidth(1.2)
        c.move(to: CGPoint(x: 11, y: 42))
        c.addQuadCurve(to: CGPoint(x: 27, y: 42), control: CGPoint(x: 19, y: 38.5))
        c.strokePath()

        // Santa: coat, the arm holding the reins, face, beard and hat.
        c.saveGState()
        shadow(c, dy: -0.6, blur: 1.4, rgb(0, 0, 0, 0.4))
        c.setFillColor(red)
        c.fillEllipse(in: CGRect(x: 37, y: 22, width: 22, height: 26))
        c.restoreGState()
        c.setStrokeColor(rgb(0.72, 0.08, 0.11))
        c.setLineWidth(5)
        c.move(to: CGPoint(x: 51, y: 39.5))
        c.addLine(to: CGPoint(x: 61.5, y: 35.6))
        c.strokePath()
        c.setStrokeColor(fur)
        c.move(to: CGPoint(x: 60.6, y: 35.9))
        c.addLine(to: CGPoint(x: 62.3, y: 35.3))
        c.strokePath()
        disc(c, santaHands, 2.6, rgb(0.16, 0.16, 0.18))
        disc(c, CGPoint(x: 52, y: 50), 6.2, rgb(1, 0.82, 0.70))
        let beard = CGMutablePath()
        beard.move(to: CGPoint(x: 45.5, y: 49))
        beard.addQuadCurve(to: CGPoint(x: 51, y: 36), control: CGPoint(x: 44, y: 39))
        beard.addQuadCurve(to: CGPoint(x: 58.5, y: 48), control: CGPoint(x: 59.5, y: 39))
        beard.addQuadCurve(to: CGPoint(x: 45.5, y: 49), control: CGPoint(x: 52, y: 45))
        c.setFillColor(fur)
        c.addPath(beard)
        c.fillPath()
        disc(c, CGPoint(x: 57.6, y: 49.6), 1.6, rgb(0.95, 0.56, 0.52))
        disc(c, CGPoint(x: 54.6, y: 52), 0.8, rgb(0.15, 0.10, 0.08))
        let hat = CGMutablePath()
        hat.move(to: CGPoint(x: 45, y: 54))
        hat.addLine(to: CGPoint(x: 58.5, y: 54))
        hat.addQuadCurve(to: CGPoint(x: 42, y: 61), control: CGPoint(x: 54, y: 63))
        hat.closeSubpath()
        c.setFillColor(red)
        c.addPath(hat)
        c.fillPath()
        c.setFillColor(fur)
        c.addPath(CGPath(roundedRect: CGRect(x: 44.5, y: 52, width: 15, height: 4), cornerWidth: 2, cornerHeight: 2, transform: nil))
        c.fillPath()
        disc(c, CGPoint(x: 41.8, y: 60.5), 2.6, fur)

        // The sleigh itself: low in the middle, a high back, and a front that curls up into a scroll.
        let body = CGMutablePath()
        body.move(to: CGPoint(x: 6, y: 12))
        body.addLine(to: CGPoint(x: 64, y: 12))
        body.addCurve(to: CGPoint(x: 79, y: 31), control1: CGPoint(x: 75, y: 12), control2: CGPoint(x: 81, y: 22))
        body.addQuadCurve(to: CGPoint(x: 71, y: 30), control: CGPoint(x: 76, y: 36))
        body.addLine(to: CGPoint(x: 64, y: 25))
        body.addLine(to: CGPoint(x: 36, y: 25))
        body.addLine(to: CGPoint(x: 31, y: 37))
        body.addQuadCurve(to: CGPoint(x: 6, y: 37), control: CGPoint(x: 18, y: 43))
        body.closeSubpath()
        c.saveGState()
        shadow(c, dy: -0.8, blur: 2, rgb(0, 0, 0, 0.45))
        c.setFillColor(rgb(0.70, 0.06, 0.09))
        c.addPath(body)
        c.fillPath()
        c.restoreGState()
        c.saveGState()
        c.addPath(body)
        c.clip()
        c.drawLinearGradient(
            gradient([rgb(0.95, 0.22, 0.20), rgb(0.66, 0.05, 0.08)]), start: CGPoint(x: 0, y: 40), end: CGPoint(x: 0, y: 12), options: [])
        c.setStrokeColor(gold)
        c.setLineWidth(1.4)
        c.move(to: CGPoint(x: 14, y: 19))
        c.addQuadCurve(to: CGPoint(x: 38, y: 20), control: CGPoint(x: 26, y: 13))
        c.addQuadCurve(to: CGPoint(x: 60, y: 18), control: CGPoint(x: 50, y: 27))
        c.strokePath()
        c.restoreGState()
        c.setStrokeColor(gold)
        c.setLineWidth(1.6)
        c.move(to: CGPoint(x: 6, y: 37))
        c.addQuadCurve(to: CGPoint(x: 31, y: 37), control: CGPoint(x: 18, y: 43))
        c.addLine(to: CGPoint(x: 36, y: 25))
        c.addLine(to: CGPoint(x: 64, y: 25))
        c.addLine(to: CGPoint(x: 71, y: 30))
        c.strokePath()
        disc(c, CGPoint(x: 77, y: 31), 2, gold)
    }

    static let reindeerSize = CGSize(width: 54, height: 48)
    /// The top of the harness, where the reins tie on.
    static let reindeerHarness = CGPoint(x: 31, y: 30)
    static let reindeerNose = CGPoint(x: 51.5, y: 36.6)
    /// Two strides of a gallop.
    static let reindeer = [reindeerTexture(stride: 0, redNose: false), reindeerTexture(stride: 1, redNose: false)]
    /// The same, with a shiny red nose.
    static let rudolph = [reindeerTexture(stride: 0, redNose: true), reindeerTexture(stride: 1, redNose: true)]

    /// A reindeer facing right. Stride 0 has its legs stretched out, stride 1 gathered underneath.
    private static func reindeerTexture(stride: Int, redNose: Bool) -> SKTexture {
        texture(width: reindeerSize.width, height: reindeerSize.height) { c in
            let coat = rgb(0.58, 0.38, 0.22), dark = rgb(0.38, 0.24, 0.14), light = rgb(0.86, 0.73, 0.56)
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
            // Hip, knee, hoof. The far pair comes first and is drawn darker, behind the body.
            let legs: [(CGPoint, CGPoint, CGPoint)] =
                stride == 0
                ? [(p(31, 20), p(38, 12), p(44, 8)), (p(16, 20), p(9, 13), p(3, 10)), (p(33, 20), p(41, 13), p(47, 11)), (p(18, 20), p(11, 12), p(6, 7))]
                : [(p(31, 20), p(35, 11), p(31, 7)), (p(16, 20), p(20, 12), p(24, 7)), (p(33, 20), p(36, 12), p(34, 6)), (p(18, 20), p(23, 11), p(27, 8))]
            c.setLineCap(.round)
            c.setLineJoin(.round)
            func drawLeg(_ leg: (CGPoint, CGPoint, CGPoint), _ color: CGColor) {
                c.setStrokeColor(color)
                c.setLineWidth(3)
                c.move(to: leg.0)
                c.addLine(to: leg.1)
                c.addLine(to: leg.2)
                c.strokePath()
                disc(c, leg.2, 1.7, rgb(0.16, 0.11, 0.08))
            }
            drawLeg(legs[0], dark)
            drawLeg(legs[1], dark)

            // Tail, then the body, lit from above with a pale belly.
            c.setFillColor(light)
            c.fillEllipse(in: CGRect(x: 6.5, y: 26, width: 7, height: 5))
            let body = CGPath(ellipseIn: CGRect(x: 9, y: 16, width: 30, height: 15), transform: nil)
            c.saveGState()
            shadow(c, dy: -0.6, blur: 1.4, rgb(0, 0, 0, 0.4))
            c.setFillColor(coat)
            c.addPath(body)
            c.fillPath()
            c.restoreGState()
            c.saveGState()
            c.addPath(body)
            c.clip()
            c.drawLinearGradient(
                gradient([rgb(0.68, 0.47, 0.29), rgb(0.46, 0.29, 0.16)]), start: CGPoint(x: 0, y: 31), end: CGPoint(x: 0, y: 16), options: [])
            c.setFillColor(rgb(0.86, 0.73, 0.56, 0.8))
            c.fillEllipse(in: CGRect(x: 13, y: 13, width: 22, height: 7))
            c.restoreGState()
            drawLeg(legs[2], coat)
            drawLeg(legs[3], coat)

            // Neck, head, muzzle, ear and eye.
            c.setStrokeColor(coat)
            c.setLineWidth(7.5)
            c.move(to: CGPoint(x: 33, y: 26))
            c.addLine(to: CGPoint(x: 40, y: 35))
            c.strokePath()
            c.setFillColor(coat)
            c.fillEllipse(in: CGRect(x: 37, y: 33, width: 11, height: 8))
            c.setFillColor(light)
            c.fillEllipse(in: CGRect(x: 44, y: 33.5, width: 8, height: 5.5))
            c.setFillColor(dark)
            c.fillEllipse(in: CGRect(x: 36, y: 39, width: 5, height: 3))
            disc(c, CGPoint(x: 45, y: 39), 0.9, rgb(0.10, 0.07, 0.05))

            // Antlers.
            c.setStrokeColor(rgb(0.84, 0.72, 0.52))
            c.setLineWidth(1.5)
            for (a, b) in [
                (p(40, 40), p(37, 47)), (p(38.6, 43.5), p(42, 46.5)), (p(37.8, 45.4), p(34.5, 47)),
                (p(42.5, 40.5), p(44.5, 47)), (p(43.4, 43.6), p(47, 45.5)),
            ] {
                c.move(to: a)
                c.addLine(to: b)
            }
            c.strokePath()

            // Nose.
            if redNose {
                c.saveGState()
                shadow(c, dy: 0, blur: 3, rgb(1, 0.2, 0.15, 1))
                disc(c, reindeerNose, 2.2, rgb(1, 0.18, 0.14))
                c.restoreGState()
                disc(c, CGPoint(x: reindeerNose.x - 0.7, y: reindeerNose.y + 0.7), 0.7, rgb(1, 0.75, 0.70))
            } else {
                disc(c, reindeerNose, 1.6, rgb(0.15, 0.10, 0.08))
            }

            // Harness: a red strap with a gold bell.
            c.setFillColor(rgb(0.80, 0.12, 0.14))
            c.addPath(CGPath(roundedRect: CGRect(x: 29, y: 16.5, width: 4, height: 14), cornerWidth: 1.5, cornerHeight: 1.5, transform: nil))
            c.fillPath()
            disc(c, CGPoint(x: 31, y: 17), 2.2, rgb(1, 0.82, 0.30))
        }
    }
}
