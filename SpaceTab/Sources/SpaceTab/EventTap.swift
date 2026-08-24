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

    private let launcherPanel = LauncherPanel()
    private var launcher: LauncherModel?

    private enum Key: Int64 {
        case tab = 48, escape = 53, ret = 36, w = 13, space = 49, delete = 51
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

        if launcher != nil {
            return handleLauncher(type: type, event: event, keycode: keycode,
                                  cmdHeld: cmdHeld)
        }

        if model == nil {
            // Inactive: Cmd-Tab opens the switcher, Cmd-Space the launcher.
            guard type == .keyDown, cmdHeld else {
                return Unmanaged.passUnretained(event)
            }
            switch keycode {
            case Key.tab.rawValue:
                activate(backwards: shiftHeld)
                return nil
            case Key.space.rawValue:
                activateLauncher()
                return nil
            default:
                return Unmanaged.passUnretained(event)
            }
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
        default:
            return nil  // swallow everything else while active
        }
        model = m
        panel.update(model: m)
        return nil
    }

    // MARK: - Launcher (Cmd-Space)

    private func activateLauncher() {
        AppCatalog.rescanInstalled()
        var windows: [LauncherWindow] = []
        for column in WindowList.snapshot() {
            for w in column.windows {
                windows.append(LauncherWindow(
                    window: w, spaceID: column.id,
                    lastFocus: FocusTracker.shared.lastFocus[w.id]))
            }
        }
        let m = LauncherModel(apps: AppCatalog.candidates(), windows: windows)
        launcher = m
        launcherPanel.show(model: m)
    }

    private func handleLauncher(type: CGEventType, event: CGEvent,
                                keycode: Int64, cmdHeld: Bool) -> Unmanaged<CGEvent>? {
        guard type == .keyDown else { return nil }  // swallow flag changes etc.
        guard var m = launcher else { return nil }
        switch Key(rawValue: keycode) {
        case .escape:
            dismissLauncher()
            return nil
        case .space where cmdHeld:
            dismissLauncher()  // Cmd-Space toggles
            return nil
        case .ret:
            let result = m.selectedResult
            dismissLauncher()
            if let result { LauncherActions.perform(result) }
            return nil
        case .down:
            m.moveDown()
        case .up:
            m.moveUp()
        case .tab where !cmdHeld:
            m.moveDown()
        case .delete:
            m.backspace()
        case .left, .right:
            break
        default:
            if !cmdHeld, let chars = typedCharacters(from: event), !chars.isEmpty {
                m.type(chars)
            }
        }
        launcher = m
        launcherPanel.update(model: m)
        return nil
    }

    private func dismissLauncher() {
        launcherPanel.hide()
        launcher = nil
    }

    private func typedCharacters(from event: CGEvent) -> String? {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: buffer.count,
                                       actualStringLength: &length,
                                       unicodeString: &buffer)
        guard length > 0 else { return nil }
        let s = String(utf16CodeUnits: buffer, count: length)
        // Printable characters only — no control chars from arrows etc.
        return s.allSatisfy { !$0.isNewline && ($0 == " " || !$0.unicodeScalars
            .contains(where: { $0.properties.generalCategory == .control })) }
            ? s : nil
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
