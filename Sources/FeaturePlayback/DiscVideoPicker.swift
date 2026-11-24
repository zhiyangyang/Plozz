#if canImport(UIKit) && canImport(SwiftUI)
import SwiftUI
import CoreModels
import CoreUI

struct DiscVideoPicker: View {
    let model: PlayerViewModel
    let close: () -> Void
    @State private var videos: [DiscVideo]?
    @State private var failure: String?
    @State private var reloadID = UUID()
    @FocusState private var focusedPlaylist: Int?

    var body: some View {
        DiscPlaybackDialog(title: "Disc videos", close: close) {
            if let failure {
                Text(verbatim: failure)
                    .foregroundStyle(.secondary)
                Button("Retry") { reloadID = UUID() }
                    .discPlaybackActionButton()
            } else if let videos {
                ForEach(videos) { video in
                    Button {
                        do {
                            try model.playDiscVideo(video)
                            close()
                        } catch {
                            failure = error.localizedDescription
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Playlist \(String(format: "%05d", video.playlist))")
                            Text("\(Duration.seconds(video.duration).formatted(.time(pattern: .hourMinuteSecond))) \u{00B7} \(video.chapterCount) chapters")
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }
                    .discPlaybackActionButton()
                    .buttonBorderShape(.roundedRectangle(radius: 16))
                    .focused($focusedPlaylist, equals: video.playlist)
                }
            } else {
                ProgressView("Reading disc")
            }
        }
        .task(id: reloadID) {
            videos = nil
            failure = nil
            do {
                videos = try await model.loadDiscVideos()
            } catch is CancellationError {
                return
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}

struct DiscPlaybackDialog<Content: View>: View {
    let title: LocalizedStringResource
    let close: () -> Void
    @ViewBuilder let content: () -> Content
    @Environment(\.themePalette) private var palette

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16, content: content)
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(Text(title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark", action: close)
                        .labelStyle(.iconOnly)
                }
            }
        }
        .tint(palette.primaryText)
    }
}

extension View {
    @ViewBuilder
    func discPlaybackActionButton() -> some View {
        self.plozzActionButton(role: .secondary)
    }

    /// Keep the TV playback owner mounted, as with the shared version-choice dialog.
    func discPlaybackSheet<Content: View>(
        isPresented: Binding<Bool>, onDismiss: @escaping () -> Void = {},
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        self.plozzSheet(isPresented: isPresented, onDismiss: onDismiss, content: content)
    }
}
#endif
