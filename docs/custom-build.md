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

## Custom seams

Keep changes confined to these files when possible:

- `project.yml` — identity, iPad-only, empty entitlements, no push/pairing
- `Sources/CoreModels/PlozzCustomization.swift` — all switches
- `Sources/CoreModels/SyncSetup.swift` — `disableCloudFeatures()`
- `Sources/CoreModels/SettingsSearch.swift` — hide disabled settings pages
- `Sources/CoreModels/NavigationRailPlan.swift` — remove Discover from iPad catalogue
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
