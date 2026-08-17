import AppKit
import ApplicationServices

// _AXUIElementGetWindow: private but long-stable; maps an AX window element
// to its CGWindowID, which is the only reliable way to match the two worlds.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<UInt32>) -> AXError

enum AXBridge {
    static func axWindow(windowID: UInt32, pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
                == .success,
              let windows = value as? [AXUIElement] else { return nil }
        for w in windows {
            var wid: UInt32 = 0
            if _AXUIElementGetWindow(w, &wid) == .success, wid == windowID {
                return w
            }
        }
        return nil
    }

    static func title(windowID: UInt32, pid: pid_t) -> String? {
        guard let w = axWindow(windowID: windowID, pid: pid) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &value)
                == .success else { return nil }
        return value as? String
    }

    /// Press the window's close button. Returns false when the window has no
    /// AX element visible to us (typically: it lives on another space).
    @discardableResult
    static func close(windowID: UInt32, pid: pid_t) -> Bool {
        guard let w = axWindow(windowID: windowID, pid: pid) else { return false }
        var button: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            w, kAXCloseButtonAttribute as CFString, &button) == .success
        else { return false }
        return AXUIElementPerformAction(
            button as! AXUIElement, kAXPressAction as CFString) == .success
    }

    /// Close a window that may live on another space. AX can't see windows
    /// on non-current spaces, so as a last resort switch to the window's
    /// space and stay there (hopping back proved jarring).
    static func close(windowID: UInt32, pid: pid_t, spaceID: UInt64,
                      completion: @escaping (Bool) -> Void) {
        if close(windowID: windowID, pid: pid) {
            completion(true)
            return
        }
        guard SkyLight.getActiveSpace(SkyLight.connection) != spaceID else {
            completion(false)
            return
        }
        SkyLight.switchTo(space: spaceID)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            completion(close(windowID: windowID, pid: pid))
        }
    }

    /// Raise the window and activate its app. macOS switches to the window's
    /// space as part of the activation.
    static func focus(windowID: UInt32, pid: pid_t) {
        if let w = axWindow(windowID: windowID, pid: pid) {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementPerformAction(w, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(w, kAXMainAttribute as CFString, kCFBooleanTrue)
            // AXRaise alone doesn't move keyboard focus when the app is
            // already frontmost (same-app window switching).
            AXUIElementSetAttributeValue(w, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(
                app, kAXFocusedWindowAttribute as CFString, w)
        } else {
            NSLog("SpaceTab: no AX window match for id \(windowID) pid \(pid)")
        }
        NSRunningApplication(processIdentifier: pid)?
            .activate(options: [.activateIgnoringOtherApps])
    }
}
