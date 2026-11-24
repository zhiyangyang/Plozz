# Required-reason API declarations

`project.yml` copies `App/Privacy/iOS/PrivacyInfo.xcprivacy` into the iPad app's
resource bundle. There is no second app or extension manifest.

| Category | Reason | First-party use |
| --- | --- | --- |
| File timestamps | `C617.1` | Cache eviction and detecting replacement of files inside Plozz's app, app-group and CloudKit containers. See `DetailSnapshotCache`, `MusicLandingCache` and `LiveTVSyncFileRevision`. |
| System boot time | `35F9.1` | Playback/UI timers and elapsed operation measurements. Diagnostic exports can include elapsed durations, not system boot time. |
| Disk space | `85F4.1` | Display available space in playback diagnostics and mobile Downloads. Raw disk-space values are not included in the structured diagnostic exports. |
| Disk space, iOS only | `E174.1` | Check capacity before user-requested downloads. See `DownloadStorageCapacity`; downloads can be refused when space is insufficient. |
| User defaults | `CA92.1` | Plozz-owned preferences and local state. |

These files declare required-reason API access. They do not claim that no data
is collected, replace App Store privacy answers, or cover required-reason API
usage inside separately bundled third-party dynamic frameworks. Check those
frameworks' manifests in the final release archive.

The existing CI pipeline regression suite checks the reason sets, per-target
resource wiring and dependency source references. After project generation,
verify the built app contains the appropriate manifest. Changes to API usage or
export behavior require reviewing these reasons against
[Apple's current approved reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).
