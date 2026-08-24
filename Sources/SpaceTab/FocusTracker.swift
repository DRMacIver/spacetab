import AppKit
import ApplicationServices

/// Tracks when each window was last focused, via one AXObserver per running
/// app. Nothing in macOS exposes MRU order, so we build it ourselves; windows
/// never focused while SpaceTab runs simply keep their z-order.
final class FocusTracker {
    static let shared = FocusTracker()
    private(set) var lastFocus: [UInt32: Date] = [:]
    private(set) var appLastUsed: [String: Date] = [:]  // by bundle ID
    private var observers: [pid_t: AXObserver] = [:]

    func start() {
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular {
            watch(pid: app.processIdentifier)
        }
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                       object: nil, queue: .main) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication, app.activationPolicy == .regular {
                self?.watch(pid: app.processIdentifier)
            }
        }
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                       object: nil, queue: .main) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication {
                self?.stampFocusedWindow(pid: app.processIdentifier)
                if let id = app.bundleIdentifier {
                    self?.appLastUsed[id] = Date()
                }
            }
        }
        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                       object: nil, queue: .main) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication {
                self?.observers.removeValue(forKey: app.processIdentifier)
            }
        }
        // Seed: current frontmost window is by definition most recent.
        if let front = NSWorkspace.shared.frontmostApplication {
            stampFocusedWindow(pid: front.processIdentifier)
        }
    }

    private func watch(pid: pid_t) {
        guard observers[pid] == nil else { return }
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, element, _, refcon in
            let tracker = Unmanaged<FocusTracker>.fromOpaque(refcon!).takeUnretainedValue()
            var wid: UInt32 = 0
            if _AXUIElementGetWindow(element, &wid) == .success, wid != 0 {
                tracker.lastFocus[wid] = Date()
            }
        }
        guard AXObserverCreate(pid, callback, &observer) == .success,
              let observer else { return }
        let appElement = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for notification in [kAXFocusedWindowChangedNotification,
                             kAXMainWindowChangedNotification] {
            AXObserverAddNotification(observer, appElement,
                                      notification as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(),
                           AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    private func stampFocusedWindow(pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            app, kAXFocusedWindowAttribute as CFString, &value) == .success
        else { return }
        var wid: UInt32 = 0
        if _AXUIElementGetWindow(value as! AXUIElement, &wid) == .success, wid != 0 {
            lastFocus[wid] = Date()
        }
    }
}
