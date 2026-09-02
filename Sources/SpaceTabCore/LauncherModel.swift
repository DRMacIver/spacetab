import Foundation

public struct LauncherApp: Equatable {
    public let name: String
    public let bundleID: String
    public let path: String?
    public let pid: pid_t?      // nil when not running
    public let lastUsed: Date?

    public init(name: String, bundleID: String, path: String?, pid: pid_t?,
                lastUsed: Date?) {
        self.name = name
        self.bundleID = bundleID
        self.path = path
        self.pid = pid
        self.lastUsed = lastUsed
    }
}

public struct LauncherWindow: Equatable {
    public let window: WindowEntry
    public let spaceID: UInt64
    public let lastFocus: Date?

    public init(window: WindowEntry, spaceID: UInt64, lastFocus: Date?) {
        self.window = window
        self.spaceID = spaceID
        self.lastFocus = lastFocus
    }
}

public enum LauncherResult: Equatable {
    case app(LauncherApp)
    case window(LauncherWindow)
}

/// How well `query` matches `text`; lower is better. nil = no match.
/// 0: prefix, 1: prefix of a later word, 2: substring, 3: subsequence.
public func matchTier(query: String, in text: String) -> Int? {
    let q = query.lowercased()
    let t = text.lowercased()
    guard !q.isEmpty else { return 0 }
    if t.hasPrefix(q) { return 0 }
    let words = t.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
    if words.contains(where: { $0.hasPrefix(q) }) { return 1 }
    if t.contains(q) { return 2 }
    // subsequence
    var qi = q.startIndex
    for c in t {
        if qi < q.endIndex, c == q[qi] { qi = q.index(after: qi) }
    }
    return qi == q.endIndex ? 3 : nil
}

/// Query/selection state for the launcher. Results are ranked by match
/// quality first, then recency of use; never-used items sort last, by name.
/// Within a tier, windows that only match through their app name sort after
/// app entries, so typing an app's name offers the app before its windows.
public struct LauncherModel: Equatable {
    public var maxResults = 12
    public private(set) var query = ""
    public private(set) var selected = 0
    private let apps: [LauncherApp]
    private let windows: [LauncherWindow]
    public private(set) var results: [LauncherResult] = []

    public init(apps: [LauncherApp], windows: [LauncherWindow]) {
        self.apps = apps
        self.windows = windows
        recompute()
    }

    public var selectedResult: LauncherResult? {
        results.indices.contains(selected) ? results[selected] : nil
    }

    public mutating func type(_ s: String) {
        query += s
        selected = 0
        recompute()
    }

    public mutating func backspace() {
        guard !query.isEmpty else { return }
        query.removeLast()
        selected = 0
        recompute()
    }

    public mutating func moveDown() {
        guard !results.isEmpty else { return }
        selected = min(selected + 1, results.count - 1)
    }

    public mutating func moveUp() {
        selected = max(selected - 1, 0)
    }

    private struct Ranked {
        let result: LauncherResult
        let tier: Int
        // Windows that match only through their app name sort after the app
        // entry itself: "chrome" should offer Google Chrome (new window)
        // before some recently focused Chrome window. Title matches are the
        // window's own merit and still compete with apps on recency.
        let demoted: Bool
        let recency: Date
        let name: String
    }

    private mutating func recompute() {
        var ranked: [Ranked] = []
        for app in apps {
            if let tier = matchTier(query: query, in: app.name) {
                // Non-running apps rank below live windows and running apps
                // of comparable match quality: a name-prefix match on a
                // not-running app shouldn't outrank an open window the user
                // is actually working in.
                let penalty = app.pid == nil ? 2 : 0
                ranked.append(Ranked(result: .app(app), tier: tier + penalty,
                                     demoted: false,
                                     recency: app.lastUsed ?? .distantPast,
                                     name: app.name))
            }
        }
        for w in windows {
            let titleTier = matchTier(query: query, in: w.window.title)
            let appTier = matchTier(query: query, in: w.window.appName)
            if let tier = [titleTier, appTier].compactMap({ $0 }).min() {
                // Demoted unless the title match is strictly better than the
                // app-name match: titles often embed the app name, and an
                // equal-tier title match is usually just that.
                let demoted = (appTier ?? .max) <= (titleTier ?? .max)
                ranked.append(Ranked(result: .window(w), tier: tier,
                                     demoted: demoted,
                                     recency: w.lastFocus ?? .distantPast,
                                     name: w.window.appName))
            }
        }
        results = ranked.sorted { a, b in
            if a.tier != b.tier { return a.tier < b.tier }
            if a.demoted != b.demoted { return !a.demoted }
            if a.recency != b.recency { return a.recency > b.recency }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }.prefix(maxResults).map(\.result)
        selected = 0
    }
}
