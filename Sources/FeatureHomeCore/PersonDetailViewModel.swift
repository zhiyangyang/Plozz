#if canImport(SwiftUI)
import SwiftUI
import CoreModels
import CoreNetworking

/// The credits a person page can show.
///
/// Server-first: `libraryCredits` comes from the source the person was seen on,
/// using that source's own person id, so it needs no third party, resolves no
/// identities, and every entry is a title the viewer owns and can play. A
/// metadata outage costs this page a biography, not its usefulness.
@MainActor
@Observable
public final class PersonDetailViewModel {
    public enum LoadState: Equatable {
        case loading
        case loaded
        /// The source could not answer. The page still renders its header — the
        /// person's name, role and headshot all arrived with the item they were
        /// listed on, so there is always something to show.
        case unavailable
    }

    public private(set) var state: LoadState = .loading
    public private(set) var libraryCredits: [MediaItem] = []
    /// Whether the credit ORDER is settled.
    ///
    /// The list grows in rungs, and the last rung re-sorts everything by how
    /// prominent the person was. A surface that shows credits the moment they
    /// exist therefore shows them in the wrong order and visibly reshuffles a
    /// second later. Anywhere that cannot afford that — the in-player card,
    /// which the viewer is watching at the moment it happens — waits for this
    /// instead of for the whole load.
    ///
    /// Distinct from "everything finished": the biography can still be in
    /// flight, and it renders in its own place without disturbing the row.
    public private(set) var creditsAreFinal = false
    /// Filled only if the source keeps person records with one. Loaded alongside
    /// the credits and independently of them: a source can answer for one and not
    /// the other, and neither absence should block the other from showing.
    public private(set) var biography: String?
    /// "1937 · Memphis, Tennessee, USA", when a source can say. Independent of
    /// the biography: a source can place someone it cannot describe.
    public private(set) var lifeSummary: String?

    /// Fired after each rung of the ladder lands, so a caller that cannot
    /// observe this object directly can still render progressively.
    ///
    /// The page itself needs no such thing — it observes the properties — but
    /// the in-player card takes a snapshot through a closure, and without this
    /// it could only take one: at the very end, behind the slowest rung.
    public var onProgress: (@MainActor () -> Void)?

    private let person: MediaPerson
    private let provider: (any MediaProvider)?
    /// The viewer's *other* signed-in servers. Empty for the single-server case,
    /// which is most people — and when it is empty this class does exactly what
    /// it did before, one request, no extra latency.
    private let otherProviders: [any MediaProvider]
    /// Drops credits the caller does not want counted — in practice the title
    /// currently playing, which every one of its own cast is trivially in.
    private let includeCredit: @Sendable (MediaItem) -> Bool
    private let limit: Int

    public init(
        person: MediaPerson,
        provider: (any MediaProvider)?,
        otherProviders: [any MediaProvider] = [],
        includeCredit: @escaping @Sendable (MediaItem) -> Bool = { _ in true },
        limit: Int = 40
    ) {
        self.person = person
        self.provider = provider
        self.otherProviders = otherProviders
        self.includeCredit = includeCredit
        self.limit = limit
    }

    /// Folds the viewer's other servers in, keyed by the person's **name** since
    /// ids do not cross servers.
    ///
    /// Additive only: anything these return is extra, and any that fail simply
    /// contribute nothing. A second server can also supply the biography the
    /// first one lacked.
    private func mergeOtherServers() async {
        let name = person.name
        guard !name.isEmpty else { return }
        let limit = self.limit

        var merged = libraryCredits
        var seen = Set(merged.map(Self.dedupeKey))

        await withTaskGroup(of: (([MediaItem])?, MediaPerson?).self) { group in
            for other in otherProviders {
                group.addTask {
                    async let items = try? other.items(withPersonNamed: name, limit: limit)
                    async let record = try? other.person(named: name)
                    return (await items, await record ?? nil)
                }
            }
            for await (items, record) in group {
                if biography == nil {
                    biography = record?.biography.flatMap { $0.isEmpty ? nil : $0 }
                }
                PersonDiagnostics.emit(
                    "person.server name=\(name) items=\(items?.count ?? -1) "
                    + "record=\(record == nil ? "nil" : "yes") "
                    + "bio=\(record?.biography?.isEmpty == false ? "yes" : "no")"
                )
                for item in items ?? [] where includeCredit(item)
                    && seen.insert(Self.dedupeKey(item)).inserted {
                    merged.append(item)
                }
            }
        }

        libraryCredits = collapsedCredits(merged)
        // A server that had nothing to say about the home source's failure should
        // not leave the page reading "unavailable" when others answered.
        if !libraryCredits.isEmpty { state = .loaded }
    }

    private func collapsedCredits(_ items: [MediaItem]) -> [MediaItem] {
        Self.collapsingAcrossServers(Self.collapsingDuplicates(items))
    }

    /// Collapses one work held on several servers into a single credit.
    ///
    /// Keyed on kind+title, deliberately without the year: the year is the field
    /// the servers disagree on, so including it defeats the very merge this is
    /// for. Within a person's credits a genuine collision between two same-named
    /// works of the same kind is rare, and the cost is one row entry rather than
    /// something unplayable — the survivor is still a real library item, and the
    /// detail page's cross-server picker still finds every copy.
    ///
    /// First wins, so the home server's copy stays the one the row routes to, but
    /// it inherits a year or a poster from a later copy when it lacks one: which
    /// server answered first is arbitrary, and a card with no date or no artwork
    /// is not.
    static func collapsingAcrossServers(_ items: [MediaItem]) -> [MediaItem] {
        TitleDedupe.collapsed(items, policy: .titleIgnoringYear)
    }

    /// A provider's family, for telemetry — so a log line says WHICH kind of
    /// server answered, not just that one did.
    private static func kind(of provider: any MediaProvider) -> String {
        String(describing: type(of: provider))
            .replacingOccurrences(of: "Provider", with: "")
    }

    /// Collapses duplicates within ONE server's answer.
    ///
    /// A server legitimately returns the same work more than once — the same film
    /// in two libraries, or as separate versions/editions — and for a credits row
    /// those are one title.
    ///
    /// Keeps the first occurrence so the server's own ordering survives, but
    /// takes a later copy's artwork if the winner had none: which duplicate came
    /// first is arbitrary, and a poster is not.
    static func collapsingDuplicates(_ items: [MediaItem]) -> [MediaItem] {
        // Strong external identity is handled by the shared `TitleDedupe`, which also
        // applies the merge split guard; `dedupeKey` supplies only this row's weak
        // policy. Adding the strong half fixes the case a pure title compare could
        // never see: the same film catalogued under two localized titles, which both
        // servers agree is `imdb:tt…`.
        TitleDedupe.collapsed(items, weakKey: dedupeKey)
    }

    /// This row's **weak** policy — the strong-identity half lives in the shared
    /// ``TitleDedupe``.
    ///
    /// Title+year rather than external ids: this is a display row, the two copies
    /// are interchangeable for the viewer, and being wrong costs a duplicate
    /// poster rather than the wrong thing playing.
    private static func dedupeKey(_ item: MediaItem) -> String? {
        let title = MediaItemIdentity.normalizedTitle(item.title)
        guard let year = item.productionYear else {
            // No year is not evidence of sameness. Two different films can share a
            // normalized title, and collapsing them would silently remove one the
            // viewer owns — a worse outcome than the duplicate poster this exists
            // to prevent. No weak key at all, so only a shared strong id merges it.
            return nil
        }
        return "\(item.kind.rawValue)|\(title)|\(year)"
    }

    public func load() async {
        guard state == .loading else { return }
        // Settled on EVERY exit, including the early ones.
        defer { creditsAreFinal = true }
        let started = Date()
        func elapsed(_ from: Date) -> Int { Int(Date().timeIntervalSince(from) * 1000) }

        // No OWNING server is not the end of the lookup: the remaining stages
        // key off the person's NAME, not a server-specific id, so they work
        // without one.
        var items: [MediaItem]?
        if let provider {
            // The person's own server, asked by its own exact id. Independent and
            // separately fallible from the biography: a source can list credits and
            // keep no person record, or the reverse, and neither absence should
            // suppress the other.
            async let credits = try? provider.items(withPerson: person.id, limit: limit)
            async let record = try? provider.person(id: person.id)

            // `try?` over an already-Optional return nests the optionals, so flatten
            // both once: "the call failed" and "the source had nothing" mean the same
            // thing to this page.
            items = await credits
            let personRecord: MediaPerson? = await record ?? nil

            biography = personRecord?.biography.flatMap { $0.isEmpty ? nil : $0 }
            lifeSummary = personRecord?.lifeSummary.flatMap { $0.isEmpty ? nil : $0 }
            if let items {
                libraryCredits = collapsedCredits(items.filter(includeCredit))
                state = .loaded
            } else {
                state = .unavailable
            }
            PersonDiagnostics.emit(
                "person.own name=\(person.name) provider=\(Self.kind(of: provider)) "
                + "credits=\(items?.count ?? -1) record=\(personRecord == nil ? "nil" : "yes") "
                + "bio=\(biography == nil ? "no" : "yes") ms=\(elapsed(started))"
            )
        } else {
            // Nothing owned yet, but nothing failed either — the later stages
            // decide what this page can show.
            state = .unavailable
            PersonDiagnostics.emit(
                "person.own name=\(person.name) provider=none "
                + "result=no-owning-server ms=\(elapsed(started))"
            )
        }
        onProgress?()

        if Task.isCancelled { return }

        // The source's own global handle, where it keeps one. Plex is the only
        // provider that does, and for a Plex-sourced person this is the sole
        // route to a biography — the server itself has no person records at
        // all, only actor tags on titles.
        if biography == nil, let provider,
           let externalID = person.externalID, !externalID.isEmpty {
            let stage = Date()
            let record = await provider.person(externalID: externalID, name: person.name)
            if let text = record?.biography, !text.isEmpty { biography = text }
            if let life = record?.lifeSummary, !life.isEmpty { lifeSummary = life }
            PersonDiagnostics.emit(
                "person.external-id name=\(person.name) "
                + "bio=\(biography == nil ? "MISS" : "hit") ms=\(elapsed(stage))"
            )
            onProgress?()
        }

        // Render what the home server gave us before consulting anyone else, so
        // time-to-content never depends on how many servers are signed in.
        if !otherProviders.isEmpty {
            let stage = Date()
            await mergeOtherServers()
            PersonDiagnostics.emit(
                "person.others name=\(person.name) servers=\(otherProviders.count) "
                + "credits=\(libraryCredits.count) bio=\(biography == nil ? "no" : "yes") "
                + "ms=\(elapsed(stage))"
            )
            onProgress?()
        }

        PersonDiagnostics.emit(
            "person.done name=\(person.name) credits=\(libraryCredits.count) "
            + "bio=\(biography == nil ? "MISS" : "hit") ms=\(elapsed(started))"
        )
    }
}
#endif
