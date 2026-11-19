import SpriteKit

/// A string of big old-fashioned bulbs with a hook on its loose end. It hangs from an eyelet in the side of the screen,
/// or from a hook under the menu bar where another string was fastened.
///
/// Drag the hook onto a window, the top of the screen or either side, and the lights drape between the two.
/// Fastened to the top of the screen, the lights carry on: a new string hangs from that spot, ready to drape further.
final class LightString: SKNode {
    /// What the string hangs from.
    enum Anchor {
        /// An eyelet in the side of the screen. Even slots are on the left, odd on the right, working down.
        case side(slot: Int)
        /// A hook under the menu bar, `x` along, where another string was fastened. This one carries on from it.
        case top(x: CGFloat)
    }

    /// Where the loose end is fastened.
    enum Home {
        /// On a window's top edge, this far in from its left.
        case window(CGWindowID, offset: CGFloat)
        /// On an eyelet in the left or right side of the screen (`x` is the eyelet's ring).
        case edge(x: CGFloat, y: CGFloat)
        /// On a hook under the menu bar.
        case top(x: CGFloat)
    }

    private enum State {
        /// Hanging loose from its anchor.
        case dangling
        /// In the user's hand.
        case held
        /// Fastened. `settled` turns true once the hook has reached its spot; from then on it sticks rigidly.
        case hooked(settled: Bool)
        /// Swinging back to hang from its anchor.
        case reelingIn
    }

    private enum Border { case left, right, top }

    private struct Bulb {
        let node: SKNode
        let glow: SKSpriteNode
        let glass: SKSpriteNode
    }

    /// How much wire hangs below the anchor when nothing holds the hook.
    private static let slack: CGFloat = 54
    /// Distance between bulbs along the wire.
    private static let spacing: CGFloat = 23
    private static let palette: [SKColor] = [
        SKColor(srgbRed: 1, green: 0.22, blue: 0.22, alpha: 1), SKColor(srgbRed: 1, green: 0.80, blue: 0.25, alpha: 1),
        SKColor(srgbRed: 0.25, green: 0.90, blue: 0.42, alpha: 1), SKColor(srgbRed: 0.32, green: 0.58, blue: 1, alpha: 1),
        SKColor(srgbRed: 1, green: 0.50, blue: 0.20, alpha: 1),
    ]
    private static let warmWhite = SKColor(srgbRed: 1, green: 0.85, blue: 0.55, alpha: 1)
    private static let chaseColors = [SKColor(srgbRed: 1, green: 0.22, blue: 0.22, alpha: 1), SKColor(srgbRed: 0.30, green: 1, blue: 0.45, alpha: 1)]

    let anchorKind: Anchor
    /// The eyelet slot, for a string tied to the side of the screen.
    var slot: Int? {
        if case .side(let slot) = anchorKind { return slot }
        return nil
    }
    /// How far along the top of the screen it hangs from, for a string that carries on from another.
    var topX: CGFloat? {
        if case .top(let x) = anchorKind { return x }
        return nil
    }
    private(set) var home: Home?

    private let sceneSize: CGSize
    /// The underside of the menu bar.
    private let top: CGFloat
    /// Where the wire is tied: the ring of the eyelet (or hook) it hangs from.
    private let anchor: CGPoint
    private var state: State = .dangling
    private var homeHiddenFor: CGFloat = 0
    private var homeShownFor: CGFloat = 0
    /// The hook's eye, where the wire ends.
    private var hookPoint: CGPoint
    private var swing: CGFloat = 0.25
    private var swingSpeed: CGFloat = 0
    /// All colours twinkling, warm white, or red and green chasing. A click on any bulb moves to the next.
    private var lightMode = 0

    private let wire = SKShapeNode()
    private let hook = SKSpriteNode(texture: Art.hook)
    /// The eyelet (or hook) the loose end is fastened to, when it's on the screen's border.
    private let endEyelet = LightString.makeEyelet()
    private var bulbs: [Bulb] = []

    /// `top` is the underside of the menu bar.
    init(anchor kind: Anchor, sceneSize: CGSize, top: CGFloat) {
        anchorKind = kind
        self.sceneSize = sceneSize
        self.top = top
        switch kind {
        case .side(let slot):
            let y = top - 48 - CGFloat(slot / 2) * 64
            anchor = CGPoint(x: slot % 2 == 0 ? Art.eyeletRing.x : sceneSize.width - Art.eyeletRing.x, y: y)
        case .top(let x):
            anchor = CGPoint(x: x, y: top - Art.eyeletRing.x)
        }
        hookPoint = CGPoint(x: anchor.x, y: anchor.y - Self.slack)
        super.init()
        zPosition = 24

        let eyelet = Self.makeEyelet()
        switch kind {
        case .side(let slot): mount(eyelet, on: slot % 2 == 0 ? .left : .right, at: anchor.y)
        case .top(let x): mount(eyelet, on: .top, at: x)
        }
        addChild(eyelet)
        endEyelet.isHidden = true
        addChild(endEyelet)

        wire.strokeColor = SKColor(srgbRed: 0.10, green: 0.24, blue: 0.13, alpha: 1)
        wire.lineWidth = 1.4
        wire.lineCap = .round
        wire.fillColor = .clear
        addChild(wire)

        hook.size = Art.hookSize
        hook.anchorPoint = CGPoint(x: Art.hookEye.x / Art.hookSize.width, y: Art.hookEye.y / Art.hookSize.height)
        hook.zPosition = 4
        addChild(hook)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private static func makeEyelet() -> SKSpriteNode {
        let eyelet = SKSpriteNode(texture: Art.eyelet)
        eyelet.size = Art.eyeletSize
        eyelet.anchorPoint = CGPoint(x: 0, y: Art.eyeletRing.y / Art.eyeletSize.height)
        eyelet.zPosition = 3
        return eyelet
    }

    /// Screws an eyelet into the screen's border, pointing in from the left or right edge, or down from under the menu bar.
    private func mount(_ eyelet: SKSpriteNode, on border: Border, at along: CGFloat) {
        switch border {
        case .left:
            eyelet.position = CGPoint(x: 0, y: along)
            eyelet.xScale = 1
            eyelet.zRotation = 0
        case .right:
            eyelet.position = CGPoint(x: sceneSize.width, y: along)
            eyelet.xScale = -1
            eyelet.zRotation = 0
        case .top:
            eyelet.position = CGPoint(x: along, y: top)
            eyelet.xScale = 1
            eyelet.zRotation = -.pi / 2
        }
    }

    func hookIsUnder(_ p: CGPoint) -> Bool {
        hypot(p.x - hookPoint.x, p.y - (hookPoint.y - 7)) < 17
    }

    /// True when the point is on one of the bulbs.
    func bulbIsUnder(_ p: CGPoint) -> Bool {
        bulbs.contains { !$0.node.isHidden && hypot(p.x - $0.node.position.x, p.y - ($0.node.position.y - 7)) < 8 }
    }

    /// Where the hook is now, for naming the string in the menu.
    var hookX: CGFloat { hookPoint.x }

    func pickUp() {
        state = .held
        home = nil
    }

    /// Dropped: fasten to the nearest window edge, the top of the screen or either side, otherwise swing back.
    func letGo(platforms: [Platform]) {
        // Dropped back where it hangs from: put it away.
        if hypot(hookPoint.x - anchor.x, hookPoint.y - (anchor.y - Self.slack / 2)) < 50 {
            state = .reelingIn
            return
        }
        var best: (Home, CGFloat)?
        func consider(_ home: Home, miss: CGFloat) {
            if miss < best?.1 ?? .infinity { best = (home, miss) }
        }
        for p in platforms {
            let x = hookPoint.x - p.left
            let miss = abs(hookPoint.y - 6 - p.top)
            guard x >= 10, x <= p.width - 10, miss < 36, p.pile.isVisible(x) else { continue }
            consider(.window(p.id, offset: x), miss: miss)
        }
        let topMiss = abs(hookPoint.y - (top - Art.eyeletRing.x))
        if topMiss < 40, hookPoint.x > 40, hookPoint.x < sceneSize.width - 40 {
            consider(.top(x: hookPoint.x), miss: topMiss)
        }
        if hookPoint.y > 30, hookPoint.y < top - 24 {
            for x in [Art.eyeletRing.x, sceneSize.width - Art.eyeletRing.x] where abs(hookPoint.x - x) < 50 {
                consider(.edge(x: x, y: hookPoint.y), miss: abs(hookPoint.x - x) * 0.5)
            }
        }
        guard let (home, _) = best else {
            state = .reelingIn
            return
        }
        self.home = home
        homeHiddenFor = 0
        state = .hooked(settled: false)
    }

    /// A click on a bulb: on to the next way of lighting up.
    func cycleLights() {
        lightMode = (lightMode + 1) % 3
        for (i, bulb) in bulbs.enumerated() { light(bulb, index: i) }
    }

    func update(dt: CGFloat, time: TimeInterval, platforms: [Platform], mouse: CGPoint) {
        // Where the hook belongs, if that spot can be seen right now.
        var homePoint: CGPoint?
        switch home {
        case .window(let id, let offset):
            if let p = platforms.first(where: { $0.id == id }) {
                if offset < 6 || offset > p.width - 6 {
                    home = nil
                } else if p.pile.isVisible(offset) {
                    homePoint = CGPoint(x: p.left + offset, y: p.top + 6)
                }
            } else if homeHiddenFor > 1, !WindowTracker.exists(id) {
                home = nil
            }
        case .edge(let x, let y):
            homePoint = CGPoint(x: x, y: y)
        case .top(let x):
            homePoint = CGPoint(x: x, y: top - Art.eyeletRing.x)
        case nil:
            break
        }
        if homePoint == nil {
            homeHiddenFor += dt
            homeShownFor = 0
        } else {
            homeHiddenFor = 0
            homeShownFor += dt
        }

        switch state {
        case .dangling:
            // An eyelet in the side of the screen leaves little room to swing; a hook under the menu bar leaves plenty.
            let limit: CGFloat = slot == nil ? 0.55 : 0.3
            swingSpeed += (-26 * swing - 1.4 * swingSpeed + (slot == nil ? 0.9 : 0.45) * sin(CGFloat(time) * 0.8 + anchor.x)) * dt
            swing = max(-limit, min(limit, swing + swingSpeed * dt))
            hookPoint = CGPoint(x: anchor.x + Self.slack * sin(swing), y: anchor.y - Self.slack * cos(swing))
            // Its window came back: hook on again.
            if homeShownFor > 0.3 { state = .hooked(settled: false) }

        case .held:
            let ease = min(1, dt * 30)
            hookPoint.x += (mouse.x - hookPoint.x) * ease
            hookPoint.y += (mouse.y + 7 - hookPoint.y) * ease

        case .hooked(let settled):
            if let homePoint {
                if settled {
                    hookPoint = homePoint
                } else {
                    let ease = min(1, dt * 10)
                    hookPoint.x += (homePoint.x - hookPoint.x) * ease
                    hookPoint.y += (homePoint.y - hookPoint.y) * ease
                    if hypot(homePoint.x - hookPoint.x, homePoint.y - hookPoint.y) < 3 { state = .hooked(settled: true) }
                }
            } else if home == nil || homeHiddenFor > 0.6 {
                // The window closed, or something is covering it.
                state = .reelingIn
            }

        case .reelingIn:
            let rest = CGPoint(x: anchor.x, y: anchor.y - Self.slack)
            let ease = min(1, dt * 7)
            hookPoint.x += (rest.x - hookPoint.x) * ease
            hookPoint.y += (rest.y - hookPoint.y) * ease
            if hypot(rest.x - hookPoint.x, rest.y - hookPoint.y) < 2 {
                state = .dangling
                swing = 0
                swingSpeed = anchor.x < sceneSize.width / 2 ? 1.2 : -1.2
            }
        }

        layOut(time: time)
    }

    /// Draws the wire as a sagging curve and hangs bulbs along it at even spacing.
    private func layOut(time: TimeInterval) {
        let dx = hookPoint.x - anchor.x, dy = hookPoint.y - anchor.y
        let span = hypot(dx, dy)
        // A string draped sideways sags in the middle; one hanging straight down doesn't.
        let sag = span > 1 ? (8 + span * 0.1) * abs(dx) / span : 0
        let control = CGPoint(x: (anchor.x + hookPoint.x) / 2, y: (anchor.y + hookPoint.y) / 2 - sag)
        let path = CGMutablePath()
        path.move(to: anchor)
        path.addQuadCurve(to: hookPoint, control: control)
        wire.path = path

        // Measure the curve so the bulbs can be spaced evenly along its length.
        let samples = 48
        var points = [anchor]
        var lengths: [CGFloat] = [0]
        for i in 1...samples {
            let t = CGFloat(i) / CGFloat(samples), u = 1 - t
            let p = CGPoint(
                x: u * u * anchor.x + 2 * u * t * control.x + t * t * hookPoint.x,
                y: u * u * anchor.y + 2 * u * t * control.y + t * t * hookPoint.y)
            lengths.append(lengths[i - 1] + hypot(p.x - points[i - 1].x, p.y - points[i - 1].y))
            points.append(p)
        }
        let total = lengths[samples]
        // From just past the anchor to just short of the hook.
        let count = total < 24 ? 0 : min(120, Int((total - 24) / Self.spacing) + 1)
        while bulbs.count < count { bulbs.append(makeBulb(index: bulbs.count)) }

        var k = 0
        let t = CGFloat(time)
        let chaseStep = Int(t / 0.22)
        for (i, bulb) in bulbs.enumerated() {
            guard i < count else {
                bulb.node.isHidden = true
                continue
            }
            let s = 12 + CGFloat(i) * Self.spacing
            while k < samples - 1, lengths[k + 1] < s { k += 1 }
            let f = (s - lengths[k]) / max(lengths[k + 1] - lengths[k], 0.001)
            bulb.node.position = CGPoint(
                x: points[k].x + (points[k + 1].x - points[k].x) * f, y: points[k].y + (points[k + 1].y - points[k].y) * f)
            // Each bulb hangs straight down from the wire and stirs a little.
            bulb.node.zRotation = 0.12 * sin(t * 1.6 + CGFloat(i) * 0.9)
            bulb.node.isHidden = false
            // The chase is driven from the clock so every bulb stays in step, however long the string grows.
            if lightMode == 2 { bulb.glow.alpha = (chaseStep - i) % 3 == 0 ? 1 : 0.15 }
        }

        hook.position = hookPoint
        if case .dangling = state { hook.zRotation = swing } else { hook.zRotation *= 0.8 }
        endEyelet.isHidden = true
        if case .hooked = state {
            switch home {
            case .edge(let x, let y):
                mount(endEyelet, on: x < sceneSize.width / 2 ? .left : .right, at: y)
                endEyelet.isHidden = false
            case .top(let x):
                mount(endEyelet, on: .top, at: x)
                endEyelet.isHidden = false
            default:
                break
            }
        }
    }

    /// One bulb: green cap, coloured glass and a soft halo.
    private func makeBulb(index: Int) -> Bulb {
        let node = SKNode()
        let glow = SKSpriteNode(texture: Art.glow)
        glow.size = CGSize(width: 24, height: 24)
        glow.position = CGPoint(x: 0, y: -2.5 - Art.bulbSize.height * 0.45)
        glow.colorBlendFactor = 1
        glow.zPosition = -1
        node.addChild(glow)

        let glass = SKSpriteNode(texture: Art.bulbGlass)
        glass.size = Art.bulbSize
        glass.anchorPoint = CGPoint(x: 0.5, y: 1)
        glass.position = CGPoint(x: 0, y: -2.5)
        glass.colorBlendFactor = 0.8
        node.addChild(glass)

        let cap = SKSpriteNode(texture: Art.bulbCap)
        cap.size = Art.bulbCapSize
        cap.anchorPoint = CGPoint(x: 0.5, y: 1)
        cap.position = CGPoint(x: 0, y: 0.6)
        cap.zPosition = 1
        node.addChild(cap)

        node.zPosition = 2
        addChild(node)
        let bulb = Bulb(node: node, glow: glow, glass: glass)
        light(bulb, index: index)
        return bulb
    }

    /// Colours a bulb and sets it twinkling for the current light mode.
    private func light(_ bulb: Bulb, index i: Int) {
        let glow = bulb.glow
        glow.removeAllActions()
        switch lightMode {
        case 0:
            // Every colour, each bulb twinkling to its own rhythm.
            let color = Self.palette[i % Self.palette.count]
            glow.color = color
            bulb.glass.color = color
            glow.alpha = 0.85
            let beat = Double.random(in: 0.6...1.4)
            glow.run(
                .sequence([
                    .wait(forDuration: .random(in: 0...1.4)),
                    .repeatForever(.sequence([.fadeAlpha(to: 0.35, duration: beat), .fadeAlpha(to: 0.9, duration: beat)])),
                ]))
        case 1:
            // Warm white with a slow shimmer.
            glow.color = Self.warmWhite
            bulb.glass.color = Self.warmWhite
            glow.alpha = 0.8
            let beat = Double.random(in: 0.9...1.7)
            glow.run(.repeatForever(.sequence([.fadeAlpha(to: 0.5, duration: beat), .fadeAlpha(to: 0.9, duration: beat)])))
        default:
            // Red and green chasing along the string (the blinking is done in layOut).
            let color = Self.chaseColors[i % 2]
            glow.color = color
            bulb.glass.color = color
        }
    }
}
