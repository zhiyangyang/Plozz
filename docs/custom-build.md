# Plozz Custom (iPad)

This branch is a hard fork of the iPad app. The Apple TV app, Top Shelf
extension, FocusHost, and tvOS targets are gone. `Package.swift` and
`project.yml` are not upstream-compatible.

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
must match `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`. A `--branded` suffix
still counts as the custom app.

## Runtime switches

Custom behavior is keyed to the bundle ID, not a compile-time constant, so
package tests and previews keep neutral behavior.

| Behaviour | Custom app |
| --- | --- |
| Library entry | Opens directly on Browse; Recommended/Playlists/Collections tabs are hidden |
| Collections | Top-level navigation destination |
| Favorites | Top-level destination, movie favorites only |
| Detail header | Hero, Play/Resume, cast, extras, episodes and release information stay |
| Detail information band | About, external ratings, details, crew and playback blocks stay hidden |
| Similar titles | Server-native similar list for supported providers |
| Hero metadata | Tags and studio chips are tappable; Starring/Director credits stay hidden |
| Settings search | Entries for hidden library pages are filtered out |

The custom detail page does not use external metadata, online artwork, trailers,
or discovery enrichment. Those providers are removed from the app rather than
switched off.

## Removed feature surface

The following are no longer compiled or linked, so no customization switch is
needed:

- Apple TV, tvOS, Top Shelf and FocusHost
- Live TV, IPTV and Multiview
- Music and Subsonic
- Seerr requests and trackers
- iCloud sync, device pairing and multi-profile setup
- External metadata, ratings and artwork providers
- Hero trailer autoplay and detail trailers

## Build

Use the repository tools, not bare XcodeGen:

```sh
tools/generate-project.sh
xcodebuild -project Plozz.xcodeproj -scheme PlozziOS \
  -destination 'platform=iOS Simulator,id=<UDID>' build
```

`project.yml` and `Package.swift` are the source of truth. Never commit the
generated Xcode project.
