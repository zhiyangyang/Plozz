#if canImport(UIKit)
import CoreModels
import CoreUI
import FeatureHomeCore
import SwiftUI

#if os(iOS)
private struct FeaturedArtworkSelectionKey: EnvironmentKey {
    static let defaultValue: ((MediaItem, MediaArtworkZoomSource) -> Void)? = nil
}

private extension EnvironmentValues {
    var featuredArtworkSelection: ((MediaItem, MediaArtworkZoomSource) -> Void)? {
        get { self[FeaturedArtworkSelectionKey.self] }
        set { self[FeaturedArtworkSelectionKey.self] = newValue }
    }
}
#endif

public struct FeaturedMediaRow: View {
    private let title: Text
    private let items: [MediaItem]
    private let scope: ObjectIdentifier
    private let isActive: Bool
    private let spoilers: SpoilerSettings
    private let onFocus: ((MediaItem) -> Void)?
    private let onSeeAll: (() -> Void)?
    private let onSelect: (MediaItem) -> Void
    @State private var rowID = UUID()
    @State private var selectedID: String?
    @State private var focusedID: String?
    @State private var priority: Int?
    @State private var isSettled = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var onBrowse: (() -> Void)?
    private var usesRowBrowsing = false
    private var isLoading = false

    public func loading(_ loading: Bool) -> Self {
        var copy = self
        copy.isLoading = loading
        return copy
    }

    #if os(iOS)
    private var onSelectArtwork: ((MediaItem, MediaArtworkZoomSource) -> Void)?

    public func artworkNavigation(
        _ action: @escaping (MediaItem, MediaArtworkZoomSource) -> Void
    ) -> Self {
        var copy = self
        copy.onSelectArtwork = action
        return copy
    }
    #endif

    public func browsingRow(_ action: (() -> Void)?) -> Self {
        var copy = self
        copy.onBrowse = action
        copy.usesRowBrowsing = true
        return copy
    }

    public init(
        title: Text, items: [MediaItem], scope: ObjectIdentifier,
        isActive: Bool, spoilers: SpoilerSettings = .default,
        onFocus: ((MediaItem) -> Void)? = nil, onSeeAll: (() -> Void)? = nil,
        onSelect: @escaping (MediaItem) -> Void
    ) {
        self.title = title
        self.items = items
        self.scope = scope
        self.isActive = isActive
        self.spoilers = spoilers
        self.onFocus = onFocus
        self.onSeeAll = onSeeAll
        self.onSelect = onSelect
    }

    private var television: Bool {
        false
    }
    public var body: some View {
        FeaturedMediaRowPresentation(
            title: title, isEmpty: items.isEmpty, isLoading: isLoading, usesRowBrowsing: usesRowBrowsing,
            onBrowse: onBrowse,
            onSeeAll: onSeeAll,
            selectedID: $selectedID, onSettled: { isSettled = $0 }
        ) { size in
            cards(size: size)
        }
        #if os(iOS)
        .environment(\.featuredArtworkSelection, { item, source in
            if let onSelectArtwork {
                onSelectArtwork(item, source)
            } else {
                onSelect(item)
            }
        })
        #endif
        .onGeometryChange(for: Int?.self) { geometry in
            let frame = geometry.frame(in: .scrollView(axis: .vertical))
            guard let bounds = geometry.bounds(of: .scrollView(axis: .vertical)),
                  frame.height > 0 else { return nil }
            let visible = max(0, min(frame.maxY, bounds.height) - max(frame.minY, 0))
            guard visible / frame.height >= 0.75 else { return nil }
            return Int(abs(frame.midY - bounds.height / 2) / 20)
        } action: { priority = $0 }
    }

    @ViewBuilder private func cards(size: CGSize) -> some View {
        ForEach(items, id: \.stablePresentationID) { item in
            FeaturedMediaCard(
                item: item, size: size, spoilers: spoilers,
                onFocus: { focused in
                    if focused {
                        focusedID = item.stablePresentationID
                        onFocus?(item)
                    } else if focusedID == item.stablePresentationID {
                        focusedID = nil
                    }
                },
                onSelect: {
                    onSelect(item)
                }
            )
            .id(item.stablePresentationID)
        }
    }
}

private struct FeaturedMediaCard: View {
    let item: MediaItem
    let size: CGSize
    let spoilers: SpoilerSettings
    let onFocus: (Bool) -> Void
    let onSelect: () -> Void
    #if os(iOS)
    @Environment(\.featuredArtworkSelection) private var artworkNavigator
    #endif

    var body: some View {
        FeaturedCardControl(
            item: item, size: size, spoilers: spoilers, onFocus: onFocus, onSelect: onSelect
        ) {
        }
        #if os(iOS)
        .artworkNavigation { source in
            if let artworkNavigator {
                artworkNavigator(item, source)
            } else {
                onSelect()
            }
        }
        #endif
    }
}
#endif
