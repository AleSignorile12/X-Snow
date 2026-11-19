import SpriteKit

/// Santa in his sleigh behind four galloping reindeer (Rudolph in front), flying across the screen once.
final class SantaSleigh: SKNode {
    /// Where each reindeer stands relative to the back of the sleigh.
    private static let deerSpacing: CGFloat = 48
    private static let firstDeerX: CGFloat = 92
    private static let deerY: CGFloat = 10
    private static let scale: CGFloat = 0.9
    /// From the back of the sleigh to Rudolph's nose.
    private static let length = (firstDeerX + 3 * deerSpacing + Art.reindeerSize.width) * scale

    private let direction: CGFloat
    private let startX: CGFloat
    private let endX: CGFloat
    private let baseY: CGFloat
    private let climb: CGFloat
    private let flightSpeed: CGFloat = 180
    private var age: CGFloat = 0
    private var gone: CGFloat = 0

    private var deer: [SKSpriteNode] = []
    private let reins = SKShapeNode()
    private let noseGlow = SKSpriteNode(texture: Art.glow)
    /// A trail of golden sparkles. It lives in the parent, so the sparkles stay put while the sleigh flies on.
    let trail = SKEmitterNode()

    init(sceneSize: CGSize) {
        direction = Bool.random() ? 1 : -1
        let margin: CGFloat = 40
        startX = direction > 0 ? -Self.length - margin : sceneSize.width + Self.length + margin
        endX = direction > 0 ? sceneSize.width + margin : -margin
        baseY = sceneSize.height * .random(in: 0.55...0.8)
        climb = .random(in: -90...90)
        super.init()
        zPosition = 35
        xScale = Self.scale * direction
        yScale = Self.scale
        position = CGPoint(x: startX, y: baseY)

        reins.strokeColor = SKColor(srgbRed: 0.55, green: 0.32, blue: 0.16, alpha: 1)
        reins.lineWidth = 1
        reins.zPosition = 1
        addChild(reins)

        let sleigh = SKSpriteNode(texture: Art.sleigh)
        sleigh.size = Art.sleighSize
        sleigh.anchorPoint = .zero
        sleigh.zPosition = 2
        addChild(sleigh)

        for i in 0..<4 {
            let reindeer = SKSpriteNode(texture: (i == 3 ? Art.rudolph : Art.reindeer)[0])
            reindeer.size = Art.reindeerSize
            reindeer.anchorPoint = .zero
            reindeer.position = CGPoint(x: Self.firstDeerX + CGFloat(i) * Self.deerSpacing, y: Self.deerY)
            reindeer.zPosition = 2
            addChild(reindeer)
            deer.append(reindeer)
        }

        noseGlow.size = CGSize(width: 18, height: 18)
        noseGlow.color = SKColor(srgbRed: 1, green: 0.15, blue: 0.12, alpha: 1)
        noseGlow.colorBlendFactor = 1
        noseGlow.zPosition = 3
        noseGlow.run(.repeatForever(.sequence([.fadeAlpha(to: 0.45, duration: 0.5), .fadeAlpha(to: 1, duration: 0.5)])))
        addChild(noseGlow)

        trail.particleTexture = Art.glow
        trail.particleBirthRate = 70
        trail.particleLifetime = 1.6
        trail.particleLifetimeRange = 0.7
        trail.particleSpeed = 16
        trail.particleSpeedRange = 12
        trail.emissionAngle = direction > 0 ? .pi : 0
        trail.emissionAngleRange = 0.9
        trail.particlePositionRange = CGVector(dx: 6, dy: 14)
        trail.particleAlpha = 0.9
        trail.particleAlphaRange = 0.2
        trail.particleAlphaSpeed = -0.6
        trail.particleScale = 0.28
        trail.particleScaleRange = 0.15
        trail.particleScaleSpeed = -0.12
        trail.particleColor = SKColor(srgbRed: 1, green: 0.86, blue: 0.5, alpha: 1)
        trail.particleColorBlendFactor = 1
        trail.yAcceleration = -10
        trail.zPosition = 34
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Flies on one frame. Returns false once it is off the far side and the last sparkles have faded.
    func update(dt: CGFloat, time: TimeInterval) -> Bool {
        age += dt
        let total = abs(endX - startX)
        let travelled = min(total, age * flightSpeed)
        let progress = travelled / total
        // Rises or sinks a little over the trip, and bobs gently as the reindeer pull.
        let bob = 12 * sin(age * 1.3)
        position = CGPoint(x: startX + direction * travelled, y: baseY + climb * (progress - 0.5) + bob)
        let slope = climb / total + 12 * 1.3 * cos(age * 1.3) / flightSpeed
        zRotation = direction * atan(slope) * 0.8

        // The team gallops: legs swap every tenth of a second, pairs out of step, each bobbing in turn.
        let t = CGFloat(time)
        var harnesses: [CGPoint] = []
        for (i, reindeer) in deer.enumerated() {
            let stride = (Int(t / 0.1) + i) % 2
            reindeer.texture = (i == 3 ? Art.rudolph : Art.reindeer)[stride]
            reindeer.position.y = Self.deerY + 2.5 * sin(t * 7 + CGFloat(i) * 0.9)
            harnesses.append(CGPoint(x: reindeer.position.x + Art.reindeerHarness.x, y: reindeer.position.y + Art.reindeerHarness.y))
        }
        if let lead = deer.last {
            noseGlow.position = CGPoint(x: lead.position.x + Art.reindeerNose.x, y: lead.position.y + Art.reindeerNose.y)
        }
        let path = CGMutablePath()
        path.move(to: Art.santaHands)
        for point in harnesses { path.addLine(to: point) }
        reins.path = path

        if let parent {
            if trail.parent == nil {
                parent.addChild(trail)
                trail.targetNode = parent
            }
            trail.position = convert(Art.sleighBack, to: parent)
        }

        guard travelled >= total else { return true }
        // Off the screen: stop sparkling and wait for the trail to fade.
        trail.particleBirthRate = 0
        gone += dt
        return gone < 2.5
    }
}
