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

// Prompt for Accessibility permission once, then wait quietly for the grant.
// Exiting here instead would make launchd (KeepAlive) respawn us and prompt
// again on every relaunch.
if !AXIsProcessTrusted() {
    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
    fputs("""
    SpaceTab needs Accessibility permission (System Settings > Privacy & \
    Security > Accessibility). Waiting for the grant...
    """ + "\n", stderr)
    while !AXIsProcessTrusted() {
        Thread.sleep(forTimeInterval: 3)
    }
    fputs("Accessibility granted.\n", stderr)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let eventTap = EventTap()

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        FocusTracker.shared.start()
        eventTap.start()
        NSLog("SpaceTab running. Cmd-Tab to open; arrows navigate; release Cmd to switch.")
    }
}

let delegate = AppDelegate()
app.delegate = delegate
app.run()
