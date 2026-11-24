# Plozz Custom (iPad) — build and upstream-merge notes

This fork carries a small personal customization layer on top of Plozz. The
feature modules stay linked (`Package.swift` is unchanged) so upstream merges
stay small; the custom app simply never exposes or activates those features.

## Identity

| Item | Value |
| --- | --- |
| Display name | `Plozz Custom` |
| Bundle ID | `dev.zhiyangyang.plozz` |
| Platform | iPad only (`TARGETED_DEVICE_FAMILY = 2`) |
| Entitlements | `App/PlozziOS/PlozziOS.branded.entitlements` (empty) |
| Deep-link scheme | `plozzcustom://` |

`PlozzCustomization.customBundleID` in
[`Sources/CoreModels/PlozzCustomization.swift`](../Sources/CoreModels/PlozzCustomization.swift)
must match `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`.

## How the switches work

Custom behavior is keyed to the bundle ID, not a compile-time constant:

- The custom app (`dev.zhiyangyang.plozz`) gets the personalized behavior.
- Package tests, SwiftUI previews, and the canonical app keep upstream behavior
  because their `Bundle.main.bundleIdentifier` is different. Upstream tests
  therefore continue to exercise the original Discover/Seerr/Tracker paths.

Switches in `PlozzCustomization`:

| Switch | Custom app | Effect |
| --- | --- | --- |
| `supportsCloudSync` | false | No `CloudConfigSyncService`; no CloudKit container |
| `supportsSyncSetup` | false | No iCloud onboarding, sync settings, or pairing links |
| `supportsSeerr` | false | Seerr never becomes configured; request UI stays hidden |
| `supportsTrackers` | false | No tracker refresh, settings, or scrobbling |
| `supportsDiscover` | false | Discover removed from the iPad navigation catalogue |

The detail page also uses `PlozzCustomization` to omit the About, Ratings,
Details, Crew and Playback blocks from the information band. The hero (including
its Play/Resume action and rating badges), the Cast & Crew rail, Extras,
seasons/episodes and Release & Availability stay visible.

For movies, the custom build replaces the old metadata-driven Related row with
the server's native "More Like This" list (`/Items/{id}/Similar`, implemented for
Jellyfin/Emby). Tags replace the hero's genre line and remain tappable; studio
chips sit at the bottom of the detail page. Both browse the current library only; Emby uses
server-side `StudioIds`/`Studios`/`Tags` filters so a large library does not need a
full scan, while other providers fall back to local filtering. The catalog loads
60 items first and appends more when the grid reaches its end. The custom build
also hides the hero's Starring/Director credits, external ratings, and online
metadata/artwork/trailer enrichment. Plex and Silo currently inherit the empty
default for the native similar endpoint.

## Library navigation

The custom iPad build opens every library directly on its Browse grid. The
in-library Recommended, Playlists and Collections tabs are hidden; the upstream
mode implementations remain compiled for the canonical app and for future
upstream merges.

**Collections** and **Favorites** default to the slots immediately after Home,
but they are ordinary destinations in Settings → App navigation: they can be
hidden, shown or reordered like Upcoming, Downloads and Search. Favorites stays
visible when empty until it is explicitly hidden. A single library page does not
repeat the library name in its navigation title; the combined All Libraries and
Collections pages keep their titles.

- **Collections** is a top-level grid of every enabled media library's
  collections. It has no library picker; tapping a collection opens its members
  through the existing collection route.
- **Favorites** reuses the existing server Favorites/watchlist path but lists
  movies only. The filter menu is hidden and the entry stays visible by default
  when empty; hiding it in Settings is still respected.

The Favorites page, the combined All Libraries grid, and the Collections pages
use the system large title; a single library's grid hides the redundant library
name and keeps an inline bar with Back, sort and Settings. Favorites offers Name
and Release Date only, defaults to Name, and applies a sort change immediately.
Emby/Jellyfin Favorites do not expose a favorite-added timestamp, so Date Added
would only repeat provider order and is not offered.

Every full-page poster wall (Collection catalog/members, Favorites, libraries,
Search, Home/Related See All, and the studio/tag catalog) shares one rhythm:
the Appearance card-size setting controls the column count (Compact = 8,
Standard = 6, and so on), with a visible artwork edge aligned to the 36pt page
inset. The card gutter uses the same `stackSpacing` calculation as the Home
horizontal rails, so a grid card sits the same distance from its neighbour as
a Home rail card. Cards reserve subtitle space so rows with and without a
subtitle keep the same height.

Because the personal build compiles no tracker integrations, the tracker set is
treated as scoped even though there is nothing to re-point. Without that, the
unified watchlist defers its first read forever and Emby/Jellyfin Favorites never
reach the Favorites page. Tracker destinations are excluded explicitly, so a
credential left by another build cannot contribute a tracker list.

Movie detail pages present the same server favorite as a heart: the hero action
toggles it. Favorited movies wear a bare red heart in the top-right corner of
their library poster card; the detail page no longer overlays a second heart on
the logo. Movie poster cards also show Emby's own CommunityRating as a compact
number in the bottom-right corner, with no star or third-party rating source.

These behaviors are keyed to `PlozzCustomization.isCustomBuild`; the canonical
app, package tests and previews keep the upstream library modes and tab order.

## Custom seams

Keep changes confined to these files when possible:

- `project.yml` — identity, iPad-only, empty entitlements, no push/pairing
- `Sources/CoreModels/PlozzCustomization.swift` — all switches
- `Sources/CoreModels/SyncSetup.swift` — `disableCloudFeatures()`
- `Sources/CoreModels/SettingsSearch.swift` — hide disabled settings pages
- `Sources/CoreModels/NavigationRailPlan.swift` — remove Discover from iPad catalogue
- `Sources/FeatureHomeCore/LibraryBrowseViewModel.swift` — Browse-only custom library modes
- `Sources/FeatureHomeCore/AllLibrariesProvider.swift` — aggregate all collection-capable libraries
- `Sources/AppShelliOS/PlozziOSCollectionsDestinationView.swift` — top-level Collections grid
- `Sources/AppShelliOS/PlozziOSRootView.swift` — fixed top navigation and movie-only Favorites
- `Sources/AppShelliOS/PlozziOSAppModel.swift` / `PlozziOSAppModel+UniversalWatchlist.swift` — tracker scoping and server-favorites-only watchlist reads
- `Sources/AppShelliOS/PlozziOSHeroViews.swift` — movie favorite heart action
- `Sources/AppShelliOS/PlozziOSLibraryView.swift` / `PlozziOSPosterCard.swift` — red poster favorite badge
- `Sources/FeatureSettings/LibraryPresentationSettingsView.swift` — hide removed library-tab settings
- `Sources/FeatureSettings/ArtworkSettingsControls.swift` / `CardAppearanceControls.swift` / `CardCaptionCustomizationContent.swift` — hide artwork/caption categories for removed library pages
- `Sources/CoreUI/DetailInformationSections.swift` — omit the requested detail blocks
- `Sources/CoreModels/MovieCatalogTerm.swift` — studio/tag term and matching
- `Sources/FeatureHomeCore/MovieCatalogViewModel.swift` — current-library studio/tag paging
- `Sources/FeatureHomeCore/SimilarMoviesViewModel.swift` — server-native similar movies
- `Sources/AppShelliOS/PlozziOSStudioSection.swift` — studio chips
- `Sources/AppShelliOS/PlozziOSDetailTagNavigator.swift` — hero tag taps
- `Sources/AppShelliOS/PlozziOSMovieCatalogView.swift` — studio/tag movie grid
- `Sources/AppShelliOS/PlozziOSMoreLikeThisSection.swift` — native similar rail
- `Sources/ProviderJellyfin/JellyfinClient.swift` / `JellyfinProvider.swift` — `/Items/{id}/Similar`
- `Sources/ProviderJellyfin/JellyfinLibraryQuery.swift` — request `Studios`/`Tags` in the inventory
- `App/PlozziOS/PlozziOSApp.swift` — apply cloud-off defaults before model creation
- `Sources/AppShelliOS/PlozziOSAppModel.swift` — skip Seerr/Tracker lifecycle work
- `Sources/AppShelliOS/PlozziOSAppModel+CloudSync.swift` — return no cloud service
- `Sources/AppShelliOS/PlozziOSSettingsView.swift` — hide Seerr/Tracker/Sync rows
- `Sources/AppShelliOS/PlozziOSRootView.swift` — filter Discover and sync offers
- `Sources/AppShelliOS/PlozziOSTrackerScrobbler.swift` — no-op when disabled
- `Sources/FeatureSettings/SeerSetupPreparation.swift` — no Seerr LAN discovery
- `Sources/SeerService/SeerService.swift` — `isConfigured` always false when disabled
- `Tests/CoreModelsTests/PlozzCustomizationTests.swift` — bundle-ID and flag tests

Do **not** edit the generated `Plozz.xcodeproj`, and do not remove the Seerr or
Tracker targets from `Package.swift` on this branch. Deleting modules would make
every upstream merge touch dozens of files.

## Upstream sync

```bash
git fetch upstream
git rebase upstream/main
tools/generate-project.sh
```

Recommended cadence: weekly, or before starting any new customization work.
Enable `git rerere` once to reuse conflict resolutions:

```bash
git config rerere.enabled true
```

Conflict hotspots are the seam files above, especially
`PlozziOSAppModel.swift`, `PlozziOSSettingsView.swift`, and
`PlozziOSRootView.swift`. Resolve by keeping upstream code and re-applying the
small `PlozzCustomization` guards.

## Verify after a merge

```bash
tools/generate-project.sh
xcodebuild -project Plozz.xcodeproj -scheme PlozziOS -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' \
  -derivedDataPath .build/ipad-sim build
python3 tools/arch-guard.py
tools/run-tests.sh CoreModelsTests
```

Manual smoke:

- App name is **Plozz Custom** and bundle ID is `dev.zhiyangyang.plozz`.
- First launch has no iCloud prompt and no CloudKit crash.
- Settings has no iCloud Sync, Seerr, or Trackers entries.
- The iPad tab bar has no Discover tab.
- Creating a profile does not offer Seerr setup.
- Detail/Home show no Request buttons.
- Playing a title produces no Trakt/Simkl/AniList/MAL/Wetrakr network attempts.

## Device signing

The simulator needs no team. For a physical iPad, set `DEVELOPMENT_TEAM` in
`project.yml` (or pass a team through Xcode) and sign with the empty branded
entitlements. A free personal team works for short-lived installs; a paid team
avoids weekly re-signing. No iCloud container or push capability is required.

## Re-enabling a feature

Change the relevant `PlozzCustomization` switch back to `!isCustomBuild`, then
undo the matching UI filter in that seam. The underlying module and tests are
still present and unchanged.
