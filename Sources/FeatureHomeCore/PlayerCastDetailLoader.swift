#if canImport(SwiftUI)
import Foundation
import CoreModels

/// Builds the in-player Cast card's detail loader — the "L2" page behind a face.
///
/// Lives here rather than in the tvOS shell so BOTH shells can reach it. It has
/// no tvOS-only dependency and never did; it simply grew up next to its one
/// caller, and the iPad card was left showing faces with no biography and no
/// known-for row because the loader it needs was on the other side of a target
/// boundary. `PersonDetailViewModel` moved here first, for the same reason.
/// See `PlayerCastDetail` for what the pane does with each partial answer.
@MainActor
public func makeCastDetailLoader(
    for item: MediaItem,
    accounts: [ResolvedAccount]
) -> PlayerCastDetailLoading {
    // Captured once, outside the returned closure: these are the same for every
    // person in this item's cast.
    let sourceAccountID = item.sourceAccountID
    // `resolveOptionalProvider`, never `resolveProvider`: the latter falls back
    // to the primary account, which sent Jellyfin and share person ids to Plex
    // and got nothing back. No account means no credits, not wrong credits.
    let ownProvider = sourceAccountID.flatMap { id in
        accounts.first(where: { $0.account.id == id })?.provider
    }
    let otherProviders = accounts
        .filter { $0.account.id != sourceAccountID }
        .map(\.provider)
    let playingID = item.id
    let playingTitle = MediaItemIdentity.normalizedTitle(item.title)

    let playingLabel = item.title
    // Completed answers for this item's cast, so returning to a face costs
    // nothing. Scoped to this loader, and therefore to the title on screen:
    // the current title is filtered OUT of the credits, so a cached answer
    // stops being correct the moment something else is playing.
    let cache = PlayerCastDetailCache()

    return { person in
        let cacheKey = person.id
        // What is playing, alongside who was opened. Without it a trace can say
        // a person had no credits but not what they had no credits IN, which
        // makes a report impossible to reconstruct afterwards.
        PersonDiagnostics.emit("cast.open person=\(person.name) in=\(playingLabel)")
        let model = PersonDetailViewModel(
            person: person,
            provider: ownProvider,
            otherProviders: otherProviders,
            // Strike what is playing. By id AND by normalized title, since a
            // second server holding the same film answers with its own id.
            includeCredit: { item in
                item.id != playingID
                    && MediaItemIdentity.normalizedTitle(item.title) != playingTitle
            },
            // Enough to fill the rail several times over. The person page is
            // where the complete list lives.
            limit: 24
        )
        return AsyncStream { continuation in
            if let cached = cache.value(for: cacheKey) {
                PersonDiagnostics.emit("cast.cache-hit person=\(person.name)")
                continuation.yield(cached)
                continuation.finish()
                return
            }
            // Yield after every rung, so the credits the viewer's own server
            // already returned appear immediately instead of waiting behind a
            // biography lookup that may take a second or never answer at all.
            model.onProgress = { continuation.yield(snapshot(model)) }
            let task = Task { @MainActor in
                await model.load()
                let final = snapshot(model, isComplete: true)
                // Only the finished answer is kept. Caching a partial one would
                // pin whatever a slower server had not yet returned, and a
                // person whose row was still loading would be permanently short.
                cache.store(final, for: cacheKey)
                continuation.yield(final)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    @MainActor
    func snapshot(
        _ model: PersonDetailViewModel,
        isComplete: Bool = false
    ) -> PlayerCastDetail {
        PlayerCastDetail(
            // Withheld until the ORDER is settled, not merely until credits
            // exist: the row arrives in one piece rather than visibly
            // reshuffling under the viewer. The biography and headshot are
            // unaffected and still stream, so the pane is never empty while
            // this waits.
            credits: model.creditsAreFinal ? foldDuplicateCredits(model.libraryCredits) : [],
            biography: model.biography,
            lifeSummary: model.lifeSummary,
            isComplete: isComplete
        )
    }
}

/// Collapses the same title held on more than one server into one poster.
///
/// The person page's own fold keys on title+year and falls back to the id when a
/// year is missing — right for a page that lists everything, where wrongly
/// merging two films would hide one the viewer owns. A ten-poster glance strip
/// has the opposite bias: the same film four times (which is what a share and a
/// Jellyfin library holding one copy each actually produced) is a worse failure
/// than two same-named films sharing a slot. So a year-less copy is folded into
/// a titled one, while two copies that BOTH state a year and disagree stay
/// apart — which is what keeps Dune (1984) and Dune (2021) separate.
private func foldDuplicateCredits(_ items: [MediaItem]) -> [MediaItem] {
    func titleKey(_ item: MediaItem) -> String {
        "\(item.kind.rawValue)|\(MediaItemIdentity.normalizedTitle(item.title))"
    }

    // Strong external identity first, through the shared `TitleDedupe` — that is what
    // folds the same film catalogued under two different titles, which no title
    // compare can see. Within each group keep whichever copy can actually show a
    // poster; a row of grey title tiles is the one outcome worse than a duplicate.
    let collapsed: [MediaItem] = TitleDedupe.collapsed(items) { item in
        "\(titleKey(item))|\(item.productionYear.map(String.init) ?? "")"
    }

    let titlesWithAYear = Set(
        collapsed.filter { $0.productionYear != nil }.map(titleKey)
    )
    return collapsed.filter {
        $0.productionYear != nil || !titlesWithAYear.contains(titleKey($0))
    }
}

/// Finished cast answers for the title currently playing.
///
/// Deliberately per-loader rather than global: the credits deliberately exclude
/// whatever is on screen, so an entry is only valid for the item it was built
/// for. A global cache would hand a viewer the wrong list the moment they
/// started something else.
@MainActor
public final class PlayerCastDetailCache {
    public init() {}
    private var entries: [String: PlayerCastDetail] = [:]

    public func value(for id: String) -> PlayerCastDetail? { entries[id] }

    public func store(_ detail: PlayerCastDetail, for id: String) { entries[id] = detail }
}

#endif
