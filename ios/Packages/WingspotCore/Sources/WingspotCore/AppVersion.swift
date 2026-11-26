import Foundation

/// The app version against the server's minimum (`min_version` in `/v1/config`, docs/MINIMUM-AGE-PLAN.md 4a). Versions are compared
/// part by part as numbers ("0.10.0" is newer than "0.9.0"); a missing part counts as 0. Anything that can't be read never asks for
/// an update: the check fails open, so a typo on the server can't lock everybody out.
public enum AppVersion {
    /// Where the apps remember the last minimum they were told (UserDefaults), so the check also works offline.
    public static let minimumKey = "minimumAppVersion"

    /// True when `installed` is older than `minimum`. False when either can't be read.
    public static func needsUpdate(installed: String?, minimum: String?) -> Bool {
        guard let installed = parts(installed), let minimum = parts(minimum) else { return false }
        for index in 0..<max(installed.count, minimum.count) {
            let have = index < installed.count ? installed[index] : 0
            let need = index < minimum.count ? minimum[index] : 0
            if have != need { return have < need }
        }
        return false
    }

    private static func parts(_ version: String?) -> [Int]? {
        guard let version = version?.trimmingCharacters(in: .whitespaces), !version.isEmpty else { return nil }
        let numbers = version.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard numbers.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        return numbers.compactMap { $0 }
    }
}
