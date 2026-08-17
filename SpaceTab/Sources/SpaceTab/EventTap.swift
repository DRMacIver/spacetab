import AppKit
import SpaceTabCore

/// Intercepts Cmd-Tab before the system switcher sees it, then owns the
/// keyboard while the switcher is up: tab/arrows navigate, releasing Cmd
/// commits, Escape cancels.
final class EventTap {
    private let panel = SwitcherPanel()
    private var model: SwitcherModel?
    private var tap: CFMachPort?

    private enum Key: Int64 {
        case tab = 48, escape = 53, ret = 36
        case left = 123, right = 124, down = 125, up = 126
    }

    func start() {
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let tap = Unmanaged<EventTap>.fromOpaque(refcon!).takeUnretainedValue()
            return tap.handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            fputs("Failed to create event tap. Grant Accessibility permission and restart.\n", stderr)
            exit(1)
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disables taps that are slow or on login; re-enable.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        let cmdHeld = event.flags.contains(.maskCommand)
        let shiftHeld = event.flags.contains(.maskShift)

        if model == nil {
            // Inactive: only Cmd-Tab interests us.
            guard type == .keyDown, cmdHeld, keycode == Key.tab.rawValue else {
                return Unmanaged.passUnretained(event)
            }
            activate(backwards: shiftHeld)
            return nil
        }

        // Active.
        if type == .flagsChanged {
            if !cmdHeld { commit() }
            return nil
        }
        guard type == .keyDown, var m = model else { return nil }
        switch Key(rawValue: keycode) {
        case .tab: shiftHeld ? m.moveUp() : m.moveDown()
        case .down: m.moveDown()
        case .up: m.moveUp()
        case .left: m.moveLeft()
        case .right: m.moveRight()
        case .escape:
            cancel()
            return nil
        case .ret:
            commit()
            return nil
        case nil:
            return nil  // swallow everything else while active
        }
        model = m
        panel.update(model: m)
        return nil
    }

    private func activate(backwards: Bool) {
        guard var m = SwitcherModel(columns: WindowList.snapshot()) else { return }
        if backwards {
            m.moveUp()
            m.moveUp()  // undo the default second-window selection, then step back
        }
        model = m
        panel.show(model: m)
    }

    private func commit() {
        guard let m = model else { return }
        panel.hide()
        model = nil
        let target = m.selectedWindow
        AXBridge.focus(windowID: target.id, pid: target.pid)
    }

    private func cancel() {
        panel.hide()
        model = nil
    }
}
