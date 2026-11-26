#if os(iOS)
import AppRuntime
import CoreModels
import CoreUI
import FeatureSettings
import Foundation
import SwiftUI

struct PlozziOSFirstRunView: View {
    /// Optional so the view can hold the last real step on screen while the cover
    /// dismisses — otherwise the final step would blank out before the animation
    /// finished, flashing Home.
    let step: PlozziOSAppModel.FirstRunStep?
    let appModel: PlozziOSAppModel
    let systemColorScheme: ColorScheme

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedStep: PlozziOSAppModel.FirstRunStep
    @State private var direction: OnboardingNavigationDirection = .forward
    /// The Plex-user step clears the model's selection before the next step is
    /// scheduled, so hold the last real payload to render from. Without it the
    /// step blanks for a frame mid-transition.
    @State private var lastPlexSelection: PlexHomeUsersModel.PendingPlexUserSelection?

    init(
        step: PlozziOSAppModel.FirstRunStep?,
        appModel: PlozziOSAppModel,
        systemColorScheme: ColorScheme
    ) {
        self.step = step
        self.appModel = appModel
        self.systemColorScheme = systemColorScheme
        _displayedStep = State(initialValue: step ?? .theme)
    }

    var body: some View {
        ZStack {
            stepContent
                .id(displayedStep)
                .geometryGroup()
                // Same motion the tvOS onboarding flow uses, so the two
                // platforms move alike and honour Reduce Motion the same way.
                .transition(
                    OnboardingPageMotion.transition(
                        direction: direction,
                        reduceMotion: reduceMotion
                    )
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: step) { _, newStep in
            // nil means the flow finished; keep the current screen rendered so
            // the cover slides away over it rather than over an empty view.
            guard let newStep, newStep != displayedStep else { return }
            direction = newStep.order >= displayedStep.order ? .forward : .backward
            withAnimation(OnboardingPageMotion.animation(reduceMotion: reduceMotion)) {
                displayedStep = newStep
            }
        }
        .onChange(of: appModel.plexHomeUsers.pendingPlexUserSelection) { _, selection in
            if let selection { lastPlexSelection = selection }
        }
        .task {
            lastPlexSelection = appModel.plexHomeUsers.pendingPlexUserSelection
        }
        .scrollContentBackground(.hidden)
        .background { AppBackground(palette: palette) }
        .offlineStatusOverlay(appModel: appModel, palette: palette)
        .environment(\.themePalette, palette)
        .environment(\.colorScheme, palette.isLight ? .light : .dark)
        .toolbarBackground(.hidden, for: .navigationBar)
        .interactiveDismissDisabled()
    }

    @ViewBuilder
    private var stepContent: some View {
        switch displayedStep {
        case .plexUser:
            if let selection = appModel.plexHomeUsers.pendingPlexUserSelection
                ?? lastPlexSelection {
                PlozziOSPlexUserSelectionView(
                    appModel: appModel,
                    selection: selection,
                    onSelect: appModel.selectPlexUserDuringOnboarding
                )
            }
        case .libraries:
            if let selection = appModel.pendingLibrarySelection {
                PlozziOSLibrarySelectionView(
                    appModel: appModel, accountIDs: selection.accountIDs
                )
            }
        case .theme:
            NavigationStack {
                PlozziOSThemeWelcomeView(
                    appModel: appModel,
                    onContinue: appModel.finishFirstRunThemeSelection
                )
            }
        }
    }

    private var palette: ThemePalette {
        ThemePalette.palette(
            for: appModel.settings.theme.theme,
            systemColorScheme: systemColorScheme
        )
    }
}

/// The per-profile theme picker.
///
/// Shared by first run and by new-profile setup rather than duplicated: the
/// theme is a per-profile setting, so every new profile gets asked, not just the
/// first one. Only what happens on Continue differs, so only that is injected.
struct PlozziOSThemeWelcomeView: View {
    let appModel: PlozziOSAppModel
    let onContinue: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 10) {
                        Text("Choose Your Look")
                            .font(.largeTitle.bold())
                        Text("Pick a theme for this profile. You can change it any time.")
                            .plozzForeground(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 150), spacing: 14)],
                        spacing: 14
                    ) {
                        ForEach(AppTheme.pickerOrder) { theme in
                            Button {
                                appModel.settings.theme.theme = theme
                            } label: {
                                VStack(spacing: 14) {
                                    Image(systemName: theme.symbolName)
                                        .font(.system(size: 32, weight: .semibold))
                                    Text(theme.displayName)
                                        .font(.headline)
                                }
                                .frame(maxWidth: .infinity, minHeight: 120)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 18)
                                        .stroke(
                                            appModel.settings.theme.theme == theme
                                                ? Color.accentColor
                                                : Color.secondary.opacity(0.2),
                                            lineWidth: appModel.settings.theme.theme == theme ? 3 : 1
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(
                                appModel.settings.theme.theme == theme ? .isSelected : []
                            )
                        }
                    }

                    Button(action: onContinue) {
                        Text("Continue").plozzPageActionLabel()
                    }
                    .plozzPageActionButton()
                }
                .frame(maxWidth: 720)
                .padding(.horizontal, 24)
                .padding(.vertical, 48)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .navigationTitle("Appearance")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#endif
