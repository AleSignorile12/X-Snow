import SpriteKit

/// The snow lying on one window's top edge (or a widget's, or along the bottom of the screen).
///
/// The width is cut into thin columns and each column remembers how high its snow is.
/// Coordinates here are "local": x runs from the surface's left edge, y is the height above its top edge.
final class SnowPile {
    static let columnWidth: CGFloat = 3

    /// How snow behaves on one kind of surface.
    struct Style {
        /// The tallest a settled pile gets.
        let maxHeight: CGFloat
        /// How rounded the surface's corners are. The snow curves down around them.
        let cornerRadius: CGFloat
        /// Over this distance from each end the snow thins out to nothing.
        let taperLength: CGFloat
        /// The chance a flake landing on snow stays there. On a bare edge the chance is a fifth of this, so snow starts
        /// as scattered flecks that grow into patches and only slowly join up, and cleared snow takes minutes to return.
        let stickiness: CGFloat
        /// Carries a string of fairy lights when "Lights on Windows" is on.
        let hasLights: Bool
        /// The ends slope off gently, like a drift, instead of curving down steeply like snow on a rounded corner.
        var slopesOff = false

        static let window = Style(maxHeight: 13, cornerRadius: 11, taperLength: 13, stickiness: 0.3, hasLights: true)
        /// Widget cards have big round corners and only get a dusting.
        static let widget = Style(maxHeight: 6, cornerRadius: 19, taperLength: 16, stickiness: 0.22, hasLights: false)
        /// A deep drift along the bottom of the screen.
        static let ground = Style(maxHeight: 24, cornerRadius: 0, taperLength: 40, stickiness: 0.35, hasLights: false, slopesOff: true)
    }

    let style: Style
    /// Pushing snow along with the cursor can heap it this high for a moment.
    var heapHeight: CGFloat { style.maxHeight * 1.8 }
    var cornerRadius: CGFloat { style.cornerRadius }
    /// For the ground: the snow thins out only next to these x positions (the Dock's ends), not at the screen's edges.
    var thinsAt: [CGFloat]? {
        didSet {
            if thinsAt != oldValue { redraw(soon: true) }
        }
    }

    let node = SKSpriteNode()
    /// A string of fairy lights along the window's top edge. Sits at the same position as `node`.
    let lights = SKNode()
    private var bulbs: [SKSpriteNode] = []
    private var lightsNeedLayout = true
    private(set) var width: CGFloat = 0
    private var heights: [CGFloat] = []
    /// How high each column may fill. Varies gently along the window so the pile isn't a flat bar.
    private var limits: [CGFloat] = []
    private let seed = CGFloat.random(in: 0...1000)

    /// Scene position of the window's top-left corner, as of the last look at the window list.
    var origin: CGPoint?
    /// False while the window is minimised, hidden or on another Space.
    var onScreen = true {
        didSet {
            node.isHidden = !(onScreen && hasPicture)
            lights.isHidden = !onScreen
        }
    }
    /// The stretches of the top edge that no other window covers.
    var segments: [ClosedRange<CGFloat>] = [] {
        didSet {
            if segments != oldValue {
                redraw(soon: true)
                lightsNeedLayout = true
            }
        }
    }

    private var hasPicture = false { didSet { node.isHidden = !(onScreen && hasPicture) } }
    private var needsRedraw = false
    private var redrawSoon = false
    private var lastRedraw: TimeInterval = 0
    /// Frames left in which carved snow keeps slumping into a natural slope.
    private var settling = 0

    init(style: Style = .window) {
        self.style = style
        node.zPosition = 10
        lights.zPosition = 11
        node.isHidden = true
    }

    private func redraw(soon: Bool) {
        needsRedraw = true
        if soon { redrawSoon = true }
    }

    // MARK: Shape

    /// Follows the surface's new width. When it gets shorter, returns local points where the snow
    /// on the part that's gone should start falling.
    @discardableResult
    func resize(to newWidth: CGFloat) -> [CGPoint] {
        guard abs(newWidth - width) > 0.5 || heights.isEmpty else { return [] }
        width = newWidth
        lightsNeedLayout = true
        let count = max(1, Int((newWidth / Self.columnWidth).rounded(.up)))
        var loose: [CGPoint] = []
        if count < heights.count {
            for i in stride(from: count, to: heights.count, by: 2) where heights[i] > 1 && loose.count < 30 {
                let x = (CGFloat(i) + 0.5) * Self.columnWidth
                if isVisible(x) { loose.append(CGPoint(x: x, y: heights[i] * 0.6)) }
            }
            heights.removeLast(heights.count - count)
            limits.removeLast(limits.count - count)
        }
        while heights.count < count {
            let x = CGFloat(heights.count) * Self.columnWidth + seed
            let wave = sin(x * 0.021) * 0.5 + sin(x * 0.057 + 1.7) * 0.3 + sin(x * 0.13 + 4.1) * 0.2
            limits.append(style.maxHeight * (0.78 + 0.22 * wave))
            heights.append(0)
        }
        redraw(soon: true)
        return loose
    }

    /// Starts the pile with some patches of snow so a freshly launched app doesn't look bare.
    /// `fraction` is roughly how much of the edge is covered; the patches vary in depth, with bare gaps between.
    func prefill(_ fraction: CGFloat) {
        for i in heights.indices {
            let x = CGFloat(i) * Self.columnWidth + seed * 7
            let lumps = 0.5 + 0.5 * (sin(x * 0.011) * 0.5 + sin(x * 0.034 + 2.1) * 0.3 + sin(x * 0.087 + 0.7) * 0.2)
            let depth = max(0, (lumps - (1 - fraction)) / max(fraction, 0.01))
            heights[i] = limits[i] * min(1, depth * 1.4)
        }
        redraw(soon: true)
    }

    private func edgeDistance(_ x: CGFloat) -> CGFloat {
        guard let thinsAt else { return min(x, width - x) }
        return thinsAt.reduce(CGFloat.infinity) { min($0, abs($1 - x)) }
    }

    /// Snow thins out to nothing at the surface's two ends.
    private func taper(_ d: CGFloat) -> CGFloat {
        if d >= style.taperLength { return 1 }
        if d <= 0 { return 0 }
        if style.slopesOff {
            let t = d / style.taperLength
            return t * t * (3 - 2 * t)
        }
        let t = 1 - d / style.taperLength
        return sqrt(1 - t * t)
    }

    /// How far the surface's rounded corner dips below its top edge.
    private func drop(_ d: CGFloat) -> CGFloat {
        let r = style.cornerRadius
        if d >= r { return 0 }
        let t = r - max(0, d)
        return r - sqrt(r * r - t * t)
    }

    private func sample(_ values: [CGFloat], _ x: CGFloat) -> CGFloat {
        let f = x / Self.columnWidth - 0.5
        let i = Int(f.rounded(.down))
        let a = values[min(max(i, 0), values.count - 1)], b = values[min(max(i + 1, 0), values.count - 1)]
        return a + (b - a) * (f - CGFloat(i))
    }

    /// Height of the snow's surface at local x (negative on the rounded corners).
    func surface(at x: CGFloat) -> CGFloat {
        let d = edgeDistance(x)
        return sample(heights, x) * taper(d) - drop(d)
    }

    func isVisible(_ x: CGFloat) -> Bool { segments.contains { $0.contains(x) } }

    // MARK: Fairy lights

    /// One bulb every 26 points, shown only where no other window covers the edge.
    func updateLights(enabled wanted: Bool) {
        let enabled = wanted && style.hasLights
        guard lightsNeedLayout || enabled != !bulbs.isEmpty else { return }
        lightsNeedLayout = false
        let wanted = enabled ? max(0, Int((width - 28) / 26) + 1) : 0
        while bulbs.count > wanted { bulbs.removeLast().removeFromParent() }
        let palette: [SKColor] = [
            SKColor(srgbRed: 1, green: 0.27, blue: 0.27, alpha: 1), SKColor(srgbRed: 1, green: 0.84, blue: 0.30, alpha: 1),
            SKColor(srgbRed: 0.35, green: 1, blue: 0.50, alpha: 1), SKColor(srgbRed: 0.38, green: 0.65, blue: 1, alpha: 1),
        ]
        while bulbs.count < wanted {
            let i = bulbs.count
            let bulb = SKSpriteNode(texture: Art.glow)
            bulb.size = CGSize(width: 18, height: 18)
            bulb.color = palette[i % palette.count]
            bulb.colorBlendFactor = 1
            // The string dips between pegs: every other bulb hangs a little lower.
            bulb.position = CGPoint(x: 14 + CGFloat(i) * 26, y: i % 2 == 0 ? -3 : -6)
            let beat = Double.random(in: 0.5...1.3)
            bulb.run(
                .sequence([
                    .wait(forDuration: .random(in: 0...1.3)),
                    .repeatForever(.sequence([.fadeAlpha(to: 0.5, duration: beat), .fadeAlpha(to: 1, duration: beat)])),
                ]))
            lights.addChild(bulb)
            bulbs.append(bulb)
        }
        for bulb in bulbs { bulb.isHidden = !isVisible(bulb.position.x) }
    }

    // MARK: Adding and removing snow

    /// A flake lands at local x. Returns false when that spot is already full (the flake falls on past).
    /// Most flakes melt on contact; the ones that stay leave a small fleck.
    func deposit(at x: CGFloat, amount: CGFloat) -> Bool {
        let column = Int(x / Self.columnWidth)
        guard heights.indices.contains(column), heights[column] < limits[column] else { return false }
        // Snow sticks to snow far better than to a bare edge, so flecks grow into patches that spread and join.
        let cover = min(1, heights[column] / (style.maxHeight * 0.25))
        guard CGFloat.random(in: 0..<1) < style.stickiness * (0.2 + 0.8 * cover) else { return true }
        // A shallow surface (a widget) gets smaller flecks, so it doesn't fill up any faster than a window.
        let fleck = amount * 1.3 * min(1, style.maxHeight / Style.window.maxHeight)
        for k in -2...2 where heights.indices.contains(column + k) {
            let i = column + k
            let share = 0.5 + 0.5 * cos(CGFloat(k) / 3 * .pi)
            if heights[i] < limits[i] { heights[i] = min(limits[i], heights[i] + fleck * share) }
        }
        redraw(soon: false)
        return true
    }

    /// The cursor, treated as a ball, pushes through the snow.
    /// Half of what it scoops is shoved ahead of it (`direction` is -1 or 1), the rest is knocked loose.
    /// Returns local points where loose snow should start falling.
    func brush(x cx: CGFloat, y cy: CGFloat, radius: CGFloat, direction: Int) -> [CGPoint] {
        let first = max(0, Int((cx - radius) / Self.columnWidth))
        let last = min(heights.count - 1, Int((cx + radius) / Self.columnWidth))
        guard first <= last else { return [] }
        var loose: [CGPoint] = []
        var scooped: CGFloat = 0
        for i in first...last {
            let x = (CGFloat(i) + 0.5) * Self.columnWidth
            let dx = x - cx
            // The underside of the ball above this column.
            let floor = max(0, cy - sqrt(max(0, radius * radius - dx * dx)))
            guard heights[i] > floor else { continue }
            let removed = heights[i] - floor
            scooped += removed
            heights[i] = floor
            if removed > 1, loose.count < 6, isVisible(x) { loose.append(CGPoint(x: x, y: floor + removed * 0.6)) }
        }
        guard scooped > 0 else { return [] }
        if direction != 0 {
            let share = scooped * 0.5 / 4
            for k in 0..<4 {
                let i = (direction > 0 ? last + 1 : first - 1) + direction * k
                let x = (CGFloat(i) + 0.5) * Self.columnWidth
                if heights.indices.contains(i), isVisible(x) {
                    heights[i] = min(heapHeight, heights[i] + share)
                } else if share > 0.6 {
                    // Pushed off the end of the window.
                    loose.append(CGPoint(x: min(max(x, 0), width), y: 1))
                }
            }
        }
        settling = 45
        redraw(soon: true)
        return loose
    }

    /// Flattens the snow under something heavy (a tree landing).
    func press(at x: CGFloat, halfWidth: CGFloat, to fraction: CGFloat) {
        let first = max(0, Int((x - halfWidth) / Self.columnWidth))
        let last = min(heights.count - 1, Int((x + halfWidth) / Self.columnWidth))
        guard first <= last else { return }
        for i in first...last { heights[i] *= fraction }
        settling = 45
        redraw(soon: true)
    }

    /// Shakes off a share of the snow (1 = all of it). Returns local points where it should start falling.
    func shed(_ fraction: CGFloat, maxPoints: Int) -> [CGPoint] {
        guard let tallest = heights.max(), tallest > 0.3 else { return [] }
        var points: [CGPoint] = []
        let visible = segments.reduce(0) { $0 + $1.upperBound - $1.lowerBound }
        let wanted = min(maxPoints, Int(visible / 14 * min(1, fraction * 2.5)))
        for _ in 0..<max(0, wanted) {
            guard let seg = segments.randomElement() else { break }
            let x = CGFloat.random(in: seg)
            let top = surface(at: x)
            if top > 1 { points.append(CGPoint(x: x, y: top * .random(in: 0.3...1))) }
        }
        for i in heights.indices { heights[i] *= 1 - fraction }
        redraw(soon: true)
        return points
    }

    /// Steep walls left by the cursor slide down until the slope is gentle.
    private func settle() {
        let maxStep: CGFloat = 1.3
        for i in 0..<(heights.count - 1) {
            let d = heights[i] - heights[i + 1]
            if d > maxStep {
                let move = (d - maxStep) / 2
                heights[i] -= move
                heights[i + 1] += move
            } else if d < -maxStep {
                let move = (-d - maxStep) / 2
                heights[i] += move
                heights[i + 1] -= move
            }
        }
    }

    // MARK: Drawing

    /// Redraws the pile's picture when it has changed. Slow growth is batched; anything the user caused shows at once.
    func update(now: TimeInterval, scale: CGFloat) {
        if settling > 0 {
            settling -= 1
            settle()
            redraw(soon: true)
        }
        guard onScreen, needsRedraw, now - lastRedraw > (redrawSoon ? 0.06 : 0.5) else { return }
        needsRedraw = false
        redrawSoon = false
        lastRedraw = now

        guard !segments.isEmpty, width > 0 else {
            hasPicture = false
            return
        }
        // Soften column-to-column steps before drawing.
        var smooth = heights
        if heights.count > 2 {
            for i in 1..<(heights.count - 1) { smooth[i] = (heights[i - 1] + 2 * heights[i] + heights[i + 1]) / 4 }
        }
        var shapes: [(outline: CGPath, crest: CGPath)] = []
        for seg in segments { shapes += paths(for: seg, heights: smooth) }
        guard !shapes.isEmpty else {
            hasPicture = false
            return
        }

        // Plain fills only: this runs often and for every window, so no blurs or wide strokes.
        let pad: CGFloat = 6
        let below = style.cornerRadius + 5
        let size = CGSize(width: (width + pad * 2).rounded(.up), height: (below + heapHeight + 6).rounded(.up))
        node.texture = Art.texture(width: size.width, height: size.height, scale: scale) { c in
            c.translateBy(x: pad, y: below)
            for shape in shapes {
                // A faint shadow underneath, so the snow still reads on a white window.
                c.saveGState()
                c.translateBy(x: 0, y: -1.2)
                c.setFillColor(Art.rgb(0.05, 0.12, 0.30, 0.28))
                c.addPath(shape.outline)
                c.fillPath()
                c.restoreGState()
                // Blue-grey body, white along the top as if lit from above.
                c.setFillColor(Art.rgb(0.80, 0.87, 0.97))
                c.addPath(shape.outline)
                c.fillPath()
                c.setFillColor(Art.rgb(1, 1, 1))
                c.addPath(shape.crest)
                c.fillPath()
            }
        }
        node.size = size
        node.anchorPoint = CGPoint(x: pad / size.width, y: below / size.height)
        hasPicture = true
    }

    /// The snow over one visible stretch of the edge: one shape per patch (bare stretches draw nothing),
    /// each with a bright band along its top.
    private func paths(for seg: ClosedRange<CGFloat>, heights: [CGFloat]) -> [(outline: CGPath, crest: CGPath)] {
        let start = max(0, seg.lowerBound), end = min(width, seg.upperBound)
        guard end - start > 4 else { return [] }
        var shapes: [(outline: CGPath, crest: CGPath)] = []
        var top: [CGPoint] = [], bottom: [CGPoint] = [], band: [CGPoint] = []
        var peak: CGFloat = 0

        func closePatch() {
            if top.count > 1, peak > 0.45 {
                let outline = CGMutablePath()
                outline.addLines(between: top + bottom.reversed())
                outline.closeSubpath()
                let crest = CGMutablePath()
                crest.addLines(between: top + band.reversed())
                crest.closeSubpath()
                shapes.append((outline, crest))
            }
            top.removeAll(keepingCapacity: true)
            bottom.removeAll(keepingCapacity: true)
            band.removeAll(keepingCapacity: true)
            peak = 0
        }

        var x = start
        while true {
            let d = edgeDistance(x), thin = taper(d), base = -drop(d)
            let h = sample(heights, x) * thin
            if h > 0.12 {
                peak = max(peak, h)
                // Dips below the edge (as far as the snow is deep, up to 2.5) so no gap shows between snow and window.
                let low = base - min(2.5, h * 0.9)
                top.append(CGPoint(x: x, y: base + h))
                bottom.append(CGPoint(x: x, y: low))
                band.append(CGPoint(x: x, y: max(low, base + h - 4.5)))
            } else {
                closePatch()
            }
            if x >= end { break }
            // Finer steps near the ends, where the outline curves.
            x = min(end, x + (d < style.taperLength + 3 ? 1.5 : 3))
        }
        closePatch()
        return shapes
    }
}
