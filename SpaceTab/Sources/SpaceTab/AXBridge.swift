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

    /// Raise the window and activate its app. macOS switches to the window's
    /// space as part of the activation.
    static func focus(windowID: UInt32, pid: pid_t) {
        if let w = axWindow(windowID: windowID, pid: pid) {
            AXUIElementPerformAction(w, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(w, kAXMainAttribute as CFString, kCFBooleanTrue)
        }
        NSRunningApplication(processIdentifier: pid)?
            .activate(options: [.activateIgnoringOtherApps])
    }
}
