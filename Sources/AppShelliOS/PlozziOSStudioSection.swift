#if os(iOS)
import CoreModels
import CoreUI
import SwiftUI

/// Tappable studio chips on a movie detail page.
///
/// Deliberately quieter than a media rail: the heading uses normal section text
/// weight and the chips are text-only, with a lighter capsule fill.
struct PlozziOSStudioSection: View {
    @Environment(\.themePalette) private var palette

    let title: Text
    let terms: [MovieCatalogTerm]
    let inset: CGFloat
    let onSelect: (MovieCatalogTerm) -> Void

    var body: some View {
        if !uniqueTerms.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                title
                    .font(PlozziOSMediaRailLayout.headingFont)
                    .foregroundStyle(palette.primaryText)
                    .padding(.horizontal, inset)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(uniqueTerms) { term in
                            Button {
                                onSelect(term)
                            } label: {
                                Text(term.name)
                                    .font(.subheadline)
                                    .foregroundStyle(palette.primaryText)
                                    .lineLimit(1)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(
                                        palette.fill.opacity(0.55),
                                        in: Capsule()
                                    )
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .contentMargins(.horizontal, inset, for: .scrollContent)
                .scrollIndicators(.hidden)
            }
            .accessibilityIdentifier("detail-studio-section")
        }
    }

    private var uniqueTerms: [MovieCatalogTerm] {
        var seen = Set<String>()
        return terms.compactMap { term in
            let trimmed = term.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = trimmed.folding(
                options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seen.insert(key).inserted else { return nil }
            return term
        }
    }
}
#endif
