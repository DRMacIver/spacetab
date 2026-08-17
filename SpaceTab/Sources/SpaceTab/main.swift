import AppKit

if CommandLine.arguments.contains("--list") {
    for column in WindowList.snapshot() {
        let raw = SkyLight.windows(onSpace: column.id)
        print("Space \(column.id)\(column.isCurrent ? " (current)" : "") [raw: \(raw.count)]:")
        for w in column.windows {
            print("  [\(w.id)] \(w.appName) — \(w.title)")
        }
    }
    exit(0)
}

// Prompt for Accessibility permission if not yet granted.
let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
if !AXIsProcessTrustedWithOptions(options) {
    fputs("""
    SpaceTab needs Accessibility permission (System Settings > Privacy & \
    Security > Accessibility). Grant it, then relaunch.
    """ + "\n", stderr)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let eventTap = EventTap()

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        eventTap.start()
        NSLog("SpaceTab running. Cmd-Tab to open; arrows navigate; release Cmd to switch.")
    }
}

let delegate = AppDelegate()
app.delegate = delegate
app.run()
