#if canImport(SwiftUI)
import CoreModels
import SwiftUI

/// A palette choice shared by profile avatars and appearance settings.
public struct ColorSwatchButton: View {
    private let title: LocalizedStringResource
    private let color: Color
    private let foreground: Color
    private let isSelected: Bool
    private let unselectedSymbol: String?
    private let action: () -> Void
    @Environment(\.themePalette) private var palette

    public init(
        title: LocalizedStringResource, color: Color, foreground: Color,
        isSelected: Bool, unselectedSymbol: String? = nil, action: @escaping () -> Void
    ) {
        self.title = title
        self.color = color
        self.foreground = foreground
        self.isSelected = isSelected
        self.unselectedSymbol = unselectedSymbol
        self.action = action
    }

    private var diameter: CGFloat {
        44
    }

    public var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: diameter, height: diameter)
                .overlay {
                    Circle().strokeBorder(
                        borderColor, lineWidth: borderWidth
                    )
                }
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: diameter * 0.4, weight: .heavy))
                            .foregroundStyle(foreground)
                    } else if let unselectedSymbol {
                        Image(systemName: unselectedSymbol)
                            .font(.system(size: diameter * 0.35, weight: .semibold))
                            .foregroundStyle(palette.secondaryText)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var borderColor: Color {
        isSelected ? palette.accent : palette.cardBorder
    }

    private var borderWidth: CGFloat {
        isSelected ? 3 : 1
    }
}

#endif
