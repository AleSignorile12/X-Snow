import AppKit

enum SurfaceKind {
    /// An ordinary app window.
    case window
    /// The card of a desktop widget.
    case widget
}

struct WindowInfo {
    let id: CGWindowID
    /// Global Quartz coordinates: origin at the top-left of the main display, y grows downward.
    let frame: CGRect
    let kind: SurfaceKind
}

/// Reads where other apps' windows are. Positions and sizes need no permission (only window titles and pixels do).
enum WindowTracker {
    struct Snapshot {
        /// Windows and widget cards that snow can rest on, front to back.
        var windows: [WindowInfo] = []
        /// Mission Control (or App Exposé) is showing. Window frames are then where the thumbnails are, not the windows.
        var missionControl = false
        /// The Dock's window is up. It goes away while an app is full screen.
        var dockShown = true
    }

    /// Widget windows tile edge to edge; the visible card sits this far in from the window's edge.
    private static let widgetMargin: CGFloat = 9
    private static let ownPID = ProcessInfo.processInfo.processIdentifier
    private static let dockLevel = Int(CGWindowLevelForKey(.dockWindow))
    private static let menuBarLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
    /// Desktop widgets sit just above the desktop icons, well below ordinary windows.
    private static let widgetLevels = (Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)..<0
    private static var cache = Snapshot()
    private static var cacheTime: TimeInterval = -1

    /// What's on screen right now. Cached per frame so every screen's scene shares one query.
    static func snapshot(at time: TimeInterval) -> Snapshot {
        if time != cacheTime {
            cacheTime = time
            cache = query()
        }
        return cache
    }

    /// True while the window still exists, even if it is minimised or on another Space.
    static func exists(_ id: CGWindowID) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as NSArray? else { return false }
        return list.count > 0
    }

    private static func query() -> Snapshot {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as NSArray? else { return Snapshot() }
        let display = CGDisplayBounds(CGMainDisplayID())
        let screens = NSScreen.screens.map(\.frame.size)
        var snapshot = Snapshot(windows: [], missionControl: false, dockShown: false)
        snapshot.windows.reserveCapacity(list.count)
        for case let w as NSDictionary in list {
            guard let layer = w[kCGWindowLayer] as? Int,
                let pid = w[kCGWindowOwnerPID] as? pid_t, pid != ownPID,
                let id = w[kCGWindowNumber] as? CGWindowID,
                let bounds = w[kCGWindowBounds] as? NSDictionary,
                let frame = CGRect(dictionaryRepresentation: bounds),
                (w[kCGWindowAlpha] as? Double ?? 1) > 0.05
            else { continue }
            let owner = w[kCGWindowOwnerName] as? String ?? ""

            // Mission Control, App Exposé and Stage Manager are drawn by WindowManager (by the Dock on older systems).
            // Their highlight frames and title labels look like windows, but snow and lights don't belong on them.
            if owner == "WindowManager" || owner == "Dock" {
                if owner == "Dock", layer == dockLevel {
                    snapshot.dockShown = true
                } else if layer > 14, layer < menuBarLevel,
                    screens.contains(where: { frame.width >= $0.width * 0.9 && frame.height >= $0.height * 0.9 })
                {
                    snapshot.missionControl = true
                }
                continue
            }

            if (0...8).contains(layer) {
                // Layers 0–8 are normal windows and floating panels. Above that it's the Dock, menu bar and overlays.
                guard frame.width >= 80, frame.height >= 40 else { continue }
                // A floating panel that covers the whole display is some other app's see-through overlay, not a real window.
                if layer != 0, frame.width >= display.width * 0.95, frame.height >= display.height * 0.9 { continue }
                snapshot.windows.append(WindowInfo(id: id, frame: frame, kind: .window))
            } else if widgetLevels.contains(layer), owner.hasPrefix("Notification"), frame.width >= 100, frame.height >= 100 {
                let card = frame.insetBy(dx: widgetMargin, dy: widgetMargin)
                snapshot.windows.append(WindowInfo(id: id, frame: card, kind: .widget))
            }
        }
        return snapshot
    }
}
