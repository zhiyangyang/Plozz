#if canImport(SwiftUI)
import CoreModels
import CoreUI
import SwiftUI

public extension View {
    func playbackVersionChoice(_ model: PlaybackVersionChoiceModel) -> some View {
        modifier(PlaybackVersionChoicePresentation(model: model))
    }
}

private struct PlaybackVersionChoicePresentation: ViewModifier {
    let model: PlaybackVersionChoiceModel

    func body(content: Content) -> some View {
        content.plozzSheet(isPresented: Binding(
            get: { model.prompt != nil },
            set: { if !$0 { model.cancel() } }
        )) {
            PlaybackVersionChoiceView(model: model)
                .interactiveDismissDisabled()
        }
    }
}

public struct PlaybackVersionChoiceView: View {
    let model: PlaybackVersionChoiceModel
    @Environment(\.themePalette) private var palette

    public init(model: PlaybackVersionChoiceModel) { self.model = model }

    public var body: some View {
        if let prompt = model.prompt {
            #if os(iOS)
            NavigationStack {
                PlaybackVersionChoiceContent(model: model, prompt: prompt)
                    .navigationTitle("Choose a version")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close", systemImage: "xmark") { model.cancel() }
                                .labelStyle(.iconOnly)
                                .accessibilityIdentifier("version-choice-cancel")
                        }
                    }
            }
            .tint(palette.accent)
            #else
            VStack(spacing: 0) {
                PlaybackVersionChoiceContent(model: model, prompt: prompt)
                Button("Cancel") { model.cancel() }
                    .plozzActionButton(role: .secondary)
                    .accessibilityIdentifier("version-choice-cancel")
                    .padding()
            }
            #endif
        }
    }
}

private struct PlaybackVersionChoiceContent: View {
    let model: PlaybackVersionChoiceModel
    let prompt: PlaybackVersionChoiceModel.Prompt

    var body: some View {
        if prompt.needsIntroduction {
            FirstUseChoiceView(
                symbol: "square.stack",
                title: "How should versions be selected?",
                message: "Ask each time, let Plozz choose, or use the server's first version.",
                actions: [
                    .init("Ask every time", identifier: "version-choice-ask") {
                        model.chooseMode(.askEveryTime, promptID: prompt.id)
                    },
                    .init("Choose automatically", identifier: "version-choice-automatic") {
                        model.chooseMode(.automatic, promptID: prompt.id)
                    },
                    .init("Use first from server", identifier: "version-choice-server-order") {
                        model.chooseMode(.serverOrder, promptID: prompt.id)
                    }
                ],
                footer: "Change this any time in Settings > Playback > Version selection.",
                messageAccessory: AnyView(AutomaticVersionInfoButton())
            )
        } else {
            PlaybackVersionChoiceList(prompt: prompt) {
                model.chooseVersion($0, promptID: prompt.id)
            }
        }
    }
}

private struct PlaybackVersionChoiceList: View {
    let prompt: PlaybackVersionChoiceModel.Prompt
    let select: (String) -> Void
    @Environment(\.locale) private var locale
    @Environment(\.themePalette) private var palette
    @FocusState private var focusedID: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                #if !os(iOS)
                Text("Choose a version")
                    .font(.title.bold())
                    .foregroundStyle(palette.primaryText)
                    .accessibilityAddTraits(.isHeader)
                #endif
                Text(verbatim: prompt.item.title)
                    .font(.headline)
                    .foregroundStyle(palette.secondaryText)
                ForEach(prompt.versions) { version in
                    MediaVersionChoiceButton(
                        presentation: .init(version, locale: locale),
                        isSelected: prompt.selectedVersionID == version.id,
                        isFocused: focusedID == version.id
                    ) {
                        select(version.id)
                    }
                    .focused($focusedID, equals: version.id)
                    .accessibilityIdentifier("version-choice-\(version.id)")
                }
            }
            .padding(32)
            .frame(maxWidth: 1_100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

#endif
