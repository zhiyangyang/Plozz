#if canImport(SwiftUI)
import CoreModels
import CoreUI
import SwiftUI


/// The added sources this profile watches, independent of library discovery.
public struct SettingsLibrarySourcesSummary: View {
    private let accounts: [Account]
    private let isAccountIncluded: (String) -> Bool

    public init(accounts: [Account], isAccountIncluded: @escaping (String) -> Bool) {
        self.accounts = accounts
        self.isAccountIncluded = isAccountIncluded
    }

    public var body: some View {
        let groups = Self.watchedServerGroups(in: accounts, isAccountIncluded: isAccountIncluded)
        if accounts.isEmpty {
            Text("No servers yet")
        } else if groups.isEmpty {
            Text("Choose what to watch")
        } else {
            ViewThatFits(in: .horizontal) {
                if groups.count >= 3 {
                    MobileLibrarySourcesStrip(groups: groups, visibleCount: 3)
                        .fixedSize(horizontal: true, vertical: false)
                }
                if groups.count >= 2 {
                    MobileLibrarySourcesStrip(groups: groups, visibleCount: 2)
                        .fixedSize(horizontal: true, vertical: false)
                }
                MobileLibrarySourcesStrip(groups: groups, visibleCount: 1)
                    .fixedSize(horizontal: true, vertical: false)
                MobileLibrarySourcesStrip(groups: groups, visibleCount: 1, compactOverflow: true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    static func watchedServerGroups(
        in accounts: [Account], isAccountIncluded: (String) -> Bool
    ) -> [ServerAccountGroup] {
        serverGroups(from: accounts).filter { group in
            group.accounts.contains { isAccountIncluded($0.id) }
        }
    }
}

private struct MobileLibrarySourcesStrip: View {
    let groups: [ServerAccountGroup]
    let visibleCount: Int
    var compactOverflow = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(groups.prefix(visibleCount).enumerated()), id: \.element.serverKey) { index, group in
                if index > 0 { Text(verbatim: "·") }
                HStack(spacing: 6) {
                    ProviderIcon(
                        provider: group.providerKind, size: 16,
                        mediaShareTransport: group.transportKind
                    )
                    .accessibilityHidden(true)
                    Text(verbatim: group.serverName)
                }
            }
            if groups.count > visibleCount {
                Group {
                    if compactOverflow {
                        Text("+\(groups.count - visibleCount)")
                            .accessibilityLabel(Text("+\(groups.count - visibleCount) more"))
                    } else {
                        Text("· +\(groups.count - visibleCount) more")
                    }
                }
                .fixedSize()
            }
        }
        .lineLimit(1)
    }
}
#endif
