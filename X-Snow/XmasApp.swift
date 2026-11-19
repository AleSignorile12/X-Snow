import AppKit
import SpriteKit

/// A menu bar app: no Dock icon, no windows of its own, just the snowflake menu and a see-through overlay per screen.
@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var overlays: [Overlay] = []
    private var screenFrames: [CGRect] = []
    private var activity: NSObjectProtocol?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // X-Snow is never the frontmost app, and macOS slows background apps down. This keeps the snow smooth.
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Animating snow")

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        updateStatusIcon()
        SnowScene.parkingSpot = { [weak item] in
            guard let button = item?.button, let window = button.window else { return nil }
            // The item's window is wider than the button (it has padding), so measure the button itself.
            let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
            // Centred in the space right of the snowflake, and halfway down the menu bar.
            return CGPoint(x: (rect.minX + AppDelegate.flakeWidth + rect.maxX) / 2, y: window.frame.midY)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(updateStatusIcon), name: Settings.changed, object: nil)

        rebuildOverlays()
        NotificationCenter.default.addObserver(
            self, selector: #selector(rebuildOverlays), name: NSApplication.didChangeScreenParametersNotification, object: nil)

        #if DEBUG
            // `-snapshot <file.png> [-snapshotAfter <seconds>] [-demo YES]` saves a picture of the overlay for checking the artwork.
            let args = UserDefaults.standard
            if args.string(forKey: "snapshot") != nil {
                if args.bool(forKey: "demo") { perform(#selector(runDemo), with: nil, afterDelay: 1.5) }
                perform(#selector(saveSnapshot), with: nil, afterDelay: max(2, args.double(forKey: "snapshotAfter")))
            }
        #endif
    }

    /// One overlay per screen. Rebuilt only when a screen is added, removed or resized.
    @objc private func rebuildOverlays() {
        let frames = NSScreen.screens.map(\.frame)
        guard frames != screenFrames else { return }
        screenFrames = frames
        overlays.forEach { $0.close() }
        overlays = NSScreen.screens.enumerated().map { Overlay(screen: $1, isMain: $0 == 0) }
    }

    /// The snowflake's share of the menu bar item, at its left end.
    static let flakeWidth: CGFloat = 22
    /// The plow's parking space to the right of the snowflake (the truck is 40 points long).
    private static let plowSpace: CGFloat = 48

    /// With the plow on, the menu bar item is wider: snowflake on the left, an empty parking space for the plow on the right.
    @objc private func updateStatusIcon() {
        guard let item = statusItem, let flake = NSImage(systemSymbolName: "snowflake", accessibilityDescription: "X-Snow") else { return }
        guard Settings.shared.plow else {
            item.length = NSStatusItem.squareLength
            item.button?.image = flake
            return
        }
        // Exactly as wide as the item, so the button doesn't centre it and shift the snowflake.
        let width = Self.flakeWidth + Self.plowSpace
        let wide = NSImage(size: NSSize(width: width, height: 18), flipped: false) { _ in
            flake.draw(in: NSRect(x: 3, y: 1, width: 16, height: 16))
            return true
        }
        wide.isTemplate = true
        item.length = width
        item.button?.image = wide
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        let settings = Settings.shared
        menu.removeAllItems()

        let snowfall = NSMenuItem(title: "Snowfall", action: nil, keyEquivalent: "")
        let levels = NSMenu()
        for level in Intensity.allCases {
            let item = NSMenuItem(title: level.title, action: #selector(setIntensity(_:)), keyEquivalent: "")
            item.target = self
            item.tag = level.rawValue
            item.state = settings.intensity == level ? .on : .off
            levels.addItem(item)
        }
        snowfall.submenu = levels
        menu.addItem(snowfall)

        let wind = NSMenuItem(title: "Wind", action: nil, keyEquivalent: "")
        let strengths = NSMenu()
        for strength in Wind.allCases {
            let item = NSMenuItem(title: strength.title, action: #selector(setWind(_:)), keyEquivalent: "")
            item.target = self
            item.tag = strength.rawValue
            item.state = settings.wind == strength ? .on : .off
            strengths.addItem(item)
        }
        wind.submenu = strengths
        menu.addItem(wind)
        add("Snow Settles on Windows", #selector(togglePiles), to: menu).state = settings.piles ? .on : .off
        add("Snow Settles on Widgets", #selector(toggleWidgets), to: menu).state = settings.widgets ? .on : .off
        add("Snow Piles Up at the Bottom", #selector(toggleGround), to: menu).state = settings.ground ? .on : .off
        if settings.ground, !Dock.canMeasure {
            let fit = add("Fit the Bottom Snow to the Dock\u{2026}", #selector(measureDock), to: menu)
            fit.toolTip = "Lets X-Snow read the Dock's exact size (Accessibility), so the snow stops right at its ends."
        }
        add("Shake Off the Snow", #selector(shakeOff), to: menu)
        menu.addItem(.separator())
        for kind in PropKind.allCases {
            add("Add \(kind.title)", #selector(addProp(_:)), to: menu).representedObject = kind.rawValue
        }
        add("Add a Cable Car", #selector(addCableCar), to: menu)
        add("Add Hanging Lights", #selector(addLightString), to: menu)
        // Decorations live on the main screen's overlay.
        let placed = overlays.first?.scene.decorations ?? []
        if !placed.isEmpty {
            let remove = NSMenuItem(title: "Remove a Decoration", action: nil, keyEquivalent: "")
            let list = NSMenu()
            for (title, node) in placed {
                add(title, #selector(removeOne(_:)), to: list).representedObject = node
            }
            list.addItem(.separator())
            add("All Decorations", #selector(removeProps), to: list)
            let tip = NSMenuItem(title: "Tip: right-click one on screen to remove it", action: nil, keyEquivalent: "")
            tip.isEnabled = false
            list.addItem(tip)
            remove.submenu = list
            menu.addItem(remove)
        }
        menu.addItem(.separator())
        add("Snow Plow in Menu Bar", #selector(togglePlow), to: menu).state = settings.plow ? .on : .off
        add("Lights on Windows", #selector(toggleLights), to: menu).state = settings.lights ? .on : .off
        add("Santa Flies By Now and Then", #selector(toggleSanta), to: menu).state = settings.santa ? .on : .off
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit X-Snow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @discardableResult
    private func add(_ title: String, _ action: Selector, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    @objc private func setWind(_ sender: NSMenuItem) {
        Settings.shared.wind = Wind(rawValue: sender.tag) ?? .off
    }

    @objc private func setIntensity(_ sender: NSMenuItem) {
        Settings.shared.intensity = Intensity(rawValue: sender.tag) ?? .medium
    }

    @objc private func togglePiles() { Settings.shared.piles.toggle() }
    @objc private func toggleWidgets() { Settings.shared.widgets.toggle() }
    @objc private func toggleGround() { Settings.shared.ground.toggle() }
    @objc private func measureDock() { Dock.askToMeasure() }
    @objc private func shakeOff() { overlays.forEach { $0.scene.shakeOff() } }
    @objc private func addProp(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String, let kind = PropKind(rawValue: key) else { return }
        Settings.shared.setCount(Settings.shared.count(of: kind) + 1, of: kind)
    }

    @objc private func removeOne(_ sender: NSMenuItem) {
        guard let node = sender.representedObject as? SKNode else { return }
        overlays.first?.scene.remove(node)
    }

    @objc private func removeProps() {
        PropKind.allCases.forEach { Settings.shared.setCount(0, of: $0) }
        Settings.shared.cableCars = 0
        Settings.shared.lightStrings = 0
        overlays.forEach { $0.scene.removeContinuedLights() }
    }
    @objc private func toggleLights() { Settings.shared.lights.toggle() }
    @objc private func togglePlow() { Settings.shared.plow.toggle() }
    @objc private func addCableCar() { Settings.shared.cableCars += 1 }
    @objc private func addLightString() { Settings.shared.lightStrings += 1 }
    @objc private func toggleSanta() { Settings.shared.santa.toggle() }

    #if DEBUG
        @objc private func runDemo() { overlays.first?.scene.demo() }

        @objc private func saveSnapshot() {
            guard let path = UserDefaults.standard.string(forKey: "snapshot") else { return }
            overlays.first?.scene.saveSnapshot(to: path)
        }
    #endif
}
