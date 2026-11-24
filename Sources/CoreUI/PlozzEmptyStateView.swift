#if canImport(SwiftUI)
import SwiftUI

/// A friendly, reusable "nothing here" state: the sad Plozz logo above a short
/// message, centered in the available space. Use it anywhere a query or list
/// legitimately comes back empty (search with no hits, an empty library, a
/// filtered view with no matches…) so those dead ends all feel like the same
/// app instead of each screen inventing its own placeholder.
///
/// Pass a custom `imageName` to swap the mascot for another asset-catalog image
/// (it resolves from the main bundle, matching the app's other brand marks).
public struct PlozzEmptyStateView: View {
    private let message: LocalizedStringResource
    private let imageName: String
    private let imageSize: CGFloat

    public init(
        _ message: LocalizedStringResource,
        imageName: String = "PlozzLogoSad",
        imageSize: CGFloat = 140
    ) {
        self.message = message
        self.imageName = imageName
        self.imageSize = imageSize
    }

    public var body: some View {
        VStack(spacing: 28) {
            Image(imageName)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: imageSize, height: imageSize)
                .accessibilityHidden(true)
            Text(message)
                .font(.title2)
                .multilineTextAlignment(.center)
                .plozzForeground(.secondary)
                .frame(maxWidth: 800)
        }
        .accessibilityElement(children: .combine)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
