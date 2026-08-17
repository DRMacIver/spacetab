import AppKit
import SpaceTabCore

/// Intercepts Cmd-Tab before the system switcher sees it, then owns the
/// keyboard while the switcher is up: tab/arrows navigate, releasing Cmd
/// commits, Escape cancels.
final class EventTap {
    private let panel = SwitcherPanel()
    private var model: SwitcherModel?
    private var tap: CFMachPort?
    private var pendingShow: DispatchWorkItem?

    private enum Key: Int64 {
        case tab = 48, escape = 53, ret = 36, w = 13
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
        case .w:
            closeSelected()
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
        // Don't flash the panel on a quick Cmd-Tab: only draw it if the
        // switcher is still up after a short delay.
        let work = DispatchWorkItem { [weak self] in
            guard let self, let m = self.model else { return }
            self.panel.show(model: m)
        }
        pendingShow = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func commit() {
        guard let m = model else { return }
        pendingShow?.cancel()
        pendingShow = nil
        panel.hide()
        model = nil
        let target = m.selectedWindow
        WindowFocus.focus(windowID: target.id, pid: target.pid,
                          spaceID: m.columns[m.selectedColumn].id)
    }

    private func closeSelected() {
        guard var m = model else { return }
        let target = m.selectedWindow
        let spaceID = m.columns[m.selectedColumn].id

        // Optimistic: drop the row from the list immediately; the rebuild
        // below resurrects it if the window refused to close (unsaved
        // changes dialog, etc.).
        if m.removeSelectedWindow() {
            model = m
            panel.update(model: m)
        } else {
            cancel()
        }

        AXBridge.close(windowID: target.id, pid: target.pid,
                       spaceID: spaceID) { [weak self] ok in
            guard let self else { return }
            if !ok {
                NSLog("SpaceTab: could not close window \(target.id) (\(target.appName))")
            }
            // Generous delay: some windows take over a second to close, and
            // an early rebuild briefly resurrects them (disappear-reappear-
            // disappear). Windows that refused come back with a modal badge.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                guard let old = self.model else { return }
                guard var fresh = SwitcherModel(columns: WindowList.snapshot()) else {
                    self.cancel()
                    return
                }
                fresh.select(column: old.selectedColumn, row: old.selectedRow)
                self.model = fresh
                self.panel.update(model: fresh)
            }
        }
    }

    private func cancel() {
        pendingShow?.cancel()
        pendingShow = nil
        panel.hide()
        model = nil
    }
}
