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

// --- LauncherModel ---

func app(_ name: String, lastUsed: Date? = nil, running: Bool = true) -> LauncherApp {
    LauncherApp(name: name, bundleID: "test.\(name)", path: "/Applications/\(name).app",
                pid: running ? 100 : nil, lastUsed: lastUsed)
}

func lwin(_ id: UInt32, app appName: String, title: String, lastFocus: Date? = nil) -> LauncherWindow {
    LauncherWindow(
        window: WindowEntry(id: id, pid: 100, appName: appName, title: title),
        spaceID: 1, lastFocus: lastFocus)
}

// match tiers
check(matchTier(query: "gho", in: "Ghostty") == 0, "tierPrefix")
check(matchTier(query: "chr", in: "Google Chrome") == 1, "tierWordPrefix")
check(matchTier(query: "ost", in: "Ghostty") == 2, "tierSubstring")
check(matchTier(query: "gty", in: "Ghostty") == 3, "tierSubsequence")
check(matchTier(query: "xyz", in: "Ghostty") == nil, "tierNoMatch")
check(matchTier(query: "", in: "anything") == 0, "tierEmptyQuery")

let now = Date()

// prefix app beats recent-but-weaker window match
do {
    var m = LauncherModel(
        apps: [app("Ghostty", lastUsed: now.addingTimeInterval(-60))],
        windows: [lwin(1, app: "Google Chrome", title: "The Ghost of Tsushima",
                       lastFocus: now)])
    m.type("gho")
    check(m.selectedResult == .app(app("Ghostty", lastUsed: now.addingTimeInterval(-60))),
          "prefixAppBeatsWeakerWindow")
}

// app ranks above its own windows when its lastUsed is most recent
do {
    var m = LauncherModel(
        apps: [app("Ghostty", lastUsed: now)],
        windows: [lwin(1, app: "Ghostty", title: "shell",
                       lastFocus: now.addingTimeInterval(-10))])
    m.type("gho")
    if case .app(let a)? = m.selectedResult {
        check(a.name == "Ghostty", "appFirstWhenMostRecent")
    } else {
        check(false, "appFirstWhenMostRecent")
    }
    check(m.results.count == 2, "windowsListedBelowApp")
}

// title match surfaces a window when no app matches
do {
    var m = LauncherModel(
        apps: [app("Google Chrome", lastUsed: now)],
        windows: [lwin(1, app: "Google Chrome", title: "Audible - Library",
                       lastFocus: now.addingTimeInterval(-5))])
    m.type("audible")
    if case .window(let w)? = m.selectedResult {
        check(w.window.title == "Audible - Library", "titleMatchTopsWindow")
    } else {
        check(false, "titleMatchTopsWindow")
    }
}

// recency breaks ties within a tier
do {
    var m = LauncherModel(
        apps: [app("Ghostty", lastUsed: now.addingTimeInterval(-100)),
               app("Ghidra", lastUsed: now)],
        windows: [])
    m.type("gh")
    if case .app(let a)? = m.selectedResult {
        check(a.name == "Ghidra", "recencyBreaksTies")
    } else {
        check(false, "recencyBreaksTies")
    }
}

// never-used apps sort after used ones, alphabetically
do {
    var m = LauncherModel(
        apps: [app("Zebra"), app("Alpha"), app("Mid", lastUsed: now)],
        windows: [])
    m.type("")
    if case .app(let a)? = m.selectedResult { check(a.name == "Mid", "usedBeforeUnused") }
    if case .app(let a) = m.results[1] { check(a.name == "Alpha", "unusedAlphabetical") }
}

// live window beats name-prefix match of a non-running app
do {
    var m = LauncherModel(
        apps: [app("Audio MIDI Setup", running: false)],
        windows: [lwin(1, app: "Google Chrome", title: "Audible - Library",
                       lastFocus: now)])
    m.type("audi")
    if case .window(let w)? = m.selectedResult {
        check(w.window.title == "Audible - Library", "liveWindowBeatsNonRunningApp")
    } else {
        check(false, "liveWindowBeatsNonRunningApp")
    }
}

// but a non-running exact match still beats a fuzzy window match
do {
    var m = LauncherModel(
        apps: [app("Slack", running: false)],
        windows: [lwin(1, app: "Ghostty", title: "sales check", lastFocus: now)])
    m.type("slack")
    if case .app(let a)? = m.selectedResult {
        check(a.name == "Slack", "nonRunningExactBeatsFuzzyWindow")
    } else {
        check(false, "nonRunningExactBeatsFuzzyWindow")
    }
}

// app beats its own recently focused windows when the query matches the app
// name — even though window focus is fresher than the app's lastUsed
do {
    var m = LauncherModel(
        apps: [app("Ghostty", lastUsed: now.addingTimeInterval(-3600))],
        windows: [lwin(1, app: "Ghostty", title: "vim notes.md", lastFocus: now),
                  lwin(2, app: "Ghostty", title: "zsh", lastFocus: now.addingTimeInterval(-5))])
    m.type("ghost")
    if case .app(let a)? = m.selectedResult {
        check(a.name == "Ghostty", "appBeatsOwnRecentWindows")
    } else {
        check(false, "appBeatsOwnRecentWindows")
    }
}

// a title that merely embeds the app name doesn't dodge the demotion
do {
    var m = LauncherModel(
        apps: [app("Google Chrome", lastUsed: now.addingTimeInterval(-3600))],
        windows: [lwin(1, app: "Google Chrome", title: "Downloads - Google Chrome",
                       lastFocus: now)])
    m.type("chrome")
    if case .app(let a)? = m.selectedResult {
        check(a.name == "Google Chrome", "embeddedAppNameTitleStillDemoted")
    } else {
        check(false, "embeddedAppNameTitleStillDemoted")
    }
}

// a strictly better title match still competes with apps on recency
do {
    var m = LauncherModel(
        apps: [app("Ghidra", lastUsed: now.addingTimeInterval(-60))],
        windows: [lwin(1, app: "Google Chrome", title: "Ghidra docs", lastFocus: now)])
    m.type("ghidra")
    if case .window(let w)? = m.selectedResult {
        check(w.window.title == "Ghidra docs", "titleMatchStillCompetesOnRecency")
    } else {
        check(false, "titleMatchStillCompetesOnRecency")
    }
}

// typing resets selection; navigation clamps
do {
    var m = LauncherModel(apps: [app("A1"), app("A2")], windows: [])
    m.type("a")
    m.moveDown()
    check(m.selected == 1, "launcherMoveDown")
    m.moveDown()
    check(m.selected == 1, "launcherMoveDownClamps")
    m.type("1")
    check(m.selected == 0 && m.results.count == 1, "typingResetsSelection")
    m.moveUp()
    check(m.selected == 0, "launcherMoveUpClamps")
    m.backspace()
    check(m.results.count == 2, "backspaceWidens")
}

if failures > 0 {
    print("\(failures) failure(s)")
    exit(1)
}
print("All tests passed")
