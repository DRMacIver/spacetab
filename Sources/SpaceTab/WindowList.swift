import AppKit
import SpaceTabCore

/// Builds the per-space window columns by combining SkyLight space/window
/// enumeration with public CGWindowList metadata.
enum WindowList {
    /// Last known title per window. Without Screen Recording permission,
    /// kCGWindowName is empty and AX can't see other-space windows — but a
    /// title seen while a window was reachable stays valid until revisited.
    private static var titleCache: [UInt32: String] = [:]

    static func snapshot() -> [SpaceColumn] {
        // CGWindowListCreateDescriptionFromArray returns nothing on modern
        // macOS, so fetch every window's description once and join by ID.
        let all = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID)
            as? [[String: Any]] ?? []
        var byID: [UInt32: [String: Any]] = [:]
        for d in all {
            if let id = (d[kCGWindowNumber as String] as? NSNumber)?.uint32Value {
                byID[id] = d
            }
        }
        return SkyLight.spaces().map { space in
            let entries = SkyLight.windows(onSpace: space.id).compactMap {
                entry(id: $0, desc: byID[$0])
            }
            // MRU first (tracked by FocusTracker); untracked windows keep
            // their z-order after them. Stable sort preserves ties.
            let ordered = entries.enumerated().sorted { a, b in
                let ta = FocusTracker.shared.lastFocus[a.element.id]
                let tb = FocusTracker.shared.lastFocus[b.element.id]
                switch (ta, tb) {
                case let (x?, y?): return x > y
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return a.offset < b.offset
                }
            }.map(\.element)
            return SpaceColumn(id: space.id, isCurrent: space.isCurrent, windows: ordered)
        }
    }

    private static func entry(id: UInt32, desc: [String: Any]?) -> WindowEntry? {
        guard let d = desc,
              let pid = (d[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
              (d[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
              // layer 0: normal windows only — skips panels, overlays, desktop
        else { return nil }
        let bounds = d[kCGWindowBounds as String] as? [String: NSNumber] ?? [:]
        guard (bounds["Width"]?.doubleValue ?? 0) >= 50,
              (bounds["Height"]?.doubleValue ?? 0) >= 50
        else { return nil }
        let appName = d[kCGWindowOwnerName as String] as? String ?? "?"
        // One AX lookup serves both the title fallback and the sheet check.
        let ax = AXBridge.axWindow(windowID: id, pid: pid)
        // kCGWindowName needs Screen Recording permission; fall back to AX.
        var title = d[kCGWindowName as String] as? String ?? ""
        if title.isEmpty, let ax {
            title = AXBridge.title(of: ax) ?? ""
        }
        if title.isEmpty {
            title = titleCache[id] ?? ""
        } else {
            titleCache[id] = title
        }
        let hasModal = ax.map(AXBridge.hasSheet) ?? false
        return WindowEntry(id: id, pid: pid, appName: appName, title: title,
                           hasModal: hasModal)
    }
}
