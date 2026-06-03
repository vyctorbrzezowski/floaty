# Floaty

A tiny macOS picture-in-picture lyrics window for Spotify.

Floaty stays above your other windows, follows the current Spotify track, and renders synced lyrics in a draggable, resizable floating panel. It reads Spotify's macOS scripting surface and draws its own native window, so it does not depend on Spotify's internal UI.

Built after one too many Foo Fighters listening sessions. It floats, follows the song, and stays out of the way.

> Unofficial project. Not affiliated with Spotify, Foo Fighters, Musixmatch, or LRCLIB.

## Screenshots

| View | Screenshot |
| --- | --- |
| Neutral dark mode | <img src="https://karma-pocket-k6kv.here.now/droppie-2026-06-03T00-28-26Z.png" width="520" alt="Floaty in neutral dark mode over a forest desktop wallpaper, showing wrapped Spotify lyrics"> |
| Album blur mode | <img src="https://emerald-lotus-apye.here.now/droppie-2026-06-03T00-28-20Z.png" width="520" alt="Floaty using blurred album artwork colors behind synced Spotify lyrics"> |
| Compact window | <img src="https://eternal-rocket-565s.here.now/droppie-2026-06-03T00-25-35Z.png" width="520" alt="Small Floaty picture-in-picture lyrics window with two wrapped lyric lines"> |
| Hover tweaks | <img src="https://snowy-sparrow-v28e.here.now/droppie-2026-06-03T00-25-26Z.png" width="520" alt="Floaty hover menu with Album, Neutral, and small, medium, large text controls"> |
| Small album-tinted window | <img src="https://coral-quinoa-2z7g.here.now/droppie-2026-06-03T00-25-25Z.png" width="520" alt="Compact album-tinted Floaty lyrics window with the hover menu button visible"> |

## Why Floaty?

Spotify has lyrics, but not a small native floating lyrics window for macOS. Floaty gives you a picture-in-picture style lyrics overlay that can sit beside your work, on top of full-screen apps, or tucked into a corner.

Good for:

- Spotify lyrics in a floating macOS window
- Picture-in-picture lyrics while working
- Always-on-top synced lyrics
- Menu bar lyrics companion with no Dock icon
- Minimal lyrics overlay with album artwork colors

## Features

- Always-on-top lyrics window that can join all Spaces and full-screen apps.
- Menu bar app: no Dock icon.
- Draggable, resizable, borderless native macOS panel.
- Album artwork blur/tint background plus a neutral mode.
- Hover-only tweak controls for background and text size.
- Synced Spotify lyrics when available, with a plain-lyrics fallback.
- Responsive typography, full-line wrapping, top/bottom fade, and saved window position.
- Native Swift, AppKit, and SwiftUI implementation.

## Install

Download `Floaty-v0.1.0.zip` from the latest release, unzip it, and open `Floaty.app`.

macOS may ask for permission to let Floaty control Spotify. Allow it. The app uses that permission only to read the current track, artist, album, duration, playback position, playback state, and artwork URL.

If macOS blocks the unsigned app, open it from Finder with Control-click -> Open. Floaty lives in the menu bar; use the music note icon to show, hide, or quit the floating window.

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
outputs/Floaty.app
```

## How It Works

Floaty polls Spotify through Apple Events, then asks LRCLIB for matching lyrics. It prefers synced LRC lyrics and falls back to plain lyrics. The floating window is rendered independently with AppKit and SwiftUI.

This keeps the integration stable: the app does not inject code into Spotify, scrape Spotify's private UI, or depend on Spotify's internal view hierarchy.

## Privacy

Floaty has no analytics and stores no listening history. It makes network requests to:

- LRCLIB, to fetch lyrics for the current track.
- Spotify's image CDN, to fetch the current album artwork.

## Limitations

- Lyrics availability depends on LRCLIB.
- Timing can vary when the best available lyrics are not synced.
- This is an unsigned personal build unless you sign/notarize it yourself.

## Search Terms

Spotify lyrics picture-in-picture, macOS Spotify lyrics, floating lyrics window, menu bar lyrics app, synced lyrics overlay, SwiftUI lyrics app, always-on-top lyrics for Spotify.
