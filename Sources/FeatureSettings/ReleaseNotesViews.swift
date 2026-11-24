#if canImport(SwiftUI)
import CoreModels
import CoreUI
import SwiftUI

public struct ReleaseNotesSettingsView: View {
    private let model: ReleaseNotesModel

    public init(model: ReleaseNotesModel) {
        self.model = model
    }

    public var body: some View {
        List {
            ReleaseNotesStartupPreferenceView(model: model)

            ForEach(model.allVersionGroups) { group in
                SettingsSectionGroup(verbatim: group.version) {
                    ReleaseNotesSectionsView(sections: group.sections)
                }
            }
        }
        .settingsPageSurface()
        .navigationTitle("Release Notes")
    }
}

public struct ReleaseNotesStartupView: View {
    private enum FocusedAction: Hashable {
        case done
    }

    private let model: ReleaseNotesModel
    @State private var confirmsDisable = false
    @FocusState private var focusedAction: FocusedAction?

    public init(model: ReleaseNotesModel) {
        self.model = model
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    featuredContent
                    ReleaseNotesVersionList(groups: model.pendingVersionGroups)

                    Button("Don’t Show Again", role: .destructive) {
                        confirmsDisable = true
                    }
                    .buttonStyle(.bordered)
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
            }
            .navigationTitle("What’s New in Plozz")
            #if os(iOS)
            .toolbarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        model.dismissStartupNotes()
                    }
                }
            }
        }
        .alert("Don’t show release notes again?", isPresented: $confirmsDisable) {
            Button("Don’t Show Again", role: .destructive) {
                model.setShowsOnStartup(false)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can still view every release in Settings.")
        }
    }

    @ViewBuilder
    private var featuredContent: some View {
        switch model.pendingFeaturedContent {
        case .discord:
            SettingsPanel {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsCommunityLogo(brand: .discord, height: 32)
                    Text("Join the new Discord community")
                        .font(.subheadline)
                        .plozzForeground(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Link(destination: AppLinks.discord) {
                        Text("Join Discord")
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .plozzActionButton()
                    .accessibilityIdentifier("ReleaseNotes.DiscordButton")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("ReleaseNotes.DiscordCard")
        case nil:
            EmptyView()
        }
    }
}

private struct ReleaseNotesStartupPreferenceView: View {
    let model: ReleaseNotesModel

    var body: some View {
        SettingsSectionGroup("Startup") {
            ReleaseNotesPreferenceToggle(model: model)
        }
    }
}

private struct ReleaseNotesPreferenceToggle: View {
    let model: ReleaseNotesModel

    var body: some View {
        Toggle(
            "Show release notes on startup for new versions",
            isOn: Binding(
                get: { model.showsOnStartup },
                set: { model.setShowsOnStartup($0) }
            )
        )
        .settingsSearchAnchor("release-notes-startup")
    }
}

private struct ReleaseNotesVersionList: View {
    let groups: [ReleaseNotesVersionGroup]

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 28) {
            ForEach(groups) { group in
                ReleaseNotesVersionCard(group: group)
            }
        }
    }
}

private struct ReleaseNotesVersionCard: View {
    let group: ReleaseNotesVersionGroup

    var body: some View {
        ReleaseNotesVersionContent(group: group)
            .plozzSurface(
                .raised,
                cornerRadius: PlozzTheme.Metrics.mediumCardCornerRadius
            )
    }
}

private struct ReleaseNotesVersionContent: View {
    let group: ReleaseNotesVersionGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(verbatim: group.version)
                .font(.title2.bold())
            ReleaseNotesSectionsView(sections: group.sections)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(28)
    }
}

private struct ReleaseNotesSectionsView: View {
    let sections: [ReleaseNotesSection]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(sections) { section in
                ReleaseNotesSectionView(section: section)
            }
        }
    }
}

private struct ReleaseNotesSectionView: View {
    let section: ReleaseNotesSection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: section.category.rawValue)
                .font(.headline)
            ForEach(section.items) { item in
                ReleaseNotesBullet(item: item.text)
            }
        }
    }

}

private struct ReleaseNotesBullet: View {
    let item: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: "•")
            Text(verbatim: item)
                .fixedSize(horizontal: false, vertical: true)
        }
        .plozzForeground(.secondary)
    }
}

#endif
