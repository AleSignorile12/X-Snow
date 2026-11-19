import SpriteKit

/// Everything drawn on one screen: falling snow, the snow lying on windows, widgets and the bottom of the screen,
/// and (on the main screen) decorations, the cable cars, hanging lights, the plow and Santa.
/// Scene coordinates are points with the origin at the screen's bottom-left corner.
final class SnowScene: SKScene {
    /// The made-up window number of the drift along the bottom of the screen.
    static let groundID = CGWindowID.max - 1

    private let screen: NSScreen
    /// Decorations live only on the main screen, the one with the notch.
    private let isMain: Bool
    /// The screen's top-left corner in global Quartz coordinates (y grows downward), which window frames are given in.
    private let quartzOrigin: CGPoint

    private let snowfall: Snowfall
    /// Everything except the falling snow. Fades out while Mission Control is showing.
    private let world = SKNode()
    /// The same, in the window just below the Dock: the drift along the bottom of the screen, and the plow while it clears it.
    private let underWorld = SKNode()
    /// The scene in the window below the Dock.
    private let under: SKScene
    private var piles: [CGWindowID: SnowPile] = [:]
    private var ground: SnowPile?
    private var platforms: [Platform] = []
    private var trees: [TreeNode] = []
    private var ropeways: [Ropeway] = []
    private var lightStrings: [LightString] = []
    private var plow: Plow?
    private var santa: SantaSleigh?
    private var nextSanta: TimeInterval = 0
    private var santaWasOn = false
    private var treesMade = 0

    private var lastTime: TimeInterval = 0
    private var lastLook: TimeInterval = 0
    /// While windows are moving, their positions are read every frame; otherwise ten times a second is plenty.
    private var lookOftenUntil: TimeInterval = 0
    private var lastPrune: TimeInterval = 0
    private var firstLook = true

    /// Mission Control (or App Exposé) is showing every window as a thumbnail.
    private var missionControl = false
    /// After Mission Control closes the windows fly back into place; until then the snow stays hidden and nothing is shaken off.
    private var calmUntil: TimeInterval = 0
    /// An app is full screen here, so the menu bar only slides down when the pointer goes to the top.
    private var fullScreen = false
    /// The "always hide the menu bar" setting is on.
    private var menuBarAutohides = false
    private var lastPrefsRead: TimeInterval = -10
    private var pointerAtTopFor: CGFloat = 0
    /// The stretch of the bottom edge the Dock covers (scene x), with a little room either side.
    private var dockSpan: ClosedRange<CGFloat>?
    /// Windows that just went away (closed, minimised, hidden), and when. A moment later the snow on them falls,
    /// unless it turns out the whole Space changed; then it's kept for when you come back.
    private var vanished: [CGWindowID: TimeInterval] = [:]
    /// When the Space last changed, or the screens slept or locked: windows going away then weren't closed.
    private var spaceChangedAt: TimeInterval = -10

    private var mouse: CGPoint
    private var mouseVelocity = CGVector.zero

    private enum Held {
        case tree(TreeNode)
        case hook(Ropeway)
        case lights(LightString)
        case plow
    }

    #if DEBUG
        /// `-noPrefill YES` starts every window bare, to watch the snow build up from nothing.
        private static let prefills = !UserDefaults.standard.bool(forKey: "noPrefill")
    #else
        private static let prefills = true
    #endif

    /// Where the plow parks (global, y up): the middle of the empty part of the snowflake's menu bar item. Set by the app.
    static var parkingSpot: () -> CGPoint? = { nil }
    private var held: Held?
    private var heldSince: TimeInterval = 0
    private var heldFrom = CGPoint.zero

    /// `under` is the scene of the window just below the Dock.
    init(screen: NSScreen, isMain: Bool, under: SKScene) {
        self.screen = screen
        self.isMain = isMain
        self.under = under
        let mainHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        quartzOrigin = CGPoint(x: screen.frame.minX, y: mainHeight - screen.frame.maxY)
        snowfall = Snowfall(size: screen.frame.size)
        let location = NSEvent.mouseLocation
        mouse = CGPoint(x: location.x - screen.frame.minX, y: location.y - screen.frame.minY)
        super.init(size: screen.frame.size)
        backgroundColor = .clear
        scaleMode = .resizeFill
        addChild(world)
        addChild(snowfall.layer)
        under.addChild(underWorld)
        applySettings()
        NotificationCenter.default.addObserver(self, selector: #selector(applySettings), name: Settings.changed, object: nil)
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification,
        ] {
            workspace.addObserver(self, selector: #selector(spaceChanged), name: name, object: nil)
        }
    }

    @objc private func spaceChanged() { spaceChangedAt = lastTime }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Layout

    /// Height of the menu bar or notch, whichever is taller.
    private var topInset: CGFloat { max(screen.safeAreaInsets.top, screen.frame.maxY - screen.visibleFrame.maxY) }

    /// The top of the Dock, or the bottom of the screen when the Dock is hidden or on a side.
    private var floorY: CGFloat { screen.visibleFrame.minY - screen.frame.minY }

    /// True when the point is on the Dock.
    private func isOnDock(_ p: CGPoint) -> Bool {
        guard let dockSpan else { return false }
        return dockSpan.contains(p.x) && p.y < floorY
    }

    /// How low a decoration can fall at x: onto the Dock where the Dock is, the very bottom of the screen anywhere else.
    private func floorHeight(at x: CGFloat) -> CGFloat {
        if let dockSpan, dockSpan.contains(x) { return floorY }
        return 0
    }

    /// Where the rope's pulley hangs: from the underside of the notch, a little left of centre.
    private var notchAnchor: CGPoint {
        var x = size.width / 2
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            x = (left.maxX + right.minX) / 2 - screen.frame.minX - (right.minX - left.maxX) * 0.18
        }
        return CGPoint(x: x, y: size.height - topInset - (Art.bracketSize.height - Art.bracketWheel.y))
    }

    @objc private func applySettings() {
        let settings = Settings.shared
        let area = Double(size.width * size.height) / 1_000_000
        snowfall.setFlakeCount(Int(settings.intensity.density * area))
        snowfall.windSpeed = settings.wind.speed
        if !settings.piles { shakeOff(windowsOnly: true) }

        if settings.ground, ground == nil {
            let pile = SnowPile(style: .ground)
            pile.thinsAt = []
            pile.resize(to: size.width)
            // Some snow is already down, at launch and the moment it's switched on.
            if Self.prefills { pile.prefill(firstLook ? .random(in: 0.45...0.7) : 0.3) }
            // In the window below the Dock, so it lies underneath the Dock rather than on top of it.
            underWorld.addChild(pile.node)
            ground = pile
        } else if !settings.ground, let ground {
            ground.node.removeFromParent()
            self.ground = nil
        }
        guard isMain else { return }

        for kind in PropKind.allCases {
            let wanted = settings.count(of: kind)
            while trees.filter({ $0.kind == kind }).count > wanted, let index = trees.lastIndex(where: { $0.kind == kind }) {
                trees.remove(at: index).removeFromParent()
            }
            while trees.filter({ $0.kind == kind }).count < wanted {
                // New decorations drop in from above and land on whatever is underneath.
                let tree = TreeNode(kind: kind)
                // In front of the snow, and newer ones in front of older ones.
                treesMade += 1
                tree.restingZ = 14 + CGFloat(treesMade) * 0.01
                tree.zPosition = tree.restingZ
                tree.position = CGPoint(x: size.width * .random(in: 0.25...0.75), y: size.height + 20)
                world.addChild(tree)
                trees.append(tree)
            }
        }
        if settings.plow, plow == nil {
            let plow = Plow()
            world.addChild(plow)
            self.plow = plow
        } else if !settings.plow, let plow {
            if case .plow = held { held = nil }
            plow.removeFromParent()
            self.plow = nil
        }
        while ropeways.count > settings.cableCars {
            if case .hook = held { held = nil }
            ropeways.removeLast().removeFromParent()
        }
        while ropeways.count < settings.cableCars {
            // Each rope gets its own pulley: the first in the usual spot, the rest spread out either side of it.
            let slot = [0, -1, 1, -2, 2].first { slot in !ropeways.contains { $0.slot == slot } } ?? 0
            let ropeway = Ropeway(anchor: CGPoint(x: notchAnchor.x + CGFloat(slot) * 34, y: notchAnchor.y))
            ropeway.slot = slot
            world.addChild(ropeway)
            ropeways.append(ropeway)
        }
        // The setting counts the strings tied to the sides; ones carrying on from the top of the screen come and go with use.
        var sides = lightStrings.filter { $0.slot != nil }
        while sides.count > settings.lightStrings, let last = sides.popLast() {
            if case .lights(let string) = held, string === last { held = nil }
            lightStrings.removeAll { $0 === last }
            last.removeFromParent()
        }
        while sides.count < settings.lightStrings {
            // Left side first, then right, working down the screen.
            let slot = (0..<6).first { slot in !sides.contains { $0.slot == slot } } ?? sides.count
            let string = LightString(anchor: .side(slot: slot), sceneSize: size, top: size.height - topInset)
            world.addChild(string)
            lightStrings.append(string)
            sides.append(string)
        }
        // Switched on just now: the first sleigh comes by within a few seconds, so you can see it's working.
        if settings.santa, !santaWasOn, lastTime > 0 { nextSanta = lastTime + 3 }
        santaWasOn = settings.santa
    }

    /// Knocks the settled snow loose (all of it, or just what's on windows and widgets).
    func shakeOff(windowsOnly: Bool = false) {
        for p in platforms where !(windowsOnly && p.id == Self.groundID) {
            for spot in p.pile.shed(1, maxPoints: 40) {
                snowfall.addClump(
                    at: CGPoint(x: p.left + spot.x, y: p.top + spot.y),
                    velocity: CGVector(dx: .random(in: -30...30), dy: .random(in: -20...60)))
            }
        }
        // Piles on windows that aren't showing right now.
        for pile in piles.values { _ = pile.shed(1, maxPoints: 0) }
    }

    // MARK: Frame loop

    override func update(_ currentTime: TimeInterval) {
        let dt = CGFloat(min(max(currentTime - lastTime, 1.0 / 240), 1.0 / 20))
        lastTime = currentTime
        let pressed = NSEvent.pressedMouseButtons & 1 == 1

        // A held mouse button usually means a window is being dragged, so follow closely.
        if pressed || currentTime < lookOftenUntil || currentTime - lastLook >= 0.1 { look(at: currentTime) }

        let location = NSEvent.mouseLocation
        let previous = mouse
        mouse = CGPoint(x: location.x - screen.frame.minX, y: location.y - screen.frame.minY)
        mouseVelocity = CGVector(dx: (mouse.x - previous.x) / dt, dy: (mouse.y - previous.y) / dt)

        // In Mission Control only the falling snow stays: the windows it sat on are thumbnails now.
        let hidden = missionControl || currentTime < calmUntil
        world.alpha += ((hidden ? 0 : 1) - world.alpha) * min(1, dt * 12)
        world.isHidden = world.alpha < 0.02
        underWorld.alpha = world.alpha
        underWorld.isHidden = world.isHidden

        if held != nil, !pressed || hidden { release() }
        // Only a moving cursor ploughs; a parked one would keep re-kicking the snow that falls back on it.
        if !hidden, held == nil, mouse != previous { brush(from: previous, to: mouse) }

        snowfall.update(dt: dt, time: currentTime, platforms: platforms, settle: !hidden)

        for tree in trees {
            guard
                let (platform, x) = tree.update(dt: dt, platforms: platforms, floor: floorHeight(at:), sceneWidth: size.width, mouse: mouse),
                platform.pile.surface(at: x) > 2
            else { continue }
            // Landing in snow flattens it and throws some up.
            platform.pile.press(at: x, halfWidth: 20, to: 0.45)
            for _ in 0..<10 {
                snowfall.addClump(
                    at: CGPoint(x: platform.left + x + .random(in: -20...20), y: platform.top + 4),
                    velocity: CGVector(dx: .random(in: -140...140), dy: .random(in: 60...190)))
            }
        }
        for ropeway in ropeways { ropeway.update(dt: dt, time: currentTime, platforms: platforms, mouse: mouse) }
        for string in lightStrings { string.update(dt: dt, time: currentTime, platforms: platforms, mouse: mouse) }
        if let plow {
            if let spot = Self.parkingSpot() {
                // Centre the truck's body (not its sprite, which has the blade sticking out) on the spot.
                plow.home = CGPoint(
                    x: spot.x - screen.frame.minX - Plow.visualMiddle.x, y: spot.y - screen.frame.minY - Plow.visualMiddle.y)
            }
            plow.menuBarShown = menuBarShown(dt: dt, now: currentTime)
            plow.update(dt: dt, time: currentTime, platforms: platforms, snowfall: snowfall, mouse: mouse)
            // Clearing the bottom of the screen, it drives behind the Dock like the snow it's clearing.
            let layer = plow.workingOn == Self.groundID ? underWorld : world
            if plow.parent !== layer {
                plow.removeFromParent()
                layer.addChild(plow)
            }
        }
        flySanta(dt: dt, now: currentTime, hidden: hidden)

        let lights = Settings.shared.lights
        for pile in piles.values { pile.updateLights(enabled: lights) }

        let scale = screen.backingScaleFactor
        for pile in piles.values { pile.update(now: currentTime, scale: scale) }
        ground?.update(now: currentTime, scale: scale)

        // The overlay lets clicks through to the apps below, except while the cursor is on something you can grab
        // (or click, or right-click away).
        let wantsMouse = !hidden && (held != nil || (!pressed && (target(at: mouse) != nil || decoration(at: mouse) != nil)))
        if let window = view?.window, window.ignoresMouseEvents == wantsMouse { window.ignoresMouseEvents = !wantsMouse }
    }

    /// Whether the menu bar is showing on this screen. A full-screen app (or the "always hide" setting) tucks it away
    /// until the pointer rests at the top of the screen.
    private func menuBarShown(dt: CGFloat, now: TimeInterval) -> Bool {
        if now - lastPrefsRead > 2 {
            lastPrefsRead = now
            menuBarAutohides = UserDefaults.standard.bool(forKey: "_HIHideMenuBar")
        }
        guard fullScreen || menuBarAutohides else {
            pointerAtTopFor = 0
            return true
        }
        let atTop = mouse.y >= size.height - topInset - (pointerAtTopFor > 0.25 ? 6 : 0) && mouse.x >= 0 && mouse.x <= size.width
        pointerAtTopFor = atTop ? pointerAtTopFor + dt : 0
        return pointerAtTopFor > 0.25
    }

    /// Every so often (not often) Santa crosses the main screen.
    private func flySanta(dt: CGFloat, now: TimeInterval, hidden: Bool) {
        if let santa, !santa.update(dt: dt, time: now) {
            santa.trail.removeFromParent()
            santa.removeFromParent()
            self.santa = nil
        }
        guard isMain, Settings.shared.santa else { return }
        // The first one four to eight minutes after launch.
        if nextSanta == 0 { nextSanta = now + .random(in: 240...480) }
        // Not while Mission Control or a full-screen app (a film, a presentation) is up; he'll come a little later.
        guard santa == nil, now >= nextSanta, !hidden, !fullScreen else { return }
        nextSanta = now + .random(in: 420...900)
        let sleigh = SantaSleigh(sceneSize: size)
        world.addChild(sleigh)
        santa = sleigh
    }

    // MARK: Windows

    /// Reads where every window and widget is and works out which parts of each top edge can be seen.
    private func look(at now: TimeInterval) {
        let snapshot = WindowTracker.snapshot(at: now)
        if snapshot.missionControl != missionControl {
            missionControl = snapshot.missionControl
            if !missionControl { calmUntil = now + 0.5 }
        }
        // Mission Control lays every window out as a thumbnail. Leave the snow as it was until it closes.
        if missionControl {
            lastLook = now
            return
        }
        let calm = now < calmUntil
        let elapsed = CGFloat(max(now - lastLook, 1.0 / 120))
        lastLook = now
        let settings = Settings.shared
        let windows = settings.widgets ? snapshot.windows : snapshot.windows.filter { $0.kind == .window }
        fullScreen = !snapshot.dockShown && windows.contains { $0.kind == .window && fillsScreen($0.frame) }
        let ceiling = size.height - topInset - 2
        var found: [Platform] = []
        var seen = Set<CGWindowID>()

        for (i, w) in windows.enumerated() {
            let left = w.frame.minX - quartzOrigin.x
            let top = size.height - (w.frame.minY - quartzOrigin.y)
            // Must be on this screen, and not tucked under the menu bar where snow has nowhere to sit.
            guard left < size.width, left + w.frame.width > 0, top > 20, top < ceiling else { continue }

            var segments = [max(0, -left)...min(w.frame.width, size.width - left)]
            // Windows in front hide the part of this edge they overlap. Checked just above the edge, where the snow lies.
            let probe = w.frame.minY - 3
            for front in windows[..<i] {
                let f = front.frame
                guard f.minY < probe, f.maxY > probe, f.maxX > w.frame.minX, f.minX < w.frame.maxX else { continue }
                segments = cut((f.minX - w.frame.minX)...(f.maxX - w.frame.minX), from: segments)
                if segments.isEmpty { break }
            }

            let pile: SnowPile
            if let existing = piles[w.id] {
                pile = existing
                // Made narrower: the snow on the part that's gone falls off the end.
                for spot in pile.resize(to: w.frame.width) where !calm {
                    snowfall.addClump(
                        at: CGPoint(x: left + spot.x, y: top + spot.y),
                        velocity: CGVector(dx: .random(in: -20...40), dy: .random(in: -10...40)))
                }
            } else {
                pile = SnowPile(style: w.kind == .widget ? .widget : .window)
                pile.resize(to: w.frame.width)
                // Windows already open at launch start with some snow; later ones collect their own.
                if firstLook, settings.piles, Self.prefills { pile.prefill(.random(in: 0.5...0.85)) }
                piles[w.id] = pile
                world.addChild(pile.node)
                world.addChild(pile.lights)
            }

            let origin = CGPoint(x: left, y: top)
            if let old = pile.origin, old != origin {
                lookOftenUntil = now + 0.5
                // A fast-moving window leaves some of its snow behind in the air (but not while windows fly back from Mission Control).
                let speed = hypot(origin.x - old.x, origin.y - old.y) / elapsed
                if speed > 300, !calm {
                    let carry = CGVector(dx: (origin.x - old.x) / elapsed * 0.2, dy: (origin.y - old.y) / elapsed * 0.2)
                    for spot in pile.shed(min(0.4, (speed - 300) / 3500), maxPoints: 10) {
                        snowfall.addClump(
                            at: CGPoint(x: old.x + spot.x, y: old.y + spot.y),
                            velocity: CGVector(dx: carry.dx + .random(in: -25...25), dy: carry.dy + .random(in: -10...40)))
                    }
                }
            }
            pile.origin = origin
            pile.node.position = origin
            pile.lights.position = origin
            pile.segments = segments
            pile.onScreen = true
            seen.insert(w.id)
            vanished[w.id] = nil
            found.append(Platform(id: w.id, left: left, top: top, width: w.frame.width, pile: pile, collects: settings.piles))
        }

        dockSpan = nil
        snowfall.dock = nil
        if let dock = Dock.frame(at: now), dock.intersects(screen.frame) {
            dockSpan = (dock.minX - screen.frame.minX - 6)...(dock.maxX - screen.frame.minX + 6)
            // Snow falling past the Dock's top goes behind it, a little below the edge so you see it reach the Dock.
            snowfall.dock = (span: dock.minX - screen.frame.minX...dock.maxX - screen.frame.minX, top: dock.maxY - screen.frame.minY - 3)
        }
        if let ground { found.append(layOutGround(ground, windows: windows, dockShown: snapshot.dockShown)) }

        // Gone from view: note when. Until it's clear whether it closed or the whole Space changed, the snow stays put.
        for (id, pile) in piles where !seen.contains(id) {
            if pile.onScreen, pile.origin != nil, !calm, vanished[id] == nil {
                vanished[id] = now
            } else if vanished[id] == nil {
                pile.onScreen = false
                pile.origin = nil
            }
        }
        for (id, at) in vanished {
            guard let pile = piles[id] else {
                vanished[id] = nil
                continue
            }
            let spaceChanged = spaceChangedAt > at - 0.3
            guard spaceChanged || now - at > 0.2 else { continue }
            vanished[id] = nil
            // Closed, minimised or hidden: the snow it was holding up falls. (A Space change keeps it for later.)
            if !spaceChanged, !calm, let origin = pile.origin {
                for spot in pile.shed(1, maxPoints: 90) {
                    snowfall.addClump(
                        at: CGPoint(x: origin.x + spot.x, y: origin.y + spot.y),
                        velocity: CGVector(dx: .random(in: -30...30), dy: .random(in: -20...35)),
                        radius: .random(in: 1.5...3.8))
                }
            }
            pile.onScreen = false
            pile.origin = nil
        }
        // Closed for good: forget it.
        if now - lastPrune > 20 {
            lastPrune = now
            for (id, pile) in piles where !seen.contains(id) && !WindowTracker.exists(id) {
                pile.node.removeFromParent()
                pile.lights.removeFromParent()
                piles[id] = nil
            }
        }
        platforms = found
        firstLook = false
    }

    /// The drift along the bottom of the screen, right across (it lies under the Dock), hidden behind windows that reach down to it.
    private func layOutGround(_ ground: SnowPile, windows: [WindowInfo], dockShown: Bool) -> Platform {
        var segments = [0...size.width]
        let probe = quartzOrigin.y + size.height - 3
        for w in windows where w.kind == .window && w.frame.minY < probe && w.frame.maxY > probe {
            segments = cut((w.frame.minX - quartzOrigin.x)...(w.frame.maxX - quartzOrigin.x), from: segments)
        }
        // Behind the Dock the drift hides nothing (the Dock already covers that strip), so it lies there even over
        // a window that reaches the bottom, showing through the Dock's glass.
        // Where it ends over a window, it thins out to nothing inside the Dock's rounded ends, out of sight.
        var thinsAt: [CGFloat] = []
        if dockShown, let dockSpan, dockSpan.upperBound - dockSpan.lowerBound > 60, dockSpan.upperBound > 0, dockSpan.lowerBound < size.width {
            let ends = (dockSpan.lowerBound + 16)...(dockSpan.upperBound - 16)
            var under = max(0, ends.lowerBound)...min(size.width, ends.upperBound)
            var rest: [ClosedRange<CGFloat>] = []
            for s in segments {
                if s.upperBound < under.lowerBound || s.lowerBound > under.upperBound {
                    rest.append(s)
                } else {
                    under = min(s.lowerBound, under.lowerBound)...max(s.upperBound, under.upperBound)
                }
            }
            segments = (rest + [under]).sorted { $0.lowerBound < $1.lowerBound }
            if under.lowerBound == ends.lowerBound { thinsAt.append(under.lowerBound) }
            if under.upperBound == ends.upperBound { thinsAt.append(under.upperBound) }
        }
        ground.thinsAt = thinsAt
        ground.resize(to: size.width)
        ground.segments = segments
        ground.origin = .zero
        ground.node.position = .zero
        ground.onScreen = true
        return Platform(id: Self.groundID, left: 0, top: 0, width: size.width, pile: ground)
    }

    /// True when a window fills the whole screen below the menu bar, as a full-screen app does.
    private func fillsScreen(_ f: CGRect) -> Bool {
        f.minX <= quartzOrigin.x + 1 && f.maxX >= quartzOrigin.x + size.width - 1
            && f.minY <= quartzOrigin.y + topInset + 1 && f.maxY >= quartzOrigin.y + size.height - 1
    }

    /// Removes `hole` from a list of stretches, dropping leftovers too short to bother with.
    private func cut(_ hole: ClosedRange<CGFloat>, from segments: [ClosedRange<CGFloat>]) -> [ClosedRange<CGFloat>] {
        var out: [ClosedRange<CGFloat>] = []
        for s in segments {
            if hole.upperBound <= s.lowerBound || hole.lowerBound >= s.upperBound {
                out.append(s)
                continue
            }
            if hole.lowerBound - s.lowerBound >= 10 { out.append(s.lowerBound...hole.lowerBound) }
            if s.upperBound - hole.upperBound >= 10 { out.append(hole.upperBound...s.upperBound) }
        }
        return out
    }

    // MARK: Mouse

    /// The cursor ploughs through any snow it crosses. Fast moves are walked in small steps so they don't skip over a pile.
    private func brush(from a: CGPoint, to b: CGPoint) {
        let radius: CGFloat = 13
        let steps = max(1, min(8, Int((hypot(b.x - a.x, b.y - a.y) / 10).rounded(.up))))
        let direction = abs(mouseVelocity.dx) > 30 ? (mouseVelocity.dx > 0 ? 1 : -1) : 0
        let fling = CGVector(dx: max(-900, min(900, mouseVelocity.dx)) * 0.3, dy: max(0, min(900, mouseVelocity.dy)) * 0.25)
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            for platform in platforms {
                let x = p.x - platform.left, y = p.y - platform.top
                guard x > -radius, x < platform.width + radius, y > -8, y < platform.pile.heapHeight + radius,
                    platform.pile.isVisible(min(max(x, 0), platform.width))
                else { continue }
                for spot in platform.pile.brush(x: x, y: y, radius: radius, direction: direction) {
                    snowfall.addClump(
                        at: CGPoint(x: platform.left + spot.x, y: platform.top + spot.y),
                        velocity: CGVector(dx: fling.dx + .random(in: -45...45), dy: fling.dy + .random(in: 20...120)))
                }
            }
        }
    }

    /// The thing under the cursor that can be picked up, if any.
    private func target(at point: CGPoint) -> Held? {
        guard world.alpha > 0.5 else { return nil }
        // Not while it's behind the Dock: the click belongs to the Dock there.
        if let plow, plow.isUnder(point), !(plow.parent === underWorld && isOnDock(point)) { return .plow }
        if let ropeway = ropeways.last(where: { $0.hookIsUnder(point) }) { return .hook(ropeway) }
        if let string = lightStrings.last(where: { $0.hookIsUnder(point) }) { return .lights(string) }
        if let tree = trees.last(where: { $0.alpha > 0.5 && $0.isUnder(point) }) { return .tree(tree) }
        return nil
    }

    /// The decoration under the cursor, by any part of it: a tree, a cable car's cabin or hook, a string's bulbs or hook.
    private func decoration(at p: CGPoint) -> SKNode? {
        guard world.alpha > 0.5 else { return nil }
        if let ropeway = ropeways.last(where: { $0.hookIsUnder(p) || $0.carIsUnder(p) }) { return ropeway }
        if let string = lightStrings.last(where: { $0.hookIsUnder(p) || $0.bulbIsUnder(p) }) { return string }
        if let tree = trees.last(where: { $0.alpha > 0.5 && $0.isUnder(p) }) { return tree }
        return nil
    }

    /// Every decoration that's out, named (and numbered where the names repeat) so they can be told apart in a menu.
    var decorations: [(title: String, node: SKNode)] {
        func place(_ x: CGFloat) -> String { x < size.width / 3 ? "left" : x > size.width * 2 / 3 ? "right" : "middle" }
        var list: [(String, SKNode)] = []
        for tree in trees { list.append(("\(tree.kind.name) (\(place(tree.position.x)))", tree)) }
        for ropeway in ropeways {
            list.append(("Cable Car (\(ropeway.isHooked ? "to a window, \(place(ropeway.hookX))" : "hanging loose"))", ropeway))
        }
        for string in lightStrings {
            let from: String
            if let slot = string.slot {
                from = slot % 2 == 0 ? "left side" : "right side"
            } else {
                from = "from the top, \(place(string.topX ?? 0))"
            }
            list.append(("Hanging Lights (\(from))", string))
        }
        var total: [String: Int] = [:]
        for (title, _) in list { total[title, default: 0] += 1 }
        var seen: [String: Int] = [:]
        return list.map { title, node in
            guard total[title, default: 0] > 1 else { return (title, node) }
            seen[title, default: 0] += 1
            return ("\(title) \(seen[title]!)", node)
        }
    }

    /// Takes one decoration away with a little poof, and updates the saved counts to match.
    func remove(_ node: SKNode) {
        if let tree = node as? TreeNode, let index = trees.firstIndex(where: { $0 === tree }) {
            if case .tree(let heldTree) = held, heldTree === tree { held = nil }
            trees.remove(at: index)
            tree.run(.sequence([.group([.scale(to: 0.1, duration: 0.18), .fadeOut(withDuration: 0.18)]), .removeFromParent()]))
            Settings.shared.setCount(trees.filter { $0.kind == tree.kind }.count, of: tree.kind)
        } else if let ropeway = node as? Ropeway, let index = ropeways.firstIndex(where: { $0 === ropeway }) {
            if case .hook(let heldRopeway) = held, heldRopeway === ropeway { held = nil }
            ropeways.remove(at: index)
            ropeway.run(.sequence([.fadeOut(withDuration: 0.2), .removeFromParent()]))
            Settings.shared.cableCars = ropeways.count
        } else if let string = node as? LightString, let index = lightStrings.firstIndex(where: { $0 === string }) {
            if case .lights(let heldString) = held, heldString === string { held = nil }
            lightStrings.remove(at: index)
            string.run(.sequence([.fadeOut(withDuration: 0.2), .removeFromParent()]))
            if string.slot != nil { Settings.shared.lightStrings = lightStrings.filter { $0.slot != nil }.count }
        }
    }

    /// Takes away the strings that carry on from the top of the screen (the ones on the sides go with the setting).
    func removeContinuedLights() {
        for string in lightStrings where string.slot == nil { remove(string) }
    }

    /// Called by the overlay view. Only the press arrives as an event; the drag and release are read each frame.
    func mouseDown(at point: CGPoint) {
        guard held == nil else { return }
        guard let target = target(at: point) else {
            // A click on a bulb changes how that string lights up.
            lightStrings.last(where: { $0.bulbIsUnder(point) })?.cycleLights()
            return
        }
        held = target
        heldSince = lastTime
        heldFrom = point
        switch target {
        case .tree(let tree): tree.pickUp(at: point)
        case .hook(let ropeway): ropeway.pickUp()
        case .lights(let string): string.pickUp()
        case .plow: plow?.pickUp()
        }
    }

    /// Right-click any part of a decoration (a tree, a cable car or its hook, a string's bulbs or hook) to take it away.
    func rightMouseDown(at point: CGPoint) {
        guard held == nil, let node = decoration(at: point) else { return }
        remove(node)
    }

    private func release() {
        guard let held else { return }
        self.held = nil
        switch held {
        case .tree(let tree):
            tree.letGo(clicked: lastTime - heldSince < 0.3 && hypot(mouse.x - heldFrom.x, mouse.y - heldFrom.y) < 5)
        case .hook(let ropeway):
            ropeway.letGo(platforms: platforms)
        case .lights(let string):
            string.letGo(platforms: platforms)
            carryOn(from: string)
        case .plow:
            plow?.letGo(platforms: platforms)
        }
    }

    /// Fastened to the top of the screen, the lights carry on: a new string hangs from that spot, ready to be draped further.
    private func carryOn(from string: LightString) {
        guard case .top(let x)? = string.home, lightStrings.count < 40,
            !lightStrings.contains(where: { abs(($0.topX ?? -100) - x) < 6 })
        else { return }
        let next = LightString(anchor: .top(x: x), sceneSize: size, top: size.height - topInset)
        next.alpha = 0
        next.run(.fadeIn(withDuration: 0.4))
        world.addChild(next)
        lightStrings.append(next)
    }

    // MARK: Debug

    #if DEBUG
        /// Hooks the rope onto a window, drapes the first string of lights along the top of the screen twice
        /// (leaving the third length dangling), and calls Santa, so they can be checked without a hand on the mouse.
        @objc func demo() {
            let usable = platforms.filter { $0.id != Self.groundID && $0.top < size.height - 100 && !$0.pile.segments.isEmpty }
            if let ropeway = ropeways.first, let p = usable.first,
                let widest = p.pile.segments.max(by: { $0.upperBound - $0.lowerBound < $1.upperBound - $1.lowerBound })
            {
                ropeway.attach(to: p, at: (widest.lowerBound + widest.upperBound) / 2 + 60)
            }
            if let first = lightStrings.first(where: { $0.slot == 0 }) {
                let y = size.height - topInset - 19
                hang(first, at: CGPoint(x: size.width * 0.17, y: y))
                if let second = lightStrings.last, second !== first { hang(second, at: CGPoint(x: size.width * 0.33, y: y)) }
            }
            if isMain, santa == nil {
                let sleigh = SantaSleigh(sceneSize: size)
                world.addChild(sleigh)
                santa = sleigh
            }
        }

        /// Drags a string's hook to `point` and lets go, as a hand on the mouse would.
        private func hang(_ string: LightString, at point: CGPoint) {
            string.pickUp()
            string.update(dt: 1, time: lastTime, platforms: platforms, mouse: point)
            string.letGo(platforms: platforms)
            carryOn(from: string)
        }

        /// Saves the overlay drawn over grey stand-ins for the real windows.
        /// (A real screenshot needs the Screen Recording permission, which this app never asks for.)
        func saveSnapshot(to path: String) {
            guard let view, let overlay = view.texture(from: self, crop: CGRect(origin: .zero, size: size))?.cgImage() else { return }
            let scale = screen.backingScaleFactor
            guard
                let c = CGContext(
                    data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return }
            c.scaleBy(x: scale, y: scale)
            c.setFillColor(Art.rgb(0.09, 0.12, 0.22))
            c.fill(CGRect(origin: .zero, size: size))
            for w in WindowTracker.snapshot(at: -2).windows.reversed() {
                let rect = CGRect(
                    x: w.frame.minX - quartzOrigin.x, y: size.height - (w.frame.maxY - quartzOrigin.y), width: w.frame.width,
                    height: w.frame.height)
                let corner: CGFloat = w.kind == .widget ? 19 : 11
                c.addPath(CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil))
                c.setFillColor(Art.rgb(0.23, 0.24, 0.28))
                c.setStrokeColor(Art.rgb(0.42, 0.43, 0.48))
                c.drawPath(using: .fillStroke)
            }
            // The window below the Dock, then the Dock in front of it (see-through, like its glass), then the overlay.
            if let underView = under.view, let underImage = underView.texture(from: under, crop: CGRect(origin: .zero, size: size))?.cgImage() {
                c.draw(underImage, in: CGRect(origin: .zero, size: size))
            }
            if let dockSpan {
                c.setFillColor(Art.rgb(0.42, 0.44, 0.50, 0.72))
                c.addPath(
                    CGPath(
                        roundedRect: CGRect(x: dockSpan.lowerBound + 6, y: 4, width: dockSpan.upperBound - dockSpan.lowerBound - 12, height: floorY - 6),
                        cornerWidth: 16, cornerHeight: 16, transform: nil))
                c.fillPath()
            }
            c.draw(overlay, in: CGRect(origin: .zero, size: size))
            guard let image = c.makeImage(),
                let out = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)
            else { return }
            CGImageDestinationAddImage(out, image, nil)
            CGImageDestinationFinalize(out)
        }
    #endif
}
