# FeaturePlayback

Video playback for the iPad app: engine selection, transport state, subtitle
rendering, Picture in Picture, AirPlay, skip markers, diagnostics, and the
player chrome.

## Engine boundary

- `PlayerViewModel` is the single playback authority. Views send intents; the
  model owns the current request, engine attachment, transport state, tracks,
  and teardown order.
- `NativeVideoEngine` drives AVPlayer-backed playback, Picture in Picture,
  native subtitles, and local/remote assets. `AetherEngine` drives formats that
  need the bundled decode path.
- Engine selection is based on the request and capabilities, not on which view
  is presenting. A replacement engine or player must preserve the current
  transport position, play intent, track choices, and PiP/background policy.
- `stop()` is terminal. A stopped view model or output surface must not be
  resurrected by a late load, notification, or track callback.

## Transport and presentation

- Play, pause, seek, scrub, speed, audio/subtitle selection, and skip actions
  all go through the model. Cancellation and superseded requests are not
  success; they leave the previous stable state in place.
- Resume position is written only for playable, authorized media and never for
  trailers, extras, or failed loads.
- PiP keeps playback alive only when the platform and current route allow it.
  Background audio and PiP share the same explicit policy switches; neither is
  inferred from a transient app lifecycle notification.
- AirPlay and external playback report their route through the existing
  `externalPlaybackRouteName` path. Losing a route restores local playback
  without discarding progress.

## Subtitles

- Native subtitles use `AVPlayerItemLegibleOutput` and the shared subtitle
  style model. Sidecar files remain local files; they must not be converted to
  an injected HLS segment when the source is a local asset.
- Remote subtitle search and download stay behind the provider capability.
  Unsupported providers fail explicitly instead of returning an empty list.
- Subtitle timing, position, font, size, color, background, and secondary-track
  choices are profile-scoped and apply to new playback.

## Skip markers

- Skip-intro/credits/recap/preview/commercial behavior is stored per content
  category with an optional per-marker rule. The default page edits inherited
  timing; the content page edits exceptions.
- A manual skip button, an automatic delay, and instant skip are mutually
  exclusive modes. The player shows the mode the model resolves, not a
  separately cached copy.
- Community marker services are not bundled. Only markers provided by the
  server or local metadata are used.

## Player chrome

- The player owns one timeline, one control surface, and one track menu.
  Orientation changes, PiP, external playback, and engine replacement must not
  create a second control surface.
- Native alerts, menus, and sheets are preferred for destructive actions and
  track selection.
- Playback diagnostics are opt-in and use the secret-safe `PlozzLog` path.
  Do not log credentials, full stream URLs, or subtitle contents.

## Where to look first

- `PlayerViewModel.swift` — playback authority and lifecycle.
- `NativeVideoEngine.swift` — AVPlayer, PiP, native subtitles, and local assets.
- `PlayerControls.swift` — timeline and transport chrome.
- `SubtitleStylePanel.swift`, `SubtitleStyleStore` — subtitle presentation.
- `CastPanelView.swift` — audio/subtitle track menus.
- `PlaybackDiagnostics.swift` — counters and local diagnostics.
