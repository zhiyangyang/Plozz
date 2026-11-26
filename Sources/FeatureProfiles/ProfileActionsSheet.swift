#if canImport(SwiftUI)
import CoreModels
import CoreUI
import SwiftUI

/// The sheet the picker's Edit button opens.
public struct ProfileActionsSheet: View {
    private let profile: Profile
    private let onEditAppearance: () -> Void
    private let onDelete: (() -> Void)?
    private let onClose: () -> Void

    public init(
        profile: Profile,
        onEditAppearance: @escaping () -> Void,
        onDelete: (() -> Void)? = nil,
        onClose: @escaping () -> Void
    ) {
        self.profile = profile
        self.onEditAppearance = onEditAppearance
        self.onDelete = onDelete
        self.onClose = onClose
    }

    @Environment(\.themePalette) private var palette

    public var body: some View {
        ZStack {
            AppBackground(palette: palette).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    ProfileActionsList(
                        profile: profile,
                        onEditAppearance: onEditAppearance,
                        onDelete: onDelete
                    )
                }
                .frame(maxWidth: 1000, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 60)
                .padding(.vertical, 60)
            }
            .scrollClipDisabled()
        }
        .environment(\.colorScheme, palette.isLight ? .light : .dark)
    }

    private var header: some View {
        HStack(spacing: 24) {
            ProfileAvatarView(profile: profile, size: 120)
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: profile.name)
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
            }
            Spacer()
            Button("Done", action: onClose)
                .buttonStyle(.borderedProminent)
        }
    }
}
#endif
