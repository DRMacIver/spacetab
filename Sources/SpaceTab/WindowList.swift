import AppKit
import SpaceTabCore

/// Builds the per-space window columns by combining SkyLight space/window
/// enumeration with public CGWindowList metadata.
enum WindowList {
    /// Last known title per window. Without Screen Recording permission,
    /// kCGWindowName is empty and AX can't see other-space windows — but a
    /// title seen while a window was reachable stays valid until revisited.
    /// Backed by TitleStore so titles survive a SpaceTab restart.
    private static var titleCache: [UInt32: TitleStore.Entry] = TitleStore.load()
    private static var cacheDirty = false

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
        let columns = SkyLight.spaces().map { space in
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
        // Closed windows won't come back; drop them and persist changes.
        let live = Set(byID.keys)
        let pruned = titleCache.filter { live.contains($0.key) }
        if pruned.count != titleCache.count {
            titleCache = pruned
            cacheDirty = true
        }
        if cacheDirty {
            TitleStore.save(titleCache)
            cacheDirty = false
        }
        return columns
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
            // Trust the cache only while the window still belongs to the
            // same app — window IDs get recycled across login sessions.
            if let cached = titleCache[id], cached.app == appName {
                title = cached.title
            }
        } else {
            let entry = TitleStore.Entry(app: appName, title: title)
            if titleCache[id] != entry {
                titleCache[id] = entry
                cacheDirty = true
            }
        }
        let hasModal = ax.map(AXBridge.hasSheet) ?? false
        return WindowEntry(id: id, pid: pid, appName: appName, title: title,
                           hasModal: hasModal)
    }
}
