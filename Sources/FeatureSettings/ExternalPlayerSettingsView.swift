import CoreModels
import CoreUI
import SwiftUI
import UIKit

public struct PlaybackAdvancedSettingsView: View {
    @Bindable var model: ExternalPlayerSettingsModel
    @State private var showsExternalPlayer = false

    public init(model: ExternalPlayerSettingsModel = .shared) {
        self.model = model
    }

    public var body: some View {
        List {
            SettingsSectionGroup {
                Button { showsExternalPlayer = true } label: {
                    SettingsDisclosureLabel { Text("External player") }
                }
                .settingsActionRow()
                .accessibilityIdentifier("playback-external-player")
            }
        }
        .settingsPageSurface()
        .navigationTitle("Advanced")
        .navigationDestination(isPresented: $showsExternalPlayer) {
            ExternalPlayerSettingsView(model: model)
        }
    }

    static func rows(model: ExternalPlayerSettingsModel = .shared) -> [SettingsSplitRow] {
        ExternalPlayerSettingsRows.advanced(model: model)
    }
}

struct ExternalPlayerSettingsRows {
    static func advanced(model: ExternalPlayerSettingsModel = .shared) -> [SettingsSplitRow] {
        [
            .page(id: "external-player", title: "External player") {
                external(model: model)
            }
        ]
    }

    static func external(
        model: ExternalPlayerSettingsModel, installedPlayers: Set<ExternalPlayer>? = nil
    ) -> [SettingsSplitRow] {
        [
                    SettingsSplitRow(id: "default-player", title: "Default player") {
                        ExternalPlayerChoices(model: model)
                    }.groupedContent(),
                    SettingsSplitRow(id: "external-player-help", title: "About external playback") {
                        ExternalPlayerHelp()
                    }.page(),
                    SettingsSplitRow(id: "custom-player", title: "Custom player") {
                        CustomExternalPlayerControls(model: model)
                    }.page()
        ]
    }
}

public struct ExternalPlayerSettingsView: View {
    @Bindable var model: ExternalPlayerSettingsModel
    private let custom: Bool
    @State private var showsAbout = false
    @State private var showsCustomPlayer = false

    public init(model: ExternalPlayerSettingsModel = .shared, custom: Bool = false) {
        self.model = model
        self.custom = custom
    }

    public var body: some View {
        if custom { customContent }
        else { root }
    }

    private var root: some View {
        List {
            SettingsSectionGroup("Default player") {
                ExternalPlayerChoices(model: model)
            }
            if model.settings.player != .builtIn {
                SettingsSectionGroup("\(model.settings.player.name) limitations") {
                    ExternalPlayerSupportSummary(player: model.settings.player)
                }
            }
            SettingsSectionGroup {
                Button { showsAbout = true } label: {
                    SettingsDisclosureLabel { Text("About external playback") }
                }
                .settingsActionRow()
            }
            SettingsSectionGroup {
                Button { showsCustomPlayer = true } label: {
                    SettingsDisclosureLabel { Text("Custom player") }
                }
                .settingsActionRow()
            }
        }
        .settingsPageSurface()
        .navigationTitle("External player")
        .navigationDestination(isPresented: $showsAbout) {
            List {
                SettingsSectionGroup { ExternalPlayerHelp() }
            }
            .settingsPageSurface()
            .navigationTitle("About external playback")
        }
        .navigationDestination(isPresented: $showsCustomPlayer) {
            customContent
        }
    }

    private var customContent: some View {
        List {
            SettingsSectionGroup { CustomExternalPlayerControls(model: model) }
        }
        .settingsPageSurface()
        .navigationTitle("Custom player")
    }
}


private struct ExternalPlayerChoices: View {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var model: ExternalPlayerSettingsModel
    @State private var installed: Set<ExternalPlayer> = [.builtIn]

    private var choices: [ExternalPlayer] {
        var result = ExternalPlayer.supported
        if !model.settings.customURLTemplate.isEmpty { result.append(.custom) }
        if !result.contains(model.settings.player) { result.append(model.settings.player) }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Applies to everyone on this device.")
                .settingsHelperText()
            SettingsControlMenu {
                ForEach(choices, id: \.self) { player in
                    Button {
                        model.settings.player = player
                    } label: {
                        if model.settings.player == player {
                            Label { title(player) } icon: { Image(systemName: "checkmark") }
                        } else {
                            title(player)
                        }
                    }
                    .disabled(!isAvailable(player))
                    .accessibilityIdentifier("external-player-\(player.rawValue)")
                }
            } label: {
                SettingsMenuLabel("Default player", value: title(model.settings.player))
            }
            .accessibilityLabel("Default player")
            .accessibilityValue(title(model.settings.player))
            .accessibilityIdentifier("external-player-selection").settingsSearchAnchor("external-player")
            if let error = model.error { Text(error.message).settingsHelperText() }
        }
        .task { refreshInstalledPlayers() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshInstalledPlayers() }
        }
    }

    private func isAvailable(_ player: ExternalPlayer) -> Bool {
        return player == .custom || installed.contains(player)
    }

    private func title(_ player: ExternalPlayer) -> Text {
        if player == .custom { return Text("Custom player") }
        if isAvailable(player) { return Text(verbatim: player.name) }
        return Text("\(player.name) (not installed)")
    }

    private func refreshInstalledPlayers() {
        installed = Set(ExternalPlayer.supported.filter {
            guard let scheme = $0.scheme, let url = URL(string: scheme + "://") else { return $0 == .builtIn }
            return UIApplication.shared.canOpenURL(url)
        })
    }
}

private struct ExternalPlayerSupportSummary: View {
    let player: ExternalPlayer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Downloads play in Plozz.")
            if player == .custom {
                Text("Non-WebDAV network shares and links needing passwords also play in Plozz.")
            } else {
                Text("Some network shares stay in Plozz when background streaming is unavailable.")
            }
            if player == .vlc || player == .custom {
                Text("Watch progress isn't returned to Plozz.")
            }
        }
        .settingsHelperText()
        .accessibilityIdentifier("external-player-support")
    }
}

private struct ExternalPlayerHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Compatible library videos open in the selected app, including server-converted streams. Unsupported sources play in Plozz.")
            Text("Playable links may include server access tokens or network-share passwords. Only choose an app you trust.")
            Text("Native Player and Infuse 8.4.7 or later can return progress when their player closes. Plozz's controls, skip markers, and autoplay aren't available in another app.")
            Text("This choice stays on this device. Watch progress still belongs to the active viewer.")
        }
        .settingsHelperText()
    }
}

private struct CustomExternalPlayerControls: View {
    @Bindable var model: ExternalPlayerSettingsModel
    @State private var template = ""
    @State private var error: ExternalPlayerError?
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Use {url} for the encoded video link. Custom players don't receive resume positions or return progress.")
                .settingsHelperText()
            SettingsInputRow("Player URL template") {
                TextField("Player URL template", text: $template, prompt: Text(verbatim: "myplayer://play?url={url}"))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("external-player-custom-template")
            }
            .settingsSearchAnchor("external-template")
            Text("Don't include passwords or access tokens in this template.")
                .settingsHelperText()
            if let error { Text(error.message).foregroundStyle(.red) }
            if saved { Text("Custom player selected").settingsHelperText() }
            Button {
                do {
                    try ExternalPlayerURL.validateCustomTemplate(template)
                    model.settings = .init(player: .custom, customURLTemplate: template)
                    error = nil
                    saved = true
                } catch let failure as ExternalPlayerError {
                    error = failure
                } catch {
                    self.error = .invalidTemplate
                }
            } label: {
                Text("Save and use custom player").settingsControlTarget()
            }
            .accessibilityIdentifier("external-player-custom-save")
        }
        .onAppear { template = model.settings.customURLTemplate }
        .onChange(of: template) { _, _ in saved = false }
    }
}
