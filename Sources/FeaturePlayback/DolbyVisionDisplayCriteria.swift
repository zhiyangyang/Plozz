#if canImport(AVFoundation)
import Foundation
import AVFoundation
import CoreMedia
import CoreModels

/// The HDR/Dolby-Vision display class of a resolved source range. Drives the
/// tvOS display-mode switch so the
/// Apple TV negotiates the correct HDMI signalling (true Dolby Vision, HDR10,
/// HLG, or plain SDR) with the panel before `AVPlayer` starts rendering.
///
/// This is the *native* (AVPlayer) path's contribution to true Dolby Vision:
/// only Apple's own pipeline can light up the DoVi handshake, and a custom
/// `AVPlayerLayer`-based player (as opposed to `AVPlayerViewController`) has to
/// drive `AVDisplayManager.preferredDisplayCriteria` itself — tvOS won't switch
/// the display for us automatically.
enum HDRDisplayMode: Equatable {
    case sdr
    case hdr10
    case hlg
    case dolbyVision

    /// Classifies a source from its declared range tokens. Mirrors Jellyfin's
    /// `VideoRangeType` vocabulary (`DOVI`, `DOVIWithHDR10`, `DOVIWithSDR`,
    /// `DOVIWithHLG`, `HDR10`, `HLG`) with `colorTransfer`/`videoRange` as a
    /// fallback. Any Dolby Vision profile maps to `.dolbyVision` so the panel is
    /// driven into DoVi mode; the RPU base layer is handled downstream.
    init(_ metadata: MediaSourceMetadata?) {
        self.init(SourceDynamicRange.providerHint(from: metadata) ?? .sdr)
    }

    init(_ range: SourceDynamicRange) {
        switch range {
        case .sdr: self = .sdr
        case .hlg: self = .hlg
        // Both use PQ/BT.2020 display criteria. HDR10+ additionally requires
        // the video's per-frame metadata, not a different static display mode.
        case .hdr10, .hdr10Plus: self = .hdr10
        case .dolbyVision: self = .dolbyVision
        }
    }

    var isHDR: Bool { self != .sdr }
}

#endif
