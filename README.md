<p align="center">
  <img src="https://raw.githubusercontent.com/brandomoore/brando/main/logos/plozz.svg" alt="Plozz logo" width="96" />
</p>

# Plozz — media player for iPad

> **This fork is iPad-only.** The Apple TV app, Top Shelf extension, and tvOS
> build targets have been removed. The remaining feature set is being trimmed
> toward a focused iPad player for media servers and network shares.

**Free and open source. No ads or paywalls.** Enjoy your movies and shows in one
app built for iPad. Connect **Emby, Jellyfin, Plex and Silo**, or play directly
from **SMB, WebDAV, NFS, SFTP and FTP shares**.

<p align="center">
  <a href="https://apps.apple.com/app/plozz-player/id6782668147"><img src="docs/assets/app-store-badge.svg" alt="Download Plozz Player on the App Store" width="180" /></a>
</p>

<p align="center">
  <a href="https://plozz.app">Website</a> ·
  <a href="https://docs.plozz.app">Docs</a> ·
  <a href="https://plozz.app/discord">Discord</a> ·
  <a href="https://testflight.apple.com/join/EKfReNMu">TestFlight</a>
</p>

## Media servers

<p>
  <a href="https://jellyfin.org"><img src="docs/assets/integrations/jellyfin.png" height="40" alt="Jellyfin" /></a>
  <a href="https://www.plex.tv"><img src="docs/assets/integrations/plex.png" height="40" alt="Plex" /></a>
  <a href="https://emby.media"><img src="docs/assets/integrations/emby.png" height="40" alt="Emby" /></a>
  <a href="https://plozz.app/silo/"><img src="docs/assets/integrations/silo.png" height="40" alt="Silo" /></a>
</p>

**All your media servers and network shares merge together into one library.**
Browse and search everything in one place, without switching between sources.
You can still browse each source separately and pick up where you left off.

## Network shares

<p>
  <a href="https://plozz.app/network-shares/"><img src="docs/assets/integrations/smb.png" height="40" alt="SMB" /></a>
  <a href="https://plozz.app/network-shares/"><img src="docs/assets/integrations/webdav.png" height="40" alt="WebDAV" /></a>
  <a href="https://plozz.app/network-shares/"><img src="docs/assets/integrations/nfs.png" height="40" alt="NFS" /></a>
  <a href="https://plozz.app/network-shares/"><img src="docs/assets/integrations/sftp.png" height="40" alt="SFTP" /></a>
  <a href="https://plozz.app/network-shares/"><img src="docs/assets/integrations/ftp.png" height="40" alt="FTP" /></a>
</p>

Play directly from your NAS or file server over **SMB, WebDAV, NFS, SFTP or FTP**.
Windows shared folders use SMB. If your PC doesn't appear in discovery, enter
its local IP address and use a Windows account that has access to the folder.
Use server-provided or local NFO artwork and details, or browse personal videos
as folders. No media server required.

## Watch and take it with you

| Feature | What you get |
| --- | --- |
| **Video playback** | Pick an audio track, change playback speed and resume where you stopped. Enjoy HDR and surround sound with compatible files and equipment. |
| **Playback shortcuts** | Skip intros and credits yourself or automatically, jump between chapters where available, and choose whether the next episode starts on its own. |
| **Picture in Picture and AirPlay** | Watch while using other apps on iPad, or send video to another screen. Availability depends on how the video plays; separately saved subtitles stay in Plozz. |
| **Subtitles** | Show two tracks at once and adjust their font, size, color, background and position. Search for subtitles when your server supports it. |
| **Versions and quality** | Switch between files or editions on the same server without leaving the player. Choose streaming quality. |
| **Offline downloads** | Save movies and episodes, choose their quality, and browse saved artwork and details without a connection. |
| **Library details** | Explore cast, server-provided ratings, collections and extras, depending on what your server provides. |
| **Watchlists and history** | Keep a watchlist, mark episodes or seasons watched, and optionally sync watch history across servers. |

### Supported formats

| Type | Formats |
| --- | --- |
| **Video files** | MKV, MP4/M4V, MOV, WebM, AVI, MPEG-TS (TS, M2TS, MTS, M2T), MPEG-PS (MPG, VOB), 3GP/3G2, OGG/OGV, ASF/WMV, FLV, RealMedia (RM/RMVB). Decrypted DVD/Blu-ray ISO images and Blu-ray folders. |
| **Video codecs** | H.264/AVC, H.265/HEVC, AV1, VP9, VP8, MPEG-2, MPEG-4 Part 2 (Xvid/DivX), VC-1, WMV 1–3, MS-MPEG4 v1–3, QuickTime RLE, FLV1 (Sorenson Spark), VP6, RealVideo 1–4, H.263, Theora. |
| **Audio codecs** | AAC, HE-AAC/v2, AC-3 (Dolby Digital), E-AC-3 (Dolby Digital Plus, including JOC), TrueHD, MLP, DTS, DTS-HD MA, FLAC, ALAC, MP3, MP2, PCM/LPCM (including G.711), Opus, Vorbis, WMA (Standard, Pro, Lossless, Voice), Nellymoser, ADPCM-SWF, Speex, RealAudio (Cook, ATRAC3, Sipro, Lossless, 14.4/28.8), AMR-NB/WB. |
| **HDR** | HDR10, HDR10+ and HLG. |
| **Dolby Vision** | Profiles 5, 8.1, 8.4 and AV1 10.1 on compatible devices and displays. AV1 profiles 10.0 and 10.4 also need built-in AV1 support in your device's chip. |

Profile 7 (MEL/FEL) plays as HDR10; profiles 8.2 and AV1 10.2 play as SDR.
Without that chip support, AV1 10.4 plays as HLG instead of Dolby Vision,
and 10.0 won't play correctly.

Your file, device, display and speakers all affect playback. TrueHD and DTS-HD MA
play as regular surround audio, not height channels or bitstream passthrough.
Some formats need more processing power; server conversion can change picture
and sound quality. [Format details and limits](https://plozz.app/formats/).

## Make it yours

- **Appearance:** choose light, dark or Pure Black, and make room for more
  posters or bigger artwork. Arrange navigation your way.
- **Circadian mode:** automatically dim and warm Plozz, including video
  playback, from sunset to sunrise or on your own schedule.

## Diagnostics, with your permission

<p>
  <a href="https://sentry.io"><img src="docs/assets/integrations/sentry.png" height="40" alt="Sentry diagnostics" /></a>
</p>

**Optional diagnostics powered by Sentry** help us troubleshoot crashes,
freezes and playback problems. Sharing is **off unless you turn it on** in
Help &amp; Diagnostics. Reports can include app, device and filtered technical
details; messages you send are included as written. No advertising or usage analytics.
[Privacy and diagnostic controls](https://plozz.app/privacy/#diagnostics).

## Get started

Install **[Plozz Player](https://apps.apple.com/app/plozz-player/id6782668147)**
on iPadOS 18 or later, then connect your media server or network share.
**Plozz supplies no movies or subscriptions.** Features vary by device and
service. Your server's access rules and any subscriptions it requires still
apply.

This README covers what's implemented in the code. App Store and TestFlight
releases may be behind.

[Explore features](https://plozz.app/features/) ·
[Supported formats](https://plozz.app/formats/) ·
[Docs](https://docs.plozz.app)

## Help and contribute

[Report a bug or request a feature](https://github.com/brandomoore/Plozz/issues/new/choose) ·
[Build and contribute](.github/CONTRIBUTING.md) ·
[Release notes](https://github.com/brandomoore/Plozz/releases)

Keep passwords, tokens and private server URLs out of public issues.
If Plozz is useful to you, [donations are welcome](https://github.com/sponsors/brandomoore).
It's free either way.

## Contributors

Thank you to the people helping improve Plozz.

<table>
  <tr>
    <td align="center" width="100"><a href="https://github.com/tresby"><img src="docs/assets/contributors/tresby.png" width="64" height="64" alt="" /><br /><sub>tresby</sub></a></td>
    <td align="center" width="100"><a href="https://github.com/kristofferR"><img src="docs/assets/contributors/kristofferR.png" width="64" height="64" alt="" /><br /><sub>kristofferR</sub></a></td>
    <td align="center" width="100"><a href="https://github.com/MargeyShah"><img src="docs/assets/contributors/MargeyShah.png" width="64" height="64" alt="" /><br /><sub>MargeyShah</sub></a></td>
  </tr>
  <tr>
    <td align="center" width="100"><a href="https://github.com/mossline"><img src="docs/assets/contributors/mossline.png" width="64" height="64" alt="" /><br /><sub>mossline</sub></a></td>
    <td align="center" width="100"><a href="https://github.com/moofone"><img src="docs/assets/contributors/moofone.png" width="64" height="64" alt="" /><br /><sub>moofone</sub></a></td>
    <td align="center" width="100"><a href="https://github.com/teymourb"><img src="docs/assets/contributors/teymourb.png" width="64" height="64" alt="" /><br /><sub>teymourb</sub></a></td>
  </tr>
</table>

[Contributions and original references](CONTRIBUTORS.md) ·
[Commit contributors](https://github.com/brandomoore/Plozz/graphs/contributors)

## License and credits

[GPL-3.0](LICENSE) with an [App Store Exception](LICENSE-EXCEPTION.md).
© 2026 Brandon Moore. See [NOTICE.md](NOTICE.md) for bundled software notices.

<details>
<summary>Service acknowledgments and media attribution</summary>

Plozz is an unofficial client and is not affiliated with, endorsed, or certified
by any of the services below.

- **AetherEngine** — on-device playback engine by Vincent Herbst,
  LGPL-3.0 with an App Store exception.
  [superuser404notfound/AetherEngine](https://github.com/superuser404notfound/AetherEngine).
  Its bundled FFmpeg is a decode-only, LGPL-3.0 build (see [NOTICE.md](NOTICE.md)).
- **Plex, Jellyfin, Emby and Silo** — compatible media servers. Names and logos
  belong to their respective owners.
- **Integration badges** — [logo sources and icon licenses](docs/assets/integrations/provenance.json).
  Logos identify compatible services, not sponsorship or endorsement.
  Network formats use generic storage symbols.

</details>

<!-- app-family:start -->
<!-- Generated by https://github.com/brandomoore/brando — edit apps.json there, not this block. -->

---

<p align="center"><b>More open source</b></p>

<p align="center">
  <a href="https://github.com/brandomoore/Hozz" title="Hozz — Apple Health, exported to storage you own"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/brandomoore/brando/main/logos/lockups/hozz-dark.svg" /><img src="https://raw.githubusercontent.com/brandomoore/brando/main/logos/lockups/hozz-light.svg" height="40" alt="Hozz" /></picture></a>
  &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
  <a href="https://github.com/brandomoore/Mozz" title="Mozz — Your music, wherever it lives"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/brandomoore/brando/main/logos/lockups/mozz-dark.svg" /><img src="https://raw.githubusercontent.com/brandomoore/brando/main/logos/lockups/mozz-light.svg" height="40" alt="Mozz" /></picture></a>
  &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
  <a href="https://github.com/brandomoore/Plozz" title="Plozz — Movies &amp; TV on Apple TV, iPhone &amp; iPad"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/brandomoore/brando/main/logos/lockups/plozz-dark.svg" /><img src="https://raw.githubusercontent.com/brandomoore/brando/main/logos/lockups/plozz-light.svg" height="40" alt="Plozz" /></picture></a>
  &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
  <a href="https://github.com/brandomoore/strozz" title="Strozz — Twitch on Apple TV, with real emotes"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/brandomoore/brando/main/logos/lockups/strozz-dark.svg" /><img src="https://raw.githubusercontent.com/brandomoore/brando/main/logos/lockups/strozz-light.svg" height="40" alt="Strozz" /></picture></a>
</p>

<p align="center">
  <a href="https://brando.page">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/brandomoore/brando/main/logos/brando-white.svg" />
      <img src="https://raw.githubusercontent.com/brandomoore/brando/main/logos/brando-black.svg" height="22" alt="Brandon Moore" />
    </picture>
  </a>
</p>
<!-- app-family:end -->
