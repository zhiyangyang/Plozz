import Foundation

/// Whether a show's download sheet has library episodes to offer.
public struct SeriesDownloadPresentation: Equatable, Sendable {
    public let hasLibraryDownloads: Bool

    public var isVisible: Bool { hasLibraryDownloads }

    public init(item: MediaItem, children: [MediaItem]) {
        hasLibraryDownloads = item.kind == .series
            && children.contains {
                ($0.kind == .season || $0.kind == .episode) && $0.locallyValidatedPlayableSource
            }
    }
}

public enum SeriesDownloadAction: Equatable, Sendable {
    case download
    case preparing
    case pause
    case resume

    public var title: LocalizedStringResource {
        switch self {
        case .download: "Download All Available Episodes"
        case .preparing: "Preparing Downloads…"
        case .pause: "Pause Downloads"
        case .resume: "Resume Downloads"
        }
    }

    public func title(for destination: MediaDownloadDestination) -> LocalizedStringResource {
        self == .download ? destination.downloadTitle : title
    }

    public var systemImage: String {
        switch self {
        case .download: "arrow.down.circle"
        case .preparing: "clock"
        case .pause: "pause.circle"
        case .resume: "play.circle"
        }
    }

    public var isEnabled: Bool { self != .preparing }
}

public enum MediaDownloadDestination: Equatable, Sendable {
    case iPhone
    case iPad
    case device

    public var downloadTitle: LocalizedStringResource {
        switch self {
        case .iPhone: "Download to This iPhone"
        case .iPad: "Download to This iPad"
        case .device: "Download to This Device"
        }
    }

    public var downloadingTitle: LocalizedStringResource {
        switch self {
        case .iPhone: "Downloading to this iPhone"
        case .iPad: "Downloading to this iPad"
        case .device: "Downloading to this device"
        }
    }
}
