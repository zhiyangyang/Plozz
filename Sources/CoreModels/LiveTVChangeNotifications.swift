import Foundation

public extension Notification.Name {
    /// A local Live TV preference/catalog change that the Home runtime should
    /// re-read. Formerly also published by cross-device sync; now local only.
    static let plozzLiveTVPortableStateDidChange = Notification.Name(
        "com.plozz.liveTV.portableStateDidChange"
    )
}
