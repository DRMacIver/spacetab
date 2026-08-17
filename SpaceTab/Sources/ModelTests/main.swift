import Foundation
import SpaceTabCore

var failures = 0

func check(_ cond: Bool, _ name: String, file: String = #file, line: Int = #line) {
    if cond {
        print("PASS \(name)")
    } else {
        failures += 1
        print("FAIL \(name) (\(file):\(line))")
    }
}

func w(_ id: UInt32) -> WindowEntry {
    WindowEntry(id: id, pid: 1, appName: "App\(id)", title: "Win\(id)")
}

// nil when no windows anywhere
check(SwitcherModel(columns: [SpaceColumn(id: 1, isCurrent: true, windows: [])]) == nil,
      "nilWhenNoWindowsAnywhere")

// starts on current space, second window
do {
    let m = SwitcherModel(columns: [
        SpaceColumn(id: 1, isCurrent: false, windows: [w(1)]),
        SpaceColumn(id: 2, isCurrent: true, windows: [w(2), w(3)]),
    ])!
    check(m.selectedColumn == 1 && m.selectedWindow == w(3), "startsOnCurrentSpaceSecondWindow")
}

// single window on current space
do {
    let m = SwitcherModel(columns: [SpaceColumn(id: 1, isCurrent: true, windows: [w(1)])])!
    check(m.selectedWindow == w(1), "startsOnFirstWindowWhenCurrentSpaceHasOne")
}

// falls back to first non-empty column when current space is empty
do {
    let m = SwitcherModel(columns: [
        SpaceColumn(id: 1, isCurrent: false, windows: []),
        SpaceColumn(id: 2, isCurrent: false, windows: [w(1)]),
        SpaceColumn(id: 3, isCurrent: true, windows: []),
    ])!
    check(m.selectedColumn == 1, "fallsBackToFirstNonEmptyColumn")
}

// vertical wrapping
do {
    var m = SwitcherModel(columns: [
        SpaceColumn(id: 1, isCurrent: true, windows: [w(1), w(2), w(3)]),
    ])!
    check(m.selectedWindow == w(2), "verticalStart")
    m.moveDown()
    check(m.selectedWindow == w(3), "moveDown")
    m.moveDown()
    check(m.selectedWindow == w(1), "moveDownWraps")
    m.moveUp()
    check(m.selectedWindow == w(3), "moveUpWraps")
}

// horizontal move clamps row
do {
    var m = SwitcherModel(columns: [
        SpaceColumn(id: 1, isCurrent: true, windows: [w(1), w(2), w(3)]),
        SpaceColumn(id: 2, isCurrent: false, windows: [w(4)]),
    ])!
    m.moveDown()
    m.moveRight()
    check(m.selectedColumn == 1 && m.selectedWindow == w(4), "horizontalClampsRow")
}

// horizontal skips empty columns and wraps
do {
    var m = SwitcherModel(columns: [
        SpaceColumn(id: 1, isCurrent: true, windows: [w(1)]),
        SpaceColumn(id: 2, isCurrent: false, windows: []),
        SpaceColumn(id: 3, isCurrent: false, windows: [w(2)]),
    ])!
    m.moveRight()
    check(m.selectedColumn == 2, "rightSkipsEmpty")
    m.moveRight()
    check(m.selectedColumn == 0, "rightWraps")
    m.moveLeft()
    check(m.selectedColumn == 2, "leftWraps")
}

// horizontal no-op when only one non-empty column
do {
    var m = SwitcherModel(columns: [
        SpaceColumn(id: 1, isCurrent: true, windows: [w(1), w(2)]),
        SpaceColumn(id: 2, isCurrent: false, windows: []),
    ])!
    m.moveRight()
    check(m.selectedColumn == 0, "noOpSingleColumn")
}

// select() clamps row and lands on requested column
do {
    var m = SwitcherModel(columns: [
        SpaceColumn(id: 1, isCurrent: true, windows: [w(1), w(2)]),
        SpaceColumn(id: 2, isCurrent: false, windows: [w(3)]),
    ])!
    m.select(column: 1, row: 5)
    check(m.selectedColumn == 1 && m.selectedWindow == w(3), "selectClampsRow")
}

// select() falls back to nearest non-empty column
do {
    var m = SwitcherModel(columns: [
        SpaceColumn(id: 1, isCurrent: true, windows: [w(1), w(2)]),
        SpaceColumn(id: 2, isCurrent: false, windows: []),
    ])!
    m.select(column: 1, row: 0)
    check(m.selectedColumn == 0, "selectFallsBackToNonEmpty")
    m.select(column: -3, row: 1)
    check(m.selectedColumn == 0 && m.selectedRow == 1, "selectClampsColumn")
}

// removeSelectedWindow keeps selection position, clamped
do {
    var m = SwitcherModel(columns: [
        SpaceColumn(id: 1, isCurrent: true, windows: [w(1), w(2), w(3)]),
    ])!
    m.moveDown() // row 2
    check(m.removeSelectedWindow(), "removeReturnsTrueWhenWindowsRemain")
    check(m.selectedWindow == w(2) && m.selectedRow == 1, "removeClampsSelection")
}

// removing the last window in a column moves to another column
do {
    var m = SwitcherModel(columns: [
        SpaceColumn(id: 1, isCurrent: true, windows: [w(1)]),
        SpaceColumn(id: 2, isCurrent: false, windows: [w(2)]),
    ])!
    check(m.removeSelectedWindow(), "removeLastInColumnSurvives")
    check(m.selectedWindow == w(2), "removeMovesToOtherColumn")
}

// removing the very last window signals shutdown
do {
    var m = SwitcherModel(columns: [
        SpaceColumn(id: 1, isCurrent: true, windows: [w(1)]),
    ])!
    check(!m.removeSelectedWindow(), "removeLastWindowReturnsFalse")
}

if failures > 0 {
    print("\(failures) failure(s)")
    exit(1)
}
print("All tests passed")
