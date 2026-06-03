# Lyric Floater

A tiny macOS picture-in-picture lyrics window for Spotify.

Lyric Floater stays above your other windows, follows the current Spotify track, and renders synced lyrics in a draggable, resizable floating panel. It is intentionally not a Spotify patch: it reads Spotify's macOS scripting surface and draws its own native window, so it is much less likely to break when Spotify updates.

> Unofficial project. Not affiliated with Spotify or Musixmatch.

## Screenshots

| View | Screenshot |
| --- | --- |
| Album-tinted lyrics | <img src="https://karma-pocket-k6kv.here.now/droppie-2026-06-03T00-28-26Z.png" width="520" alt="Album-tinted Lyric Floater window"> |
| Compact floating panel | <img src="https://emerald-lotus-apye.here.now/droppie-2026-06-03T00-28-20Z.png" width="520" alt="Compact Lyric Floater window"> |
| Large picture-in-picture layout | <img src="https://eternal-rocket-565s.here.now/droppie-2026-06-03T00-25-35Z.png" width="520" alt="Large Lyric Floater window"> |
| Hover tweaks | <img src="https://snowy-sparrow-v28e.here.now/droppie-2026-06-03T00-25-26Z.png" width="520" alt="Hover tweak controls"> |
| Neutral mode | <img src="https://coral-quinoa-2z7g.here.now/droppie-2026-06-03T00-25-25Z.png" width="520" alt="Neutral Lyric Floater window"> |

## Features

- Always-on-top lyrics window that can join all Spaces and full-screen apps.
- Draggable, resizable, borderless native macOS panel.
- Album artwork blur/tint background plus a neutral mode.
- Hover-only tweak controls for background and text size.
- Synced lyrics when available, with a plain-lyrics fallback.
- Responsive typography, top/bottom fade, and saved window position.

## Install

Download `LyricFloater-v0.1.0.zip` from the latest release, unzip it, and open `LyricFloater.app`.

macOS may ask for permission to let Lyric Floater control Spotify. Allow it. The app uses that permission only to read the current track, artist, album, duration, playback position, playback state, and artwork URL.

If macOS blocks the unsigned app, open it from Finder with Control-click -> Open.

## Build From Source

Requirements:

- macOS 13 or newer
- Swift 6 toolchain
- Spotify for macOS

Build and run:

```sh
./script/build_and_run.sh --verify
```

The app bundle is written to:

```sh
outputs/LyricFloater.app
```

## How It Works

Lyric Floater polls Spotify through Apple Events, then asks LRCLIB for matching lyrics. It prefers synced LRC lyrics and falls back to plain lyrics. The floating window is rendered independently with AppKit and SwiftUI.

This keeps the integration stable: the app does not inject code into Spotify, scrape Spotify's private UI, or depend on Spotify's internal view hierarchy.

## Privacy

Lyric Floater has no analytics and stores no listening history. It makes network requests to:

- LRCLIB, to fetch lyrics for the current track.
- Spotify's image CDN, to fetch the current album artwork.

## Limitations

- Lyrics availability depends on LRCLIB.
- Timing can vary when the best available lyrics are not synced.
- This is an unsigned personal build unless you sign/notarize it yourself.
