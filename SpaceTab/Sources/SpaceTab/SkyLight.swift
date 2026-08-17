import Foundation

// Private SkyLight APIs, resolved at runtime. Same calls yabai/AltTab rely on.
enum SkyLight {
    private static let handle = dlopen(
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    private static func sym<T>(_ name: String, _ type: T.Type) -> T {
        guard let h = handle, let p = dlsym(h, name) else {
            fatalError("SkyLight symbol not found: \(name)")
        }
        return unsafeBitCast(p, to: T.self)
    }

    typealias MainConnectionID = @convention(c) () -> Int32
    typealias CopyManagedDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>
    typealias GetActiveSpace = @convention(c) (Int32) -> UInt64
    typealias CopyWindowsWithOptionsAndTags = @convention(c) (
        Int32, UInt32, CFArray, UInt32,
        UnsafeMutablePointer<UInt64>, UnsafeMutablePointer<UInt64>
    ) -> Unmanaged<CFArray>?

    static let mainConnectionID = sym("SLSMainConnectionID", MainConnectionID.self)
    static let copyManagedDisplaySpaces = sym("SLSCopyManagedDisplaySpaces", CopyManagedDisplaySpaces.self)
    static let getActiveSpace = sym("SLSGetActiveSpace", GetActiveSpace.self)
    static let copyWindowsWithOptionsAndTags =
        sym("SLSCopyWindowsWithOptionsAndTags", CopyWindowsWithOptionsAndTags.self)

    static let connection: Int32 = mainConnectionID()

    struct SpaceInfo {
        let id: UInt64
        let isCurrent: Bool
        let isFullscreen: Bool
    }

    /// All user-visible spaces in mission-control order, across displays.
    static func spaces() -> [SpaceInfo] {
        let displays = copyManagedDisplaySpaces(connection).takeRetainedValue()
            as! [[String: Any]]
        var result: [SpaceInfo] = []
        for display in displays {
            let current = (display["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? UInt64
            for space in display["Spaces"] as? [[String: Any]] ?? [] {
                guard let id = space["ManagedSpaceID"] as? UInt64 else { continue }
                let type = space["type"] as? Int ?? 0
                result.append(SpaceInfo(
                    id: id,
                    isCurrent: id == current,
                    isFullscreen: type == 4  // 0 = user space, 4 = fullscreen app
                ))
            }
        }
        return result
    }

    /// Window IDs present on the given space, front-to-back.
    static func windows(onSpace spaceID: UInt64) -> [UInt32] {
        var setTags: UInt64 = 0
        var clearTags: UInt64 = 0
        guard let arr = copyWindowsWithOptionsAndTags(
            connection, 0, [NSNumber(value: spaceID)] as CFArray, 0x2, &setTags, &clearTags
        )?.takeRetainedValue() as? [NSNumber] else { return [] }
        return arr.map { $0.uint32Value }
    }
}
