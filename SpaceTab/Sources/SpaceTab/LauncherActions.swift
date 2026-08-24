import AppKit
import SpaceTabCore

/// Executes launcher selections: focus a window, or open a new window of an
/// app in the current space.
enum LauncherActions {
    private static let noNewWindowKey = "appsWithoutNewWindowSupport"

    private static var noNewWindowApps: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: noNewWindowKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue).sorted(), forKey: noNewWindowKey) }
    }

    static func perform(_ result: LauncherResult) {
        switch result {
        case .window(let w):
            WindowFocus.focus(windowID: w.window.id, pid: w.window.pid,
                              spaceID: w.spaceID)
        case .app(let app):
            openNewWindow(of: app)
        }
    }

    private static func openNewWindow(of app: LauncherApp) {
        guard let pid = app.pid else {
            // Not running: launching opens on the current space.
            if let path = app.path {
                NSWorkspace.shared.openApplication(
                    at: URL(fileURLWithPath: path),
                    configuration: NSWorkspace.OpenConfiguration())
            }
            return
        }
        // Remembered as unable to open new windows: switch immediately.
        if noNewWindowApps.contains(app.bundleID) {
            switchToExistingWindow(of: pid)
            return
        }
        // Probe: post Cmd-N directly to the process (without activating it
        // first, so macOS can't yank us to the app's space) and watch for a
        // new window to appear on this space.
        let before = windowIDs(of: pid)
        postCmdN(to: pid)
        pollForNewWindow(of: app, pid: pid, before: before, attempt: 0)
    }

    private static func pollForNewWindow(of app: LauncherApp, pid: pid_t,
                                         before: Set<UInt32>, attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let fresh = windowIDs(of: pid).subtracting(before)
            if let newWindow = fresh.first {
                WindowFocus.focus(
                    windowID: newWindow, pid: pid,
                    spaceID: SkyLight.getActiveSpace(SkyLight.connection))
                return
            }
            if attempt < 4 {
                pollForNewWindow(of: app, pid: pid, before: before, attempt: attempt + 1)
            } else {
                NSLog("SpaceTab: \(app.name) ignored Cmd-N; remembering and switching")
                noNewWindowApps.insert(app.bundleID)
                switchToExistingWindow(of: pid)
            }
        }
    }

    private static func switchToExistingWindow(of pid: pid_t) {
        // Most recently used window of the app, from the per-space snapshot.
        var best: (window: WindowEntry, spaceID: UInt64, date: Date)?
        for column in WindowList.snapshot() {
            for w in column.windows where w.pid == pid {
                let date = FocusTracker.shared.lastFocus[w.id] ?? .distantPast
                if best == nil || date > best!.date {
                    best = (w, column.id, date)
                }
            }
        }
        if let best {
            WindowFocus.focus(windowID: best.window.id, pid: pid, spaceID: best.spaceID)
        } else {
            // No windows anywhere: just activate the app.
            NSRunningApplication(processIdentifier: pid)?
                .activate(options: [.activateIgnoringOtherApps])
        }
    }

    private static func windowIDs(of pid: pid_t) -> Set<UInt32> {
        let all = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID)
            as? [[String: Any]] ?? []
        var ids = Set<UInt32>()
        for d in all {
            guard (d[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (d[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let id = (d[kCGWindowNumber as String] as? NSNumber)?.uint32Value
            else { continue }
            let bounds = d[kCGWindowBounds as String] as? [String: NSNumber] ?? [:]
            guard (bounds["Width"]?.doubleValue ?? 0) >= 50,
                  (bounds["Height"]?.doubleValue ?? 0) >= 50 else { continue }
            ids.insert(id)
        }
        return ids
    }

    private static func postCmdN(to pid: pid_t) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 45, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 45, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.postToPid(pid)
        up?.postToPid(pid)
    }
}
