#if canImport(SwiftUI)
import CoreModels
import CoreUI
import SwiftUI

public enum HeroSettingsPage: String, CaseIterable {
    case titles, ratings, libraries, collections

    var title: LocalizedStringResource {
        switch self {
        case .titles:
            "Hero content sources"
        case .ratings: "Ratings"
        case .libraries: "Random libraries"
        case .collections: "Collections"
        }
    }

    var linkTitle: LocalizedStringResource {
        switch self {
        case .titles, .ratings: title
        case .libraries: "Choose libraries"
        case .collections: "Choose collections"
        }
    }

    var initialRowID: String {
        switch self {
        case .titles: "hero-source-continueWatching"
        case .ratings: "hero-ratings"
        case .libraries: "hero-all-libraries"
        case .collections: "hero-collection-done"
        }
    }
}

/// Shared controls keep TV and mobile terminology, grouping and Kids policy aligned.
public struct HeroSettingsControls: View {
    private let libraries: [AggregatedLibrary]
    private let accounts: [ResolvedAccount]
    @Environment(HeroSettingsModel.self) private var hero

    public init(libraries: [AggregatedLibrary], accounts: [ResolvedAccount]) {
        self.libraries = libraries
        self.accounts = accounts
    }

    public var body: some View {
        @Bindable var hero = hero
        HeroSettingsGroup(searchTargets: ["hero-enabled"] + enableTargets) {
            Toggle("Show hero", isOn: $hero.settings.isEnabled)
                .accessibilityIdentifier("hero-enabled")
                .settingsSearchAnchor("hero-enabled", fallbackFor: enableTargets)
        }
        if showsControls {
            HeroSettingsGroup {
                HeroLogoSizeControl(size: $hero.settings.logoSize, textSize: $hero.settings.textSize, surface: .home)
            }
            HeroTitleControls(libraries: libraries, accounts: accounts)
            HeroAutomaticChangeControls()
            HeroSettingsGroup {
                HeroSettingsLink(page: .ratings, libraries: libraries, accounts: accounts)
                }
        }
    }

    private var showsControls: Bool {
        hero.settings.isEnabled
    }

    private var enableTargets: [String] {
        showsControls ? [] : SettingsSearchCatalog.carouselHeroTargets
    }
}

private struct HeroTitleControls: View {
    let libraries: [AggregatedLibrary]
    let accounts: [ResolvedAccount]
    @Environment(HeroSettingsModel.self) private var hero

    var body: some View {
        @Bindable var hero = hero
        HeroSettingsGroup(title: "Content", searchTargets: ["hero-content", "hero-items"]) {
            HeroSettingsLink(page: .titles, libraries: libraries, accounts: accounts)
            Stepper("Items to show: \(hero.settings.maxItems)",
                    value: $hero.settings.maxItems, in: HeroSettings.maxItemsRange)
                .settingsSearchAnchor("hero-items")
        }
    }
}

private struct HeroAutomaticChangeControls: View {
    @Environment(HeroSettingsModel.self) private var hero

    var body: some View {
        @Bindable var hero = hero
        HeroSettingsGroup(searchTargets: ["hero-auto-advance", "hero-advance-seconds"]) {
            Toggle("Advance automatically", isOn: $hero.settings.autoAdvance)
                .accessibilityIdentifier("hero-auto-advance")
                .settingsSearchAnchor(
                    "hero-auto-advance", fallbackFor: hero.settings.autoAdvance ? [] : ["hero-advance-seconds"]
                )
            if hero.settings.autoAdvance {
                Stepper("Seconds per item: \(hero.settings.autoAdvanceSeconds)",
                        value: $hero.settings.autoAdvanceSeconds, in: HeroSettings.autoAdvanceRange)
                    .settingsSearchAnchor("hero-advance-seconds")
            }
        }
    }
}

struct HeroRatingControls: View {
    var isShowcase = false
    @Environment(HeroSettingsModel.self) private var hero

    var body: some View {
        @Bindable var hero = hero
        HeroSettingsGroup(searchTargets: isShowcase
            ? ["showcase-ratings", "showcase-age", "showcase-rating-count"]
            : SettingsSearchCatalog.targets(on: .heroRatings)) {
            Toggle("Show ratings", isOn: $hero.settings.showsRatings)
                .accessibilityIdentifier("hero-ratings")
                .modifier(ViewCustomizationRowFocus(id: "hero-ratings"))
                .settingsSearchAnchor(
                    isShowcase ? "showcase-ratings" : "hero-ratings",
                    fallbackFor: hero.settings.showsRatings ? []
                        : (isShowcase ? ["showcase-age", "showcase-rating-count"] : ["hero-age", "hero-rating-count"])
                )
            if hero.settings.showsRatings {
                Toggle("Show Common Sense age", isOn: $hero.settings.ratingPreferences.showsHeaderFamilyGuidance)
                    .accessibilityIdentifier("hero-common-sense-age")
                    .settingsSearchAnchor(isShowcase ? "showcase-age" : "hero-age")
                HeaderReviewScoreCountPicker(settings: $hero.settings.ratingPreferences)
                    .settingsSearchAnchor(isShowcase ? "showcase-rating-count" : "hero-rating-count")
            }
        }
    }
}

struct HeroSettingsLink: View {
    let page: HeroSettingsPage
    let libraries: [AggregatedLibrary]
    let accounts: [ResolvedAccount]
    @Environment(HeroSettingsModel.self) private var hero
    #if os(iOS)
    @State private var isPresented = false
    #endif

    var body: some View {
        Group {
            #if os(iOS)
            Button {
                isPresented = true
            } label: {
                label
            }
            .settingsActionRow()
            .navigationDestination(isPresented: $isPresented) {
                HeroSettingsScreen(page: page, libraries: libraries, accounts: accounts)
                    .environment(hero)
            }
            #else
            SettingsDetailLink(pageID: page.rawValue) {
                HeroSettingsScreen(page: page, libraries: libraries, accounts: accounts)
            } label: {
                label
            }
            #endif
        }
        .accessibilityIdentifier("hero-settings-\(page.rawValue)")
        .modifier(ViewCustomizationRowFocus(id: "hero-settings-\(page.rawValue)"))
        .settingsSearchAnchor(searchID)
    }

    private var searchID: String {
        switch page {
        case .titles: "hero-content"
        case .libraries: "hero-choose-libraries"
        case .collections: "hero-choose-collections"
        default: "hero-settings-\(page.rawValue)"
        }
    }

    private var label: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(page.linkTitle)
                    .font(SettingsRowMetrics.titleFont)
                if page == .titles {
                    HeroTitleSourceSummary(sources: hero.settings.sources)
                        .font(.footnote)
                        .settingsRowSecondary()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 16)
            if let enabledState {
                Group {
                    if enabledState { Text("On") }
                    else { Text("Off") }
                }
                .settingsRowSecondary()
            }
            Image(systemName: "chevron.forward")
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }

    private var enabledState: Bool? {
        switch page {
        case .ratings: hero.settings.showsRatings
        default: nil
        }
    }
}

private struct HeroTitleSourceSummary: View {
    let sources: [HeroSourceKind]
    @Environment(\.locale) private var locale

    var body: some View {
        if sources.isEmpty {
            Text("No content sources selected")
        } else {
            Text(sources.map { source in
                var title = source.displayName
                title.locale = locale
                return String(localized: title) // l10n:content - Foundation list boundary; resolved from the environment locale on every body update.
            }, format: .list(type: .and).locale(locale))
        }
    }
}

struct HeroSettingsDestination: View {
    let libraries: [AggregatedLibrary]
    let accounts: [ResolvedAccount]
    @Environment(SettingsDetailNavigation.self) private var navigation

    var body: some View {
        if let page = navigation.pageID.flatMap(HeroSettingsPage.init(rawValue:)) {
            HeroSettingsScreen(page: page, libraries: libraries, accounts: accounts)
        }
    }
}

struct HeroSettingsScreen: View {
    let page: HeroSettingsPage
    let libraries: [AggregatedLibrary]
    let accounts: [ResolvedAccount]
    @Environment(HeroSettingsModel.self) private var hero
    @Environment(SettingsDetailNavigation.self) private var parentNavigation: SettingsDetailNavigation?
    @State var childNavigation = SettingsDetailNavigation()

    var body: some View {
        @Bindable var hero = hero
        if page == .collections {
            HeroCollectionPickerView(selections: $hero.settings.collections, libraries: libraries, accounts: accounts)
        } else {
            ViewCustomizationList(title: page.title, initialRowID: initialRowID) {
                form
            }
        }
    }

    private var initialRowID: String {
        if page == .libraries && eligibleLibraries.isEmpty { return "view-customization-back" }
        return page.initialRowID
    }

    @ViewBuilder private var form: some View {
        switch page {
        case .titles: HeroTitleSources(libraries: libraries, accounts: accounts)
        case .ratings: HeroRatingControls()
        case .libraries: randomLibraries
        case .collections: EmptyView()
        }
    }

    private var eligibleLibraries: [AggregatedLibrary] {
        libraries.filter { $0.library.kind == .movie || $0.library.kind == .series }
    }

    private var randomLibraries: some View {
        @Bindable var hero = hero
        return HeroSettingsGroup(
            detail: "Choose at least one library. All libraries includes new libraries added to Home.",
            searchTargets: ["hero-all-libraries"]
        ) {
            if eligibleLibraries.isEmpty {
                Text("No movie or TV libraries are enabled on Home.")
            } else {
                Toggle("All libraries on Home", isOn: Binding(
                    get: { hero.settings.randomLibraryKeys.isEmpty },
                    set: { all in hero.settings.randomLibraryKeys = all ? [] : Set(eligibleLibraries.map(\.key)) }
                ))
                .modifier(ViewCustomizationRowFocus(id: "hero-all-libraries"))
                .settingsSearchAnchor("hero-all-libraries")
                if !hero.settings.randomLibraryKeys.isEmpty {
                    ForEach(eligibleLibraries) { library in
                        Toggle(isOn: Binding(
                            get: { hero.settings.randomLibraryKeys.contains(library.key) },
                            set: { selected in
                                if selected { hero.settings.randomLibraryKeys.insert(library.key) }
                                else { hero.settings.randomLibraryKeys.remove(library.key) }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 4) {
                                library.library.displayName
                                Text(verbatim: library.serverName).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .disabled(hero.settings.randomLibraryKeys == [library.key])
                    }
                }
            }
        }
    }

}

private struct HeroTitleSources: View {
    let libraries: [AggregatedLibrary]
    let accounts: [ResolvedAccount]
    @Environment(HeroSettingsModel.self) private var hero

    var body: some View {
        @Bindable var hero = hero
        ForEach(HeroSourceKind.allCases) { source in
            ViewPreferenceChoiceGroup(rowSize: .contained) {
                Toggle(source.displayName, isOn: sourceBinding(source))
                    .modifier(ViewCustomizationRowFocus(id: "hero-source-\(source.rawValue)"))
                    .settingsSearchAnchor(
                        "hero-source-\(source.rawValue)",
                        fallbackFor: hero.settings.isEnabled(source) ? [] : dependentTargets(for: source)
                    )
                if hero.settings.isEnabled(source) {
                    switch source {
                    case .randomFromLibrary:
                        HeroSettingsLink(page: .libraries, libraries: libraries, accounts: accounts)
                    case .collection:
                        HeroSettingsLink(page: .collections, libraries: libraries, accounts: accounts)
                    case .watchlist, .continueWatching, .recentlyAdded:
                        EmptyView()
                    }
                }
            }
            .settingsSearchGroup(["hero-source-\(source.rawValue)"] + dependentTargets(for: source))
        }
    }

    private func sourceBinding(_ source: HeroSourceKind) -> Binding<Bool> {
        Binding(
            get: { hero.settings.isEnabled(source) },
            set: { selected in
                hero.settings.setEnabled(source, enabled: selected)
            }
        )
    }

    private func dependentTargets(for source: HeroSourceKind) -> [String] {
        switch source {
        case .randomFromLibrary: return ["hero-choose-libraries"] + SettingsSearchCatalog.targets(on: .heroLibraries)
        case .collection: return ["hero-choose-collections"] + SettingsSearchCatalog.targets(on: .heroCollections)
        default: return []
        }
    }
}

private struct HeroSettingsGroup<Content: View>: View {
    var title: LocalizedStringResource? = nil
    var detail: LocalizedStringResource? = nil
    var searchTargets: [String] = []
    @ViewBuilder var content: () -> Content

    var body: some View {
        SettingsSectionGroup(title, content: content) {
            if let detail { Text(detail) }
        }
        .settingsSearchGroup(searchTargets)
    }
}
#endif
