import CoreModels
import CoreNetworking
import SwiftUI

private struct FamilyGuidanceProviderKey: EnvironmentKey {
    static let defaultValue: (any FamilyGuidanceLoading)? = nil
}

public extension EnvironmentValues {
    var familyGuidanceProvider: (any FamilyGuidanceLoading)? {
        get { self[FamilyGuidanceProviderKey.self] }
        set { self[FamilyGuidanceProviderKey.self] = newValue }
    }
}

struct FamilyGuidanceTile: View {
    let item: MediaItem
    let summary: FamilyGuidanceSummary
    @State private var isPresented = false
    @Environment(\.familyGuidanceProvider) private var provider
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ScaledMetric(relativeTo: .title2) private var scaledAgeSize: CGFloat = 30
    @ScaledMetric(relativeTo: .body) private var expandedMinimumWidth: CGFloat = 280
    #endif

    var body: some View {
        Button { isPresented = true } label: {
            ViewThatFits(in: .horizontal) {
                horizontalContent
                    .frame(minWidth: expandedContentWidth, idealWidth: expandedContentWidth)
                compactContent
            }
            .plozzForeground(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DetailInformationLayout.cellPadding)
        }
        .plozzCardButton(cornerRadius: DetailInformationLayout.cornerRadius,
                        focusedScale: PlozzTheme.Metrics.readOnlyFocusedCardScale)
        .accessibilityIdentifier("family-guidance-tile")
        .accessibilityHint("Open family guidance")
        .plozzSheet(isPresented: $isPresented) {
            FamilyGuidanceSheet(item: item, summary: summary, authorizationID: provider?.contextID)
        }
    }

    private var horizontalContent: some View {
        HStack(alignment: .center, spacing: 16) {
            FamilyGuidanceAge(age: summary.recommendedAge, size: ageSize)
            VStack(alignment: .leading, spacing: 6) {
                FamilyGuidanceBrand(compact: true)
                    .font(sourceFont)
                overview
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            disclosure
        }
    }

    private var compactContent: some View {
        VStack(spacing: 4) {
            HStack(spacing: compactIconSize / 2) {
                FamilyGuidanceIcon(size: compactIconSize)
                FamilyGuidanceAge(age: summary.recommendedAge, size: ageSize * (22.0 / 30))
            }
            .frame(minHeight: compactIconSize * 1.5)
            Text(verbatim: "Common Sense")
                .font(sourceFont)
                .plozzForeground(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .trailing) { disclosure }
    }

    private var expandedContentWidth: CGFloat {
        expandedMinimumWidth
    }

    private var compactIconSize: CGFloat {
        horizontalSizeClass == .compact ? 24 : 28
    }

    @ViewBuilder
    private var overview: some View {
        if let overview = summary.overview {
            Text(overview)
                .font(summaryFont)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .plozzForeground(.secondary)
        }
    }

    private var disclosure: some View {
        Image(systemName: "chevron.forward")
            .font(sourceFont)
            .plozzForeground(.secondary)
            .accessibilityHidden(true)
    }

    private var ageSize: CGFloat {
        scaledAgeSize
    }
    private var sourceFont: Font {
        .caption.weight(.semibold)
    }
    private var summaryFont: Font {
        .subheadline
    }
}

struct FamilyGuidanceSheet: View {
    let item: MediaItem
    let summary: FamilyGuidanceSummary
    let authorizationID: String?
    @Environment(\.familyGuidanceProvider) private var provider
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var state: LoadState<FamilyGuidanceAvailability> = .idle
    @State private var attempt = 0

    var body: some View {
        Group {
            if provider?.contextID == authorizationID {
                NavigationStack {
                    FamilyGuidanceMobileOverview(
                        title: item.title, summary: displayedSummary, state: state, retry: { attempt += 1 }
                    )
                    .navigationTitle("Family guidance")
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationDestination(for: FamilyGuidancePage.self) { page in
                        ScrollView {
                            FamilyGuidanceDetailContent(
                                page: page, summary: displayedSummary, state: state, retry: { attempt += 1 }
                            )
                            .padding(24)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .background { SettingsPageBackground() }
                    }
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { dismiss() }
                        }
                    }
                }
            }
        }
        .foregroundStyle(palette.primaryText)
        .task(id: attempt) { await load() }
        .onChange(of: provider?.contextID) { _, current in
            if current != authorizationID { dismiss() }
        }
    }

    private var displayedSummary: FamilyGuidanceSummary {
        guard let guidance = state.guidance else { return summary }
        return FamilyGuidanceSummary(
            recommendedAge: guidance.summary.recommendedAge ?? summary.recommendedAge,
            qualityRating: guidance.summary.qualityRating ?? summary.qualityRating,
            overview: guidance.summary.overview ?? summary.overview
        )
    }

    private func load() async {
        guard let provider else {
            state = .loaded(.unavailable)
            return
        }
        state = .loading
        do {
            let result = try await provider.loadFamilyGuidance(for: item)
            try Task.checkCancellation()
            guard provider.contextID == authorizationID else { return }
            state = .loaded(result)
        } catch is CancellationError {
            // The sheet or its profile no longer owns this request.
        } catch {
            guard !Task.isCancelled, provider.contextID == authorizationID else { return }
            PlozzLog.app.error("Family guidance could not be loaded")
            state = .failed((error as? AppError) ?? .invalidResponse)
        }
    }
}

enum FamilyGuidancePage: Hashable {
    case overview, topic(String), reviews, discussion

    static func pages(summary: FamilyGuidanceSummary, guidance: FamilyGuidance?) -> [Self] {
        var pages: [Self] = [.overview]
        pages += (guidance?.topics ?? []).map { .topic($0.id) }
        if summary.qualityRating != nil || !(guidance?.audienceRatings ?? []).isEmpty
            || guidance?.qualityOverview != nil {
            pages.append(.reviews)
        }
        if !(guidance?.talkingPoints ?? []).isEmpty { pages.append(.discussion) }
        return pages
    }

    func topic(in guidance: FamilyGuidance?) -> FamilyGuidance.Topic? {
        guard case .topic(let id) = self else { return nil }
        return guidance?.topics.first { $0.id == id }
    }
}

private extension LoadState where Value == FamilyGuidanceAvailability {
    var guidance: FamilyGuidance? {
        guard case .loaded(.available(let guidance)) = self else { return nil }
        return guidance
    }
}

private struct FamilyGuidanceMobileOverview: View {
    let title: String // l10n:content — media title supplied by the provider
    let summary: FamilyGuidanceSummary
    let state: LoadState<FamilyGuidanceAvailability>
    let retry: () -> Void
    @Environment(\.themePalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                FamilyGuidanceHeader(title: title, summary: summary)
                ForEach(FamilyGuidancePage.pages(summary: summary, guidance: state.guidance), id: \.self) { page in
                    NavigationLink(value: page) {
                        FamilyGuidanceMenuLabel(page: page, guidance: state.guidance)
                            .padding(18)
                    }
                    .plozzCardButton(cornerRadius: 16)
                }
                if state.guidance == nil {
                    FamilyGuidanceStatus(state: state, retry: retry)
                }
            }
            .padding(24)
        }
        .background { SettingsPageBackground() }
    }
}

private extension FamilyGuidancePage {
    var identifier: String {
        switch self {
        case .overview: "family-guidance-overview"
        case .topic(let id): "family-guidance-topic-\(id)"
        case .reviews: "family-guidance-reviews"
        case .discussion: "family-guidance-discussion"
        }
    }
}

private struct FamilyGuidanceAge: View {
    let age: Double?
    let size: CGFloat
    @Environment(\.locale) private var locale

    var body: some View {
        if let age {
            Text(verbatim: age.formatted(.number.locale(locale).precision(.fractionLength(0...1))) + "+")
                .font(.system(size: size, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityLabel("Recommended age: \(age, format: .number.precision(.fractionLength(0...1)))+")
        } else {
            Text("No age recommendation").font(.headline)
        }
    }
}

struct FamilyGuidanceHeader: View {
    let title: String // l10n:content — media title supplied by the provider
    let summary: FamilyGuidanceSummary
    @Environment(\.themePalette) private var palette
    #if os(iOS)
    @ScaledMetric(relativeTo: .largeTitle) private var scaledAgeSize: CGFloat = 60
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                FamilyGuidanceAge(age: summary.recommendedAge, size: ageSize)
                ageCaption
            }
            VStack(alignment: .leading, spacing: 10) {
                FamilyGuidanceHeaderIdentity(title: title)
                synopsis
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("family-guidance-header")
    }

    private var ageCaption: some View {
        Text("Recommended age").font(.caption)
            .foregroundStyle(palette.secondaryText)
    }

    @ViewBuilder
    private var synopsis: some View {
        if let overview = summary.overview {
            Text(overview)
                .font(summaryFont)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var ageSize: CGFloat {
        scaledAgeSize
    }
    private var summaryFont: Font {
        .body
    }
}

private struct FamilyGuidanceHeaderIdentity: View {
    let title: String // l10n:content — media title supplied by the provider
    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(titleFont).lineLimit(2)
            FamilyGuidanceBrand(compact: false)
                .font(brandFont)
                .foregroundStyle(palette.secondaryText)
        }
    }

    private var titleFont: Font {
        .headline
    }

    private var brandFont: Font {
        .subheadline.weight(.semibold)
    }
}

private struct FamilyGuidancePageLabel: View {
    let page: FamilyGuidancePage
    let guidance: FamilyGuidance?
    var isMenu = false

    var body: some View {
        switch page {
        case .overview:
            if isMenu { Text("Overview") } else { Text("What parents need to know") }
        case .topic:
            if let topic = page.topic(in: guidance) { Text(topic.label) }
        case .reviews: Text("Review scores")
        case .discussion: Text("Talk with your family")
        }
    }
}

private struct FamilyGuidanceMenuLabel: View {
    let page: FamilyGuidancePage
    let guidance: FamilyGuidance?

    var body: some View {
        HStack(spacing: 14) {
            FamilyGuidancePageLabel(page: page, guidance: guidance, isMenu: true)
                .font(labelFont)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let topic = page.topic(in: guidance) {
                FamilyGuidanceIntensity(value: topic.rating)
            }
        }
    }

    private var labelFont: Font {
        .body.weight(.medium)
    }
}

private struct FamilyGuidanceDetailContent: View {
    let page: FamilyGuidancePage
    let summary: FamilyGuidanceSummary
    let state: LoadState<FamilyGuidanceAvailability>
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            FamilyGuidancePageLabel(page: page, guidance: state.guidance)
                .font(.title2.bold())
            if page == .reviews {
                FamilyGuidanceReviewScores(summary: summary, guidance: state.guidance)
                if let overview = state.guidance?.qualityOverview { text(overview) }
            } else if let guidance = state.guidance {
                switch page {
                case .overview:
                    if let overview = guidance.parentsNeedToKnow {
                        text(overview)
                    } else {
                        Text("Select a content topic to read its explanation.")
                    }
                case .topic:
                    if let topic = page.topic(in: guidance) {
                        FamilyGuidanceIntensity(value: topic.rating)
                        if let explanation = topic.explanation {
                            text(explanation)
                        } else {
                            Text("No explanation was provided for this topic.")
                        }
                    }
                case .discussion:
                    text(guidance.talkingPoints.joined(separator: "\n\n"))
                case .reviews: EmptyView()
                }
            } else {
                FamilyGuidanceStatus(state: state, retry: retry)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func text(_ value: String) -> some View {
        Text(value).fixedSize(horizontal: false, vertical: true)
    }
}

private struct FamilyGuidanceStatus: View {
    let state: LoadState<FamilyGuidanceAvailability>
    let retry: () -> Void

    var body: some View {
        switch state {
        case .idle, .loading:
            ProgressView("Loading family guidance…")
        case .failed(let error):
            Text(error.userMessage)
            Button("Retry", action: retry).accessibilityIdentifier("family-guidance-retry")
        case .loaded(.restricted):
            Text("Detailed guidance requires Plex Pass access for the account viewing this title.")
        case .empty, .loaded(.unavailable):
            Text("Detailed guidance is not available for this title.")
        case .loaded(.available):
            EmptyView()
        }
    }
}

private struct FamilyGuidanceIntensity: View {
    let value: Double?
    @Environment(\.themePalette) private var palette

    var body: some View {
        if let value {
            HStack(spacing: 4) {
                ForEach(0..<5) { index in
                    Capsule().fill(palette.primaryText.opacity(Double(index) < value ? 0.85 : 0.15))
                        .frame(width: 13, height: 6)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Content level: \(value, format: .number.precision(.fractionLength(0...1))) out of 5")
        } else {
            Text("Not rated").font(.caption).foregroundStyle(palette.secondaryText)
        }
    }
}

private struct FamilyGuidanceReviewScores: View {
    let summary: FamilyGuidanceSummary
    let guidance: FamilyGuidance?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Quality ratings, not age recommendations")
                .font(.subheadline)
                .plozzForeground(.secondary)
            HStack {
                Text(verbatim: "Common Sense Media")
                Spacer()
                FamilyGuidanceStars(value: summary.qualityRating)
            }
            ForEach((guidance?.audienceRatings ?? []).filter { $0.audience != .official }) { rating in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        if rating.audience == .parents { Text("Parents’ rating") } else { Text("Kids’ rating") }
                        Spacer()
                        FamilyGuidanceStars(value: rating.qualityRating)
                    }
                    if let age = rating.recommendedAge {
                        Text("Average recommended age: \(age, format: .number.precision(.fractionLength(0...1)))+")
                            .font(.caption)
                            .plozzForeground(.secondary)
                    }
                }
            }
        }
    }
}

private struct FamilyGuidanceStars: View {
    let value: Double?

    var body: some View {
        if let value {
            HStack(spacing: 5) {
                ForEach(0..<5) { index in
                    Image(systemName: value >= Double(index) + 0.75 ? "star.fill" :
                            value >= Double(index) + 0.25 ? "star.leadinghalf.filled" : "star")
                }
            }
            .font(.subheadline)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Quality rating: \(value, format: .number.precision(.fractionLength(0...1))) out of 5")
        } else {
            Text("Not rated").font(.caption).plozzForeground(.secondary)
        }
    }
}


private struct FamilyGuidanceBrand: View {
    let compact: Bool

    var body: some View {
        HStack(spacing: 8) {
            FamilyGuidanceIcon(size: 32)
            Text(verbatim: compact ? "Common Sense" : "Common Sense Media")
        }
    }
}

struct FamilyGuidanceIcon: View {
    let size: CGFloat
    @Environment(\.themePalette) private var palette

    var body: some View {
        Image(palette.isLight ? "CommonSenseMediaOnLight" : "CommonSenseMedia", bundle: .module)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
