import AppKit
import ApplicationServices

/// Where the Dock sits, so the snow along the bottom of the screen can stop at its ends.
///
/// With Accessibility allowed, the Dock reports its exact frame. Without it, the width is worked out from the
/// Dock's own settings (icon size and how many icons it shows), which lands within a few points.
enum Dock {
    private static var cached: CGRect?
    private static var lastRead: TimeInterval = -10
    private static var reading = false

    /// True once the user has let X-Snow use Accessibility, so the Dock can be measured exactly.
    static var canMeasure: Bool { AXIsProcessTrusted() }

    /// The Dock's frame in AppKit screen coordinates (origin at the main display's bottom-left, y up),
    /// or nil when it is hidden or on a side of the screen.
    static func frame(at now: TimeInterval) -> CGRect? {
        if now - lastRead > 1 { refresh(at: now) }
        return cached
    }

    /// Shows the system prompt that leads to the Accessibility setting.
    static func askToMeasure() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private static func refresh(at now: TimeInterval) {
        lastRead = now
        // The Dock leaves a strip at the bottom of the screen it is on. No strip: it is hidden or on a side.
        guard let screen = NSScreen.screens.first(where: { $0.visibleFrame.minY > $0.frame.minY + 1 }) else {
            cached = nil
            return
        }
        let height = screen.visibleFrame.minY - screen.frame.minY
        guard AXIsProcessTrusted(), !reading,
            let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
        else {
            if !reading { cached = estimate(on: screen, height: height) }
            return
        }
        // Accessibility calls can block for a moment, so they run off the main thread.
        reading = true
        let mainHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        Task { @MainActor in
            let measured = await Task.detached(priority: .utility) { measure(pid: pid) }.value
            reading = false
            if let q = measured {
                cached = CGRect(x: q.minX, y: mainHeight - q.maxY, width: q.width, height: q.height)
            } else {
                cached = estimate(on: screen, height: height)
            }
        }
    }

    /// Finder, the kept apps, any others running or recent, the folders, and the Trash, side by side.
    private static func estimate(on screen: NSScreen, height: CGFloat) -> CGRect {
        let domain = "com.apple.dock" as CFString
        CFPreferencesAppSynchronize(domain)
        func value(_ key: String) -> Any? { CFPreferencesCopyAppValue(key as CFString, domain) }
        func bundleID(_ tile: Any) -> String? {
            ((tile as? [String: Any])?["tile-data"] as? [String: Any])?["bundle-identifier"] as? String
        }
        let tile = CGFloat((value("tilesize") as? NSNumber)?.doubleValue ?? Double(max(16, height - 20)))
        let kept = value("persistent-apps") as? [Any] ?? []
        let folders = value("persistent-others") as? [Any] ?? []
        let showsRecents = (value("show-recents") as? NSNumber)?.boolValue ?? true
        let keptIDs = Set(kept.compactMap(bundleID))
        var extra = Set(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.compactMap(\.bundleIdentifier))
        if showsRecents { extra.formUnion((value("recent-apps") as? [Any] ?? []).compactMap(bundleID)) }
        extra.subtract(keptIDs)
        extra.remove("com.apple.finder")
        let icons = CGFloat(1 + kept.count + extra.count + folders.count + 1)
        let dividers: CGFloat = showsRecents && !extra.isEmpty ? 2 : 1
        let width = min(screen.frame.width, tile * (icons + dividers * 0.5 + 0.6))
        return CGRect(x: screen.frame.midX - width / 2, y: screen.frame.minY, width: width, height: height)
    }

    /// The Dock's icon strip, in global Quartz coordinates (top-left origin).
    nonisolated private static func measure(pid: pid_t) -> CGRect? {
        func attribute(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
            var v: CFTypeRef?
            return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
        }
        guard let strip = (attribute(AXUIElementCreateApplication(pid), kAXChildrenAttribute) as? [AXUIElement])?.first,
            let position = attribute(strip, kAXPositionAttribute), let size = attribute(strip, kAXSizeAttribute),
            CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &origin)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        // A tall, thin strip means the Dock is on a side; then the bottom of the screen is free anyway.
        guard extent.width > extent.height else { return nil }
        return CGRect(origin: origin, size: extent)
    }
}
