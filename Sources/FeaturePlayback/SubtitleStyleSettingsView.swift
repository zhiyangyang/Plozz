#if canImport(SwiftUI)
import CoreModels
import CoreUI
import SwiftUI

public struct SubtitleStyleSettingsView: View {
    @Binding private var style: SubtitleStyle
    private let isLiveTV: Bool
    private let initialPage: SettingsSearchSubtitlePage
    @Environment(SettingsSearchRequest.self) private var searchRequest: SettingsSearchRequest?
    @State private var controls = PlayerControlsModel()
    @State private var secondaryVisible = false
    @State private var prepared = false
    @State private var previewOptions = SubtitlePreviewOptions()

    public init(
        style: Binding<SubtitleStyle>, isLiveTV: Bool = false,
        initialPage: SettingsSearchSubtitlePage = .appearance
    ) {
        _style = style
        self.isLiveTV = isLiveTV
        self.initialPage = isLiveTV && initialPage == .dual ? .appearance : initialPage
    }

    public var body: some View {
        GeometryReader { geometry in
            let context = SubtitleStyleEditingContext(
                controls: controls, style: $style, secondaryPreview: secondaryPreview,
                offersDualSubtitles: !isLiveTV, showsASSOverride: !isLiveTV
            )
            let width = max(geometry.size.width, geometry.size.height)
            let reference = CGSize(width: width, height: width * 9 / 16)
            let layout = geometry.size.width > geometry.size.height
                ? AnyLayout(HStackLayout(alignment: .top, spacing: 24))
                : AnyLayout(VStackLayout(alignment: .leading, spacing: 20))
            layout {
                SubtitleStylePreview(
                    style: style, secondaryVisible: secondaryVisible,
                    referenceSize: reference, options: previewOptions
                )
                .frame(maxWidth: .infinity)
                NavigationStack {
                    MobileSubtitleStyleEditor(viewModel: context, initialPage: initialPage)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, pageInset)
        .padding(.vertical, 24)
        .background { SettingsPageBackground() }
        .navigationTitle(Text(pageTitle))
        #if os(iOS)
        .toolbarTitleDisplayMode(.inline)
        #endif
        .onChange(of: style, initial: true) { previous, value in
            controls.subtitleStyle = value
            controls.subtitlesRenderHDR = true
            previewOptions.styleDidChange(from: previous, to: value)
            if value.secondary == nil { secondaryVisible = false }
        }
        .onAppear {
            guard !prepared else { return }
            prepared = true
            secondaryVisible = !isLiveTV && style.secondary != nil
        }
    }

    private var pageTitle: LocalizedStringResource {
        isLiveTV ? "Customize Live TV subtitles" : "Customize subtitle style"
    }


    private var pageInset: CGFloat {
        16
    }

    private var secondaryPreview: Binding<Bool> {
        Binding(
            get: { secondaryVisible },
            set: {
                if $0, style.secondary == nil {
                    style.secondary = .init()
                    controls.subtitleStyle = style
                }
                secondaryVisible = $0
            }
        )
    }
}

#endif
