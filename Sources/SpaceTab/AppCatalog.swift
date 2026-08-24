import AppKit
import SpaceTabCore

/// Installed + running applications, as launcher candidates.
enum AppCatalog {
    private static let searchDirs = [
        "/Applications",
        "/System/Applications",
        "/System/Applications/Utilities",
        ("~/Applications" as NSString).expandingTildeInPath,
    ]

    private struct Installed {
        let name: String
        let bundleID: String
        let path: String
    }

    private static var installedCache: [Installed] = []

    static func rescanInstalled() {
        var found: [Installed] = []
        var seen = Set<String>()
        for dir in searchDirs {
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
            for entry in entries where entry.hasSuffix(".app") {
                let path = "\(dir)/\(entry)"
                guard let bundle = Bundle(path: path),
                      let id = bundle.bundleIdentifier,
                      !seen.contains(id) else { continue }
                seen.insert(id)
                let name = (bundle.localizedInfoDictionary?["CFBundleDisplayName"]
                    ?? bundle.infoDictionary?["CFBundleDisplayName"]
                    ?? bundle.infoDictionary?["CFBundleName"]) as? String
                    ?? String(entry.dropLast(4))
                found.append(Installed(name: name, bundleID: id, path: path))
            }
        }
        installedCache = found
    }

    static func candidates() -> [LauncherApp] {
        var byBundle: [String: LauncherApp] = [:]
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular {
            guard let id = app.bundleIdentifier else { continue }
            byBundle[id] = LauncherApp(
                name: app.localizedName ?? id,
                bundleID: id,
                path: app.bundleURL?.path,
                pid: app.processIdentifier,
                lastUsed: FocusTracker.shared.appLastUsed[id])
        }
        for installed in installedCache where byBundle[installed.bundleID] == nil {
            byBundle[installed.bundleID] = LauncherApp(
                name: installed.name,
                bundleID: installed.bundleID,
                path: installed.path,
                pid: nil,
                lastUsed: FocusTracker.shared.appLastUsed[installed.bundleID])
        }
        return Array(byBundle.values)
    }
}
