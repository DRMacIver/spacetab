import AppKit
import ApplicationServices

// Focusing a window on another space cannot go through the Accessibility API:
// kAXWindowsAttribute omits windows on non-current spaces. Instead use the
// SkyLight process-serial-number path that AltTab and yabai use: make the
// process front "for" the target window, then post a synthetic pair of
// window-targeted activation events. macOS switches to the window's space.
enum WindowFocus {
    private typealias SetFrontProcess = @convention(c) (
        UnsafePointer<ProcessSerialNumber>, UInt32, UInt32) -> CGError
    private typealias PostEventRecord = @convention(c) (
        UnsafePointer<ProcessSerialNumber>, UnsafePointer<UInt8>) -> CGError
    private typealias GetProcessForPIDFn = @convention(c) (
        pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

    private static func sym<T>(_ name: String, _ type: T.Type) -> T {
        guard let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2) /* RTLD_DEFAULT */, name) else {
            fatalError("symbol not found: \(name)")
        }
        return unsafeBitCast(p, to: T.self)
    }

    private static let setFrontProcess =
        sym("_SLPSSetFrontProcessWithOptions", SetFrontProcess.self)
    private static let postEventRecord =
        sym("SLPSPostEventRecordTo", PostEventRecord.self)
    private static let getProcessForPID =
        sym("GetProcessForPID", GetProcessForPIDFn.self)

    private static let kCPSUserGenerated: UInt32 = 0x200

    static func focus(windowID: UInt32, pid: pid_t, spaceID: UInt64) {
        // The PSN events below make the window key, but macOS 26 does not
        // follow the key window to another space — switch explicitly.
        SkyLight.switchTo(space: spaceID)
        var psn = ProcessSerialNumber()
        guard getProcessForPID(pid, &psn) == noErr else {
            NSLog("SpaceTab: GetProcessForPID failed for pid \(pid)")
            return
        }
        _ = setFrontProcess(&psn, windowID, kCPSUserGenerated)

        // Synthetic event record targeting the window (the documented-by-
        // reverse-engineering layout used by AltTab/yabai).
        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes[0x04] = 0xf8
        bytes[0x3a] = 0x10
        withUnsafeBytes(of: windowID.littleEndian) { wid in
            for (i, b) in wid.enumerated() { bytes[0x3c + i] = b }
        }
        for i in 0x20..<0x30 { bytes[i] = 0xff }
        bytes[0x08] = 0x01  // "make key" down
        _ = postEventRecord(&psn, bytes)
        bytes[0x08] = 0x02  // "make key" up
        _ = postEventRecord(&psn, bytes)

        NSRunningApplication(processIdentifier: pid)?
            .activate(options: [.activateIgnoringOtherApps])

        // Best-effort AX polish (works once the window's space is current).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            AXBridge.focus(windowID: windowID, pid: pid)
        }
    }
}
