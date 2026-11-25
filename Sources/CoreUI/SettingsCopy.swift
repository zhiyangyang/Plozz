import Foundation

/// Copy that appears in more than one Settings surface, so tvOS and iOS can never
/// drift apart on the wording — and, now that it is localized, so the string is
/// translated once rather than once per shell.
///
/// `LocalizedStringResource` rather than `String`: `Text(aString)` renders
/// verbatim, so copy typed as `String` is invisible to both the String Catalog and
/// the compiler's string extraction, and would silently stay English.
public enum SettingsCopy {
    public static let sources: LocalizedStringResource = "Sources"
    public static let addSource: LocalizedStringResource = "Add Source"
    public static let tvSources: LocalizedStringResource = "TV Sources"
    public static let addTVSource: LocalizedStringResource = "Add TV Source"

    public static let libraries = LocalizedStringResource(
        "settings.nav.libraries",
        defaultValue: "Libraries",
        comment: "Navigation row and page heading for the screen listing the user's media libraries."
    )
    public static let attributions = LocalizedStringResource(
        "settings.nav.attributions",
        defaultValue: "Attributions",
        comment: "Navigation row for the screen crediting third-party software and data sources."
    )

    public static let shareDiagnostics: LocalizedStringResource = "Share Diagnostics"
    public static let enableDiagnosticSharing: LocalizedStringResource = "Enable Sharing"
    public static let diagnosticSharingRequired: LocalizedStringResource =
        "Turn on Share Diagnostics to send a report."
    public static let diagnosticSharingUnavailable: LocalizedStringResource =
        "Diagnostic sharing is unavailable in this build."
    public static let diagnosticSubmissionFailed: LocalizedStringResource =
        "Couldn't submit diagnostics. Check that Share Diagnostics is on and try again."

    public static let automaticDiagnostics: LocalizedStringResource =
        "Automatically share crash reports, technical errors, app and device information, screen categories, and performance diagnostics with the developer through Sentry."

    public static let automaticDiagnosticsExclusions: LocalizedStringResource =
        "Automatic reports exclude logins, server addresses, and media titles."

    public static let manualDiagnostics: LocalizedStringResource =
        "Send recent activity, search, playback and connection diagnostics, and your message to the developer through Sentry. Don't include passwords or personal information."

    public static let diagnosticsMessage: LocalizedStringResource = "Message (required)"
    public static let diagnosticsMessagePrivacy: LocalizedStringResource =
        "Don't include passwords or personal information."

    // MARK: - Scope headers

    /// App management, separate from the active profile's personal preferences.
    public static let everyone = LocalizedStringResource(
        "Manage Plozz",
        comment: "Settings section heading for managing sources, profiles, parental protection, and metadata providers, separate from personal profile preferences. Plozz is the app name and must remain unchanged."
    )


}
