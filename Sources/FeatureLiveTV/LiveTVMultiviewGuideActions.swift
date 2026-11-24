import CoreUI
import FeatureLiveTVCore
import SwiftUI

enum LiveTVMultiviewSelection: Equatable {
    case add
    case replace(UUID)

    var title: LocalizedStringResource {
        switch self {
        case .add: "Add channel to Multiview"
        case .replace: "Replace channel in Multiview"
        }
    }

    @MainActor
    func apply(_ channel: LiveTVPrototypeChannel, to coordinator: LiveTVMultiviewCoordinator) {
        switch self {
        case .add: coordinator.add(channel)
        case .replace(let id): coordinator.replace(id, with: channel)
        }
    }
}

struct LiveTVMultiviewGuideSelectionHeader: View {
    let selection: LiveTVMultiviewSelection
    let cancel: () -> Void

    var body: some View {
        HStack {
            Text(selection.title)
                .font(.callout.weight(.semibold))
                .accessibilityIdentifier("live-multiview-guide-selection")
            Spacer()
            Button("Cancel", systemImage: "xmark", action: cancel)
                .buttonStyle(PrototypeButtonStyle(surface: .control))
                .accessibilityIdentifier("live-multiview-cancel-selection")
        }
    }
}

struct LiveTVMultiviewGuideExit: ViewModifier {
    let cancel: (() -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        content
    }
}

struct LiveTVMultiviewFavoritesView: View {
    let model: LiveTVPrototypeModel
    let open: (LiveTVMultiviewFavorite) -> Void
    var isPortrait = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette
    @ScaledMetric(relativeTo: .title2) private var titleSize: CGFloat = 30
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 24
    @ScaledMetric(relativeTo: .caption) private var detailSize: CGFloat = 22

    var body: some View {
        LiveTVSettingsPage(title: "Favorite Multiviews") {
            favoritesContent
        }
    }

    @ViewBuilder
    private var favoritesContent: some View {
        if model.favoriteMultiviews.isEmpty {
            ContentUnavailableView(
                "No favorite Multiviews", systemImage: "star",
                description: Text("Favorite a Multiview to open its channels and layout here."))
        } else {
            SettingsSectionGroup {
                ForEach(model.favoriteMultiviews) { favorite in
                    Button {
                        open(favorite)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(favorite.name).lineLimit(2)
                            HStack {
                                Text("\(favorite.channelIDs.count) channels")
                                Text(favorite.layout.title(count: favorite.channelIDs.count, isPortrait: isPortrait))
                            }
                            .font(.caption)
                            .settingsRowSecondary()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(SettingsFocusButtonStyle(size: .contained))
                    .accessibilityIdentifier("live-multiview-saved-\(favorite.id)")
                    .contextMenu {
                        Button("Remove from Favorites", systemImage: "star.slash") {
                            if model.removeMultiviewFavorite(favorite.id) { TouchFeedback.shared.emit(.confirmation) }
                        }
                    }
                }
            }
        }
        if model.preferencesIssue != nil {
            SettingsSectionGroup {
                Text("Multiview favorites could not be loaded or saved. Retry to keep your changes.")
                HStack {
                    Button("Retry", action: model.retryPreferences)
                        .plozzActionButton(role: .secondary)
                }
                .accessibilityElement(children: .contain)
            }
        }
    }
}
