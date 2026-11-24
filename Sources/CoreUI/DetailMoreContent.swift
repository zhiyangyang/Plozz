import Foundation

public enum DetailPreviewLimits {
    static let valueLines = 3
    static let facts = 9
    static let serviceLogos = 6
}

#if canImport(SwiftUI)
import SwiftUI

extension PlozzSheetStyle {
    static var detailReader: Self {
        .standard
    }
}


public struct DetailMoreLabel: View {
    public init() {}

    public var body: some View {
        Text("MORE")
            .font(labelFont)
            .plozzForeground(.secondary)
    }

    private var labelFont: Font {
        .footnote.weight(.semibold)
    }
}

struct DetailInlineMoreLabel<Content: View>: View {
    let isTruncated: Bool
    let fadeWidth: CGFloat
    let textFont: Font
    @ViewBuilder let content: Content
    @State private var lineHeight: CGFloat = 0
    @State private var moreWidth: CGFloat = 0

    private var maskWidth: CGFloat { max(fadeWidth, moreWidth + 48) }
    private var fadeEnd: CGFloat { (maskWidth - moreWidth - 8) / maskWidth }

    var body: some View {
        content.overlay(alignment: .bottomTrailing) {
            if isTruncated, lineHeight > 0 {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: fadeEnd),
                        .init(color: .black, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: maskWidth, height: lineHeight)
                .blendMode(.destinationOut)
            }
        }
        .compositingGroup()
        .overlay(alignment: Alignment(horizontal: .trailing, vertical: .lastTextBaseline)) {
            if isTruncated, lineHeight > 0 {
                DetailMoreLabel()
                    .fixedSize()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { moreWidth = $0 }
            }
        }
        .background(alignment: .topLeading) {
            Text(verbatim: "Ag")
                .font(textFont)
                .fixedSize()
                .hidden()
                .accessibilityHidden(true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { lineHeight = $0 }
        }
    }
}

public struct DetailMoreSheet<Content: View>: View {
    private let title: Text
    private let content: Content
    @Environment(\.dismiss) private var dismiss

    public init(title: Text, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    content
                }
                .padding(24)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollContentBackground(.hidden)
            .background { SettingsPageBackground() }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#endif
