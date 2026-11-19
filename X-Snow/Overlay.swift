import SpriteKit

/// Two see-through windows covering a whole screen.
///
/// The main one floats above every app; clicks pass straight through it unless the scene says the cursor is on
/// something you can grab. The second sits just below the Dock and holds the snow lying along the bottom of the
/// screen, so the Dock stands in front of the drift (and its glass shows the snow through it).
final class Overlay {
    let scene: SnowScene
    private let panel: NSPanel
    private let underPanel: NSPanel

    init(screen: NSScreen, isMain: Bool) {
        // Non-activating: grabbing a tree doesn't steal focus from the app you're working in.
        panel = Self.makePanel(screen: screen)
        // Just above the menu bar and Dock, but below menus and notifications.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)

        underPanel = Self.makePanel(screen: screen)
        // Above app windows, just below the Dock.
        underPanel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) - 1)
        let underView = SKView(frame: CGRect(origin: .zero, size: screen.frame.size))
        underView.allowsTransparency = true
        underView.ignoresSiblingOrder = true
        underView.preferredFramesPerSecond = 60
        let under = SKScene(size: screen.frame.size)
        under.backgroundColor = .clear
        under.scaleMode = .resizeFill
        underView.presentScene(under)
        underPanel.contentView = underView
        underPanel.setFrame(screen.frame, display: true)
        underPanel.orderFrontRegardless()

        let view = View(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.allowsTransparency = true
        view.ignoresSiblingOrder = true
        view.preferredFramesPerSecond = 60
        scene = SnowScene(screen: screen, isMain: isMain, under: under)
        view.presentScene(scene)
        panel.contentView = view
        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()
    }

    func close() {
        panel.close()
        underPanel.close()
    }

    private static func makePanel(screen: NSScreen) -> NSPanel {
        let panel = Panel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        return panel
    }

    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private final class View: SKView {
        /// Take the very first click even though X-Snow is never the active app.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard let scene = scene as? SnowScene else { return }
            scene.mouseDown(at: event.location(in: scene))
        }

        override func rightMouseDown(with event: NSEvent) {
            guard let scene = scene as? SnowScene else { return }
            scene.rightMouseDown(at: event.location(in: scene))
        }
    }
}
