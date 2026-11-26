import Foundation

/// Copy shared by the Plex Home-user PIN prompt and its model errors.
public enum PlexPINCopy {
    public static let incorrectPIN = LocalizedStringResource(
        "plexPIN.incorrectPIN",
        defaultValue: "Incorrect PIN. Try again.",
        comment: "Shown under the Plex PIN pad when the entered PIN is wrong."
    )

    public static let switchFailed = LocalizedStringResource(
        "plexPIN.switchFailed",
        defaultValue: "Couldn’t switch Plex user. Please try again.",
        comment: "Shown under the Plex PIN pad when switching users failed for a reason other than a wrong PIN."
    )
}
