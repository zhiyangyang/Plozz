import CoreModels
import SwiftUI

public extension MediaDownloadDestination {
    @MainActor
    static var current: Self {
        #if os(iOS)
        switch UIDevice.current.userInterfaceIdiom {
        case .phone: .iPhone
        case .pad: .iPad
        default: .device
        }
        #else
        .device
        #endif
    }
}

public struct SeriesDownloadActionLabel<Accessory: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 24

    private let title: LocalizedStringResource
    private let subtitle: LocalizedStringResource
    private let systemImage: String
    private let detail: LocalizedStringResource?
    private let accessory: Accessory

    public init(
        title: LocalizedStringResource,
        subtitle: LocalizedStringResource,
        systemImage: String,
        detail: LocalizedStringResource? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.detail = detail
        self.accessory = accessory()
    }

    public var body: some View {
        let contentLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        let rowLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        rowLayout {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .regular))
                .foregroundStyle(.tint)
                .frame(width: iconSize)
                .accessibilityHidden(true)
            contentLayout {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .foregroundStyle(Color.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    }
                }
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                accessory
            }
        }
        .frame(minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        #if os(iOS)
        .alignmentGuide(.listRowSeparatorLeading) {
            $0[.leading] + (dynamicTypeSize.isAccessibilitySize ? 0 : iconSize + 12)
        }
        #endif
    }
}
