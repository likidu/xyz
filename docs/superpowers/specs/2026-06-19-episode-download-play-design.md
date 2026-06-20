# Episode page — two-step Download → Play (design)

- **Date:** 2026-06-19
- **Branch / worktree:** `worktree-episode-play`
- **Status:** approved (brainstorming) — ready for implementation plan
- **Design source:** Claude Design project `d80ba09c` ("Xyz for Symbian Belle"),
  files `screens-detail.jsx`, `screens-player.jsx`, `belle.css`.

## Goal

Wire the existing episode detail page's inert "Play" CTA to a real **two-step,
offline-first** flow: the user explicitly **downloads** the episode to device
storage, then **plays** the cached local file. Both download and play are
surfaced on the episode page itself.

This builds on the device-verified download-then-play stack already merged
(`PlayerController`/`EpisodeDownloader`, see DEVICE_NOTES 2026-06-19).

### Success criteria
- A real Xiaoyuzhou episode downloads from the episode page with visible
  progress, then plays the cached local file with audio on device.
- The CTA reflects every state: not-cached → downloading → on-device → playing
  → paused, and a per-episode delete.
- No regressions to Updates/Subscriptions/Self-test or the existing player path.

## Scope

**In:** the episode page CTA region + the data/C++ needed to drive it.

**Out (explicitly, per request):** the docked mini floating player, the
now-playing (Now Playing) page, and the broad downloads manager. Per-episode
delete on the episode page is in (it is part of the design's `.dl-status`).

## Background: what already exists

- `qml/EpisodePage.qml` (PR #3): hero, **inert** `.ep-play` CTA ("player
  deferred"), show notes, top comments, toolbar. Seeded from the tapped Updates
  card via `openWith(item)`, then fetches detail + comments via `xyzApi`.
- `PlayerController` (`player`): `playEpisode(url, eid, title)`, `pause/resume/
  stop/seek`, `state / downloadProgress / position / duration / errorString /
  currentEid / currentTitle / currentSourcePath`. States: Idle, Downloading,
  Preparing, Playing, Paused, Error. Does unified download-**then**-play.
- `EpisodeDownloader`: streams a URL to a public, MMF-readable path, caches by
  `eid` (`<eid>.part` → `<eid>.<ext>`), reuses a completed file, tolerates the
  stale device CA.
- `XyzApiClient` (`xyzApi`): `shapeInboxItem` / `shapeEpisode` — **neither
  exposes an audio URL today.**

## Design (the belle.css states already exist)

`belle.css` has a dedicated "download-to-play (Symbian offline flow)" section.
The states map onto the player:

| Design class | Meaning | Player state / data |
|---|---|---|
| `.dl-btn.idle` (+ `.dl-size`) | "Download" (+ size) | not cached |
| `.dl-btn.busy` (`.dl-fill`, `.dl-pct`, `.dl-x`) | downloading | `Downloading` + `downloadProgress` |
| `.dl-status` (`.ok` ✓, `.sz`, `.del`) | "on device · size · delete" | cached |
| `.ep-play` | "Play" / "Resume" | cached, idle/paused |
| `.ep-play.playing` (`.eq` bars) | playing | `Playing` (and `currentEid === eid`) |

### Component 1 — Data layer (`XyzApiClient` + mock)
- Add **`audioUrl`** to `shapeInboxItem` and `shapeEpisode`, parsed from the
  real episode object's `enclosure.url`.
- Add `enclosure` to `scripts/mock-content.ps1` (inbox items + episode/get) so
  the simulator can exercise the flow.
- **Verify the real field path against the live read-only API before coding**
  (inbox/list / episode/get) — do not trust the mock (mock-diverges lesson).
- `audioUrl` rides through `EpisodePage.openWith(item)` so it is available
  immediately; `xyzApi.episode.audioUrl` is the fallback after the detail fetch.

### Component 2 — C++ player surface (download-only path)
`EpisodeDownloader` — add lookups that do **not** start a transfer:
- `bool isCached(const QString &eid) const`
- `qint64 cachedSizeBytes(const QString &eid) const`
- `bool removeCached(const QString &eid)`

(These resolve the cached path via the existing public-path `audioDir()` probe.)

`PlayerController` — add the two-step verbs (keep `playEpisode` for the Play
step; it finds the cache and plays instantly):
- `Q_INVOKABLE void download(const QUrl &url, const QString &eid)` — download
  **only**; a new `m_downloadOnly` flag prevents the auto-play fall-through.
- `Q_INVOKABLE void cancelDownload()`
- `Q_INVOKABLE bool isDownloaded(const QString &eid) const`
- `Q_INVOKABLE QString downloadedSizeText(const QString &eid) const`
- `Q_INVOKABLE void deleteDownload(const QString &eid)`
- A signal so QML re-evaluates "downloaded" when a download finishes (e.g.
  `downloadFinished(eid)` / reuse `stateChanged`).

### Component 3 — `EpisodePage.qml` CTA region
Replace the inert `.ep-play` block with a state-driven CTA:

| State | Renders | Tap action |
|---|---|---|
| not cached | `.dl-btn.idle` "Download" | `player.download(audioUrl, eid)` |
| downloading | `.dl-btn.busy` (fill=`downloadProgress`, `%`, ✕) | ✕ `player.cancelDownload()` |
| cached, idle/paused | `.ep-play` "Play"/"Resume" + `.dl-status` "✓ On device · size · Delete" | Play `player.playEpisode(audioUrl, eid, title)`; Delete `player.deleteDownload(eid)` |
| playing | `.ep-play.playing` (equalizer) | `player.pause()` |

- **Guard:** playing/paused render only when `player.currentEid === page.eid`;
  otherwise a cached episode shows "Play".
- QML 1.1 rules apply: no block bindings (use helper functions/ternaries),
  functions declared at `Page` root, no negative anchor margins.

### Component 4 — Icons / theme
- Tokens already align with `belle.css` (cosmic-violet) via `js/Theme.js`;
  reconcile any missing tokens (accent/accent-bright/accent-deep, hairline).
- New SVGs: download, cancel (✕), check (✓), trash/delete, pause. Existing:
  play, heart. Equalizer = animated QML `Rectangle`s (no SVG). Follow the SVG
  viewBox sizing rule for any new icon.

## Key decisions
- **No auto-play after download** — strict two-step.
- **Size** comes from the on-disk file after download; pre-download the button
  is just "Download" (no guessed size) unless the live API gives a reliable
  size.
- **No seek bar / elapsed time** on the episode page — Play is a play/pause
  toggle; scrubbing belongs to the out-of-scope now-playing page.
- **Per-episode Delete** included; broad downloads manager excluded.
- **Cancel** during download included.

## Risks / verification
- Audio URL field path confirmed against the live API before coding.
- `player` is a single shared controller — bind by `eid` to avoid showing
  another episode's playing state.
- RVCT toolchain is not runnable in this environment; the user verifies on
  device. Audio is fragile (MMF) — a phone reboot may be needed before trusting
  a failure (DEVICE_NOTES 2026-06-19). Record any audio experiment in
  DEVICE_NOTES.md.

## Open items (resolve during implementation)
- Exact `enclosure` field path + whether the API exposes a reliable byte size.
- Whether `audioUrl` is present on inbox items or only on episode detail (drives
  whether Download can start before the detail fetch completes).
