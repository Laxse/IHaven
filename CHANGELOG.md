# Changelog

## 2.0 — a complete rewrite

**Released:** 2026-10-20 · **Requires:** macOS 26.0 or later · **Runtime:** Swift 6 / SwiftUI

IHaven 2.0 is not an update to the 2020 client — it is a replacement. The old Xcode project
(`IHaven/` + `IHaven.xcodeproj`) has been deleted, and the app is now a Swift Package Manager
target built against the macOS 26 SDK under Swift 6 strict concurrency. 180 commits since `1.2`.

### Highlights

- **Masonry browse grid** with true mixed aspect ratios and infinite scroll, backed by a
  disk-backed image cache (Nuke `DataCache`, 512 MB) — a wallpaper you have already seen is never
  downloaded twice
- **Detail page**: the complete image (never cropped), a 300 px metadata sidebar, tags, uploader,
  palette, download original, set as wallpaper, crop, add to album
- **Crop before you set**: a draggable box locked to your screen's aspect ratio, so a portrait
  wallpaper never ends up with black bars down the sides
- **Menu bar panel** for the things you do ten times a day — current wallpaper, search,
  previous / next, one-click shuffle, favorites, and a way back to the main window
- **Dynamic wallpapers you render locally**: breathe / pan / push-in, seamless loops, no video file
  involved. Optionally, six image-to-video vendors can supply the motion (each billed against its
  own key)
- **Albums and Timeline**: a second organizing layer on top of favorites, plus your applied history
  regrouped by day
- **Chinese (Simplified) and English**, following your system language or a manual override

### Browse

- Rich filters — resolution, aspect ratio, dominant colour, category, purity, sorting, time range —
  with 150 ms debounced re-query
- Instant low-resolution preview that swaps to the full-resolution original, with a visible download
  progress bar so "still loading" is distinguishable from "this image is soft"
- Offline fallback: when the network is unavailable, an already-cached original is reused instead of
  failing
- Correct pagination boundary (`meta.lastPage`), so a result set shorter than one page no longer
  leaves a spinner running forever

### Set as wallpaper

- Per-screen assignment and a fill mode, with a fill colour derived from the wallpaper's own palette
- Favorites library and an applied history, both stored locally in SQLite
- Albums — one wallpaper can live in several albums at once
- Timeline — see what you had when, and re-apply it

### Dynamic wallpapers

- Any static image becomes a locally rendered, seamless-looping dynamic wallpaper (JPEG frame
  sequence). No video import, no video playback
- **AI-generated motion (optional)**: pick one of six vendors — Google Veo, MiniMax Hailuo, Vidu,
  Alibaba Wan, Volcano Seedance, Kuaishou Kling — add that vendor's own API key in Settings ▸ AI,
  and IHaven turns the clip into a dynamic wallpaper. Generation is cancellable
- Performance guard: auto-pauses when the frontmost app is full screen, on low battery, or in Low
  Power Mode, with a visible CPU / memory readout

### Automation

- Menu bar panel, plus a global hotkey `⌥⌘S` to shuffle to a new wallpaper from anywhere
- Rotation schedule: switch by time of day or weekday, per display, drawing from imported files,
  your applied history, favorites, or an album
- Client-side rate limiting (45 req/min token bucket) with exponential backoff, so the app never
  trips wallhaven's limits on your behalf

### Your own images

- Import your own pictures and manage them in a dedicated **Import…** tab. They are deliberately
  kept out of the wallhaven grid — local files carry no category, tag, or search relevance there

### Fixes worth calling out

Fixes users actually hit, in rough order of how much they hurt:

- Text fields could not be typed into anywhere in the app — a global hotkey was installing a local
  `keyDown` monitor that sat on the key delivery chain. Hotkeys now go through the app menu in the
  foreground and an `NSEvent` global monitor in the background
- Nothing happened when clicking a tag or "More like this" from Favorites / Applied / Timeline /
  Albums: those tabs render local collections, so the search results had nowhere to appear. Tag
  searches now land on Discover
- Imported images opened from Timeline showed "this wallpaper no longer exists" — their id is a
  UUID, so the wallhaven detail request 404'd and the 404 was read as "removed". Local imports no
  longer make that request, and the sidebar shows real filesystem values instead of a bogus red
  NSFW badge
- "Download original" on an imported image could delete or move your own file out of the library
- Vertical images were cropped in the detail view; returning from the detail view lost the grid's
  scroll position
- Switching sidebar categories left the detail page open on top of the new content
- Infinite scroll stopped after the first page; the grid could collapse or overlap at some window
  sizes
- The `general` category was mislabelled "Scenery" — it is everything that is neither anime nor
  people, and is now "General"
- API key moved out of the Keychain to `~/.ihaven/apikey`, which removes the keychain prompt on
  launch

### Breaking changes

- **macOS 26.0 or later is required.** IHaven 1.x will not run on it, and 2.0 will not run on older
  systems
- **Nothing migrates from 1.x.** Your 2.0 API key, favorites and history start empty
- **Video-based dynamic wallpapers are gone** (ADR-016). Dynamic wallpapers are now rendered locally
  from a still image; to play a local video as your desktop, use the system dynamic desktop
- **The project is SwiftPM-only.** There is no `.xcodeproj`; open `Package.swift`

### Known limitations

- Only Volcano Seedance (Volcano Ark) has been verified end to end with a real key. Google Veo,
  MiniMax, Vidu and Alibaba Wan have never been exercised against a live key, and Kling's request
  body is unverified
- Volcano Ark rejects a source image whose short side is under 300 px
- Per-screen wallpapers need "Displays have separate Spaces" enabled in System Settings ▸ Desktop &
  Dock. Changing that setting requires logging out and back in
- The build is ad-hoc signed (no Developer ID), so macOS will ask you to right-click and Open the
  first time

### Installing

Download `IHaven.app` from the assets below and drag it into `/Applications`. An API key is optional
but unlocks NSFW purity levels and your account's default filters; paste it into
Settings ▸ API Key, where it is stored at `~/.ihaven/apikey` and sent as an `X-API-Key` header.

Full documentation: see [`README.md`](README.md).
Architecture and decision records: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) and
[`docs/decisions/`](docs/decisions/).
