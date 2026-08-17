import Foundation

public struct WindowEntry: Equatable, Identifiable {
    public let id: UInt32          // CGWindowID
    public let pid: pid_t
    public let appName: String
    public let title: String

    public init(id: UInt32, pid: pid_t, appName: String, title: String) {
        self.id = id
        self.pid = pid
        self.appName = appName
        self.title = title
    }
}

public struct SpaceColumn: Equatable, Identifiable {
    public let id: UInt64          // space ID
    public let isCurrent: Bool
    public let windows: [WindowEntry]

    public init(id: UInt64, isCurrent: Bool, windows: [WindowEntry]) {
        self.id = id
        self.isCurrent = isCurrent
        self.windows = windows
    }
}

/// Pure navigation state for the switcher: a grid of columns (spaces),
/// each holding a vertical list of windows. Tab/down and shift-tab/up move
/// within a column (wrapping); left/right move between columns, keeping the
/// row as close as possible.
public struct SwitcherModel: Equatable {
    public private(set) var columns: [SpaceColumn]
    public private(set) var selectedColumn: Int
    public private(set) var selectedRow: Int

    /// Columns with no windows are kept (so every space is visible) but are
    /// skipped by navigation.
    public init?(columns: [SpaceColumn]) {
        guard columns.contains(where: { !$0.windows.isEmpty }) else { return nil }
        self.columns = columns
        // Start on the current space's column if it has windows, else the
        // first non-empty column.
        let start = columns.firstIndex(where: { $0.isCurrent && !$0.windows.isEmpty })
            ?? columns.firstIndex(where: { !$0.windows.isEmpty })!
        self.selectedColumn = start
        // Cmd-tab semantics: initial selection is the *second* window (the
        // one you'd switch to), falling back to the first.
        self.selectedRow = columns[start].windows.count > 1 ? 1 : 0
    }

    public var selectedWindow: WindowEntry {
        columns[selectedColumn].windows[selectedRow]
    }

    public mutating func moveDown() {
        let count = columns[selectedColumn].windows.count
        selectedRow = (selectedRow + 1) % count
    }

    public mutating func moveUp() {
        let count = columns[selectedColumn].windows.count
        selectedRow = (selectedRow - 1 + count) % count
    }

    /// Move selection as close as possible to (column, row) — used to keep
    /// the selection in place when the window list is rebuilt (e.g. after
    /// closing a window). Falls back to the nearest non-empty column.
    public mutating func select(column: Int, row: Int) {
        let n = columns.count
        let target = min(max(column, 0), n - 1)
        for offset in 0..<n {
            for candidate in [target + offset, target - offset] {
                if columns.indices.contains(candidate),
                   !columns[candidate].windows.isEmpty {
                    selectedColumn = candidate
                    selectedRow = min(max(row, 0), columns[candidate].windows.count - 1)
                    return
                }
            }
        }
    }

    /// Optimistically remove the selected window (e.g. while a close is in
    /// flight). Selection stays at the same position, clamped. Returns false
    /// when this was the last window anywhere — the switcher should close.
    public mutating func removeSelectedWindow() -> Bool {
        let column = columns[selectedColumn]
        var windows = column.windows
        windows.remove(at: selectedRow)
        columns[selectedColumn] = SpaceColumn(
            id: column.id, isCurrent: column.isCurrent, windows: windows)
        guard columns.contains(where: { !$0.windows.isEmpty }) else { return false }
        select(column: selectedColumn, row: selectedRow)
        return true
    }

    public mutating func moveRight() { moveHorizontally(by: 1) }
    public mutating func moveLeft() { moveHorizontally(by: -1) }

    private mutating func moveHorizontally(by step: Int) {
        let n = columns.count
        var col = selectedColumn
        for _ in 1..<max(n, 2) {
            col = (col + step + n) % n
            if !columns[col].windows.isEmpty {
                selectedColumn = col
                selectedRow = min(selectedRow, columns[col].windows.count - 1)
                return
            }
        }
    }
}
