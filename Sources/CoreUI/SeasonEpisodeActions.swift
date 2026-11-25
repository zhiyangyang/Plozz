import CoreModels
import SwiftUI

public struct SeasonEpisodeCoverageHeader: View {
    private let coverage: SeasonEpisodeCoverage?
    private let isLoading: Bool
    private let hasNumberingConflict: Bool

    public init(coverage: SeasonEpisodeCoverage?, isLoading: Bool, hasNumberingConflict: Bool) {
        self.coverage = coverage
        self.isLoading = isLoading
        self.hasNumberingConflict = hasNumberingConflict
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let coverage {
                Text(coverage.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                if coverage.missing > 0 && coverage.unaired > 0 {
                    Text("\(coverage.missing) missing, \(coverage.unaired) not yet released")
                } else if coverage.missing > 0 {
                    Text("\(coverage.missing) missing from your library")
                } else if coverage.unaired > 0 {
                    Text("\(coverage.unaired) not yet released")
                }
            } else if isLoading {
                Text("Checking episode availability…")
            } else if hasNumberingConflict {
                Text("Episode numbering differs. Showing library episodes without a coverage count.")
            } else {
                Text("Library episodes")
            }
        }
        .font(.caption)
        .foregroundStyle(Color.secondary)
        .lineLimit(nil)
        .fixedSize(horizontal: false, vertical: true)
        .textCase(nil)
        .accessibilityElement(children: .combine)
    }
}
