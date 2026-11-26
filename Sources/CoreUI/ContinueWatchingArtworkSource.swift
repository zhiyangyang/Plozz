#if canImport(UIKit)
import CoreModels
import Foundation
import SwiftUI
import UIKit

public extension EnvironmentValues {
    @Entry var continueWatchingLogoScope: String? = nil
}

/// Shared logo/background composition for Continue Watching and opt-in landscape rows.
public struct ContinueWatchingArtworkSource: Sendable {
    let item: MediaItem
    let style: PosterCardView.Style
    let cardPolicy: CardArtworkPolicy
    let allowsFallback: Bool
    let policy: ArtworkPresentationPolicy
    let titleLogo: LandscapeTitleLogo?

    public init(
        item: MediaItem, style: PosterCardView.Style,
        policy: ArtworkPresentationPolicy, cardPolicy: CardArtworkPolicy = .standard,
        enablesAsyncArtworkFallback: Bool = true,
        titleLogo: LandscapeTitleLogo? = nil
    ) {
        self.item = item
        self.style = style
        self.policy = titleLogo == nil ? policy.forArea(.continueWatching) : policy
        self.titleLogo = titleLogo
        self.cardPolicy = cardPolicy
        self.allowsFallback = enablesAsyncArtworkFallback && cardPolicy.allowsOnlineFallback
    }

    var pinIdentity: String {
        cardPolicy.pinIdentity(for: item) + (titleLogo.map { "|title-logo:\($0.rawValue)" } ?? "")
    }
    var variant: ArtworkImageVariant { style == .poster ? .posterCard : .landscapeCard }
    var aspectGuard: CGFloat? { style == .poster ? 0.9 : nil }
    var logoReferences: [ArtworkReference] { item.artworkReferences(for: .logo) }
    var prefersTextlessBackdrop: Bool { false }

    func suppressesLogo(
        artworkAlreadyCarriesTitle: Bool, hasCurrentArtwork: Bool, textlessBackdropSuppressesLogo: Bool
    ) -> Bool {
        if let titleLogo {
            return titleLogo == .off || style != .landscape || !hasCurrentArtwork
        }
        return style == .poster || artworkAlreadyCarriesTitle
            || (prefersTextlessBackdrop && textlessBackdropSuppressesLogo)
    }

    public var identity: String {
        [
            pinIdentity, item.title, style == .poster ? "poster" : "landscape",
            policy.forPlacement(.logo).identity, policy.settings.preference(in: policy.area).rawValue,
            allowsFallback ? "fallback" : "local-only",
            references(textlessBackdrop: nil).map(\.privacySafeIdentity).joined(separator: "\n"),
            logoReferences.map(\.privacySafeIdentity).joined(separator: "\n"),
        ].joined(separator: "|")
    }

    func primaryReference(textlessBackdrop: URL?) -> ArtworkReference? {
        guard style == .landscape else { return nil }
        if titleLogo != nil { return nil }
        return PosterCardPresentation.continueWatchingPrimaryReference(
            for: item, policy: policy, textlessBackdrop: nil
        )
    }

    func references(textlessBackdrop: URL?) -> [ArtworkReference] {
        var ladder = item.kind == .episode
            ? item.seriesArtworkReferences(prefersPortrait: style == .poster)
            : cardPolicy.references(for: item, style: style, prefersLandscapeKeyArt: false)
        if titleLogo != nil {
            let titled = PosterCardPresentation.titleBearingArtwork(for: item)
            let candidates = item.artworkReferences(for: .homeHero, preferringLibrarySelection: true)
                + item.artworkReferences(for: .landscapeCard) + ladder
            var seen = Set<ArtworkReference>()
            ladder = (candidates.filter { !titled.contains($0) } + candidates)
                .filter { seen.insert($0).inserted }
        }
        guard let primary = primaryReference(textlessBackdrop: textlessBackdrop) else { return ladder }
        return [primary] + ladder.filter { $0 != primary }
    }

    func fallback(background: Bool = false) -> (@Sendable () async -> URL?)? {
        guard allowsFallback else { return nil }
        guard let lookup = cardPolicy.artworkFallback(for: item, style: style) else { return nil }
        return { await ArtworkSession.resolveArtwork(background: background, lookup) }
    }

    func logoFallback(background: Bool = false) -> HeroLogoFallback? { nil }

    func logoVisit(in scope: String?) -> DetailLogoVisit? {
        guard let scope, item.kind == .movie || item.kind == .series
                || (item.kind == .episode && item.seriesID != nil) else { return nil }
        let subject = item.kind == .episode ? ArtworkSubject.seriesArtworkItem(for: item) : item
        return DetailLogoVisit(scope: scope, subject: subject.stablePresentationID)
    }

    @MainActor
    public func prepare(detailLogoScope: String? = nil) async {
        guard style == .landscape else {
            await prepareBackground()
            return
        }
        async let logo: Void = HeroLogoPreloader.prepare(
            references: logoReferences, fallback: logoFallback(background: true), policy: policy,
            visit: logoVisit(in: detailLogoScope)
        )
        await prepareBackground()
        await logo
    }

    @MainActor
    private func prepareBackground() async {
        guard !Task.isCancelled else { return }
        await ArtworkFirstPaintResolver.prepare(
            references: references(textlessBackdrop: nil),
            prefersPrimaryReference: primaryReference(textlessBackdrop: nil) != nil,
            variant: variant, maxAspectRatio: aspectGuard,
            asyncOnlineURL: fallback(background: true),
            pinIdentity: pinIdentity, policy: policy
        )
    }
}
#endif
