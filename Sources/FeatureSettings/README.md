# FeatureSettings

Profile-scoped settings models, persistence, and the screens used by the iPad
app. The app shell owns navigation and presentation; this module owns the
controls, their search anchors, and the stores that keep one profile's choices
independent from another's.

## Settings areas

- **Playback** — external-player handoff, streaming and upscaling choices,
  read-ahead, seek/skip marker defaults, default video zoom and auto-hide,
  lossless audio, subtitles, and player tab/control preferences.
- **Appearance** — light, dark, Pure Black and gradient themes; card style, card
  captions, artwork preference, hero wordmark sizing, and navigation styling.
- **Home** — hero source enablement and ordering, collection/watchlist sources,
  Home row arrangement, library visibility, filtering, and per-row presentation.
- **Libraries** — which libraries appear in navigation, their Recommended pages,
  and the shared Continue Watching choice.
- **Downloads** — cellular policy, storage, quality, artwork refresh, and
  notification behavior.
- **Language and accessibility** — app language, subtitle language and style,
  reduced effects, and Dynamic Type-aware layouts.
- **Diagnostics** — optional crash/performance reporting, playback diagnostics,
  and local log export.
- **Night Shift** — schedule-based display warming, including during playback.

## Ownership and persistence

- Each settings model owns one concern and writes through its existing store.
  Views bind to the model; they do not write another feature's store directly.
- Profile-scoped stores are keyed by the active profile. Changing profiles must
  not leak playback, artwork, subtitle, or navigation choices.
- Settings search entries live in `CoreModels/SettingsSearch.swift`. Every
  interactive control that search can target keeps a stable
  `settingsSearchAnchor` and, where it is inside a lazy list, a matching
  `settingsSearchGroup`.
- Native controls are preferred: `Toggle`, `Picker`, `Stepper`, `Menu`, and
  native navigation. Custom surfaces wrap those controls rather than replacing
  their accessibility or focus behavior.
- A setting that affects playback applies to new playback unless the control
  explicitly documents live reconfiguration.
- Removed features must not leave hidden pages, search entries, or stored keys.
  When a feature is deleted, remove its model, screen, search anchors, and
  migration path together.

## Layout

- Mobile settings use `SettingsPageList`/`SettingsPageScroll` and the shared
  `SettingsPageSurface`; page insets and group spacing come from
  `MobileSettingsMetrics`.
- Described rows use `SettingsDescribedControl`, menus use `SettingsControlMenu`
  with `SettingsMenuLabel`, and explanatory copy uses `settingsHelperText()`.
- Download and server setup pages may use the wider shared form surface, but
  keep native fields, validation, and keyboard behavior.

## Where to look first

- `PlozziOSSettingsView.swift` — app-shell settings navigation and page wiring.
- `PreferenceDetailViews.swift` — playback, subtitle, and appearance detail rows.
- `CardAppearanceControls.swift` — card captions, indicators, and style pickers.
- `HeroSettingsControls.swift` — hero sources, collections, and ordering.
- `HomeRowsSettingsView.swift` — Home row arrangement and per-row controls.
- `ExternalPlayerSettingsView.swift` — external player selection and handoff.
- `Sources/CoreModels/SettingsSearch.swift` — search catalog and anchors.
- `Sources/CoreUI/SettingsPageSurface.swift` — shared settings surfaces and rows.
