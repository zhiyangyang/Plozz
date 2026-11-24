import CoreModels
import CoreUI
import SwiftUI

public struct SettingsSearchResults: View {
    let query: String
    let platform: SettingsSearchEntry.Platform
    let isKids: Bool
    let featureFlags: RuntimeFeatureFlags
    let onSelect: (SettingsSearchEntry, UUID?) -> Void
    @Environment(\.locale) private var locale

    public init(
        query: String, platform: SettingsSearchEntry.Platform, isKids: Bool = false,
        featureFlags: RuntimeFeatureFlags = .buildDefault,
        onSelect: @escaping (SettingsSearchEntry, UUID?) -> Void
    ) {
        self.query = query
        self.platform = platform
        self.isKids = isKids
        self.featureFlags = featureFlags
        self.onSelect = onSelect
    }
    private var isEmptyQuery: Bool { query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var results: [SettingsSearchEntry] {
        let available = SettingsSearchCatalog.entries(on: platform, isKids: isKids, featureFlags: featureFlags)
        if isEmptyQuery {
            let suggestions = ["subtitle-size", "theme", "autoplay-next-episode", "resume-rewind", "display-size"]
            return suggestions.compactMap { id in available.first { $0.id == id } }
        }
        return SettingsSearchIndex(entries: available, locale: locale).results(for: query)
    }

    public var body: some View {
        if results.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            List {
                if isEmptyQuery {
                    Text("Suggestions").font(.headline).foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                ForEach(results) { entry in
                    Button { onSelect(entry, nil) } label: {
                        resultLabel(entry)
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("settings-search-result-\(entry.id)")
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.vertical, 0, for: .scrollContent)
            .accessibilityIdentifier("settings-search-results")
        }
    }

    private func resultLabel(_ entry: SettingsSearchEntry) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                title(entry.title).font(.body)
                Text(verbatim: entry.destinationPath(on: platform).map {
                    $0.resolved(locale: locale)
                }.joined(separator: " › "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
        } icon: {
            Image(systemName: entry.page.symbol)
        }
        .contentShape(Rectangle())
    }

    private func title(_ label: SettingsSearchLabel) -> Text {
        switch label {
        case .localized(let resource): Text(resource)
        case .verbatim(let value): Text(verbatim: value)
        }
    }
}
