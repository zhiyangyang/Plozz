import Foundation

/// The distribution channel baked into this binary, used for build labelling and
/// beta-only diagnostics.
public enum AppReleaseChannel: Sendable {
    case debug
    case testflight
    case production

    /// Info.plist key holding the channel baked in at build time by
    /// `tools/generate-project.sh` (from `$PLOZZ_RELEASE_CHANNEL`, which the
    /// fastlane `beta`/`release` lanes set). Empty for local builds.
    static let bundleKey = "PlozzReleaseChannel"

    /// The channel baked into this binary, or `nil` when none was (local builds,
    /// or an unresolved `$(...)` build setting).
    static func baked(
        _ raw: String? = Bundle.main.object(forInfoDictionaryKey: bundleKey) as? String
    ) -> AppReleaseChannel? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              !(trimmed.hasPrefix("$(") && trimmed.hasSuffix(")")) else { return nil }
        switch trimmed.lowercased() {
        case "testflight": return .testflight
        case "production": return .production
        case "debug": return .debug
        default: return nil
        }
    }

    public static var current: AppReleaseChannel {
        #if DEBUG
        return .debug
        #else
        if let baked = baked() { return baked }
        if let receiptURL = Bundle.main.appStoreReceiptURL,
           receiptURL.lastPathComponent == "sandboxReceipt" {
            return .testflight
        }
        return .production
        #endif
    }

    /// Debug + TestFlight are "beta": builds still under active testing.
    public var isBeta: Bool { self != .production }
}
