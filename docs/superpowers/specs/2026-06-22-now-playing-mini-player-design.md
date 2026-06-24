# Now Playing Page + Mini Floating Player — Design

**Date:** 2026-06-22
**Status:** Approved (design), pending implementation
**Target device:** Nokia C7/X7-00 class (Symbian Belle), 360×640 nHD, self-signed SIS
**Design source:** Claude Design project "Xyz for Symbian Belle" — `screens-player.jsx`,
mini player in `belle.css` (`.player`, `.miniplayer`).

## Problem

Playback today is driven only from `EpisodePage.qml`: its CTA morphs
download → downloading → play → equalizer inline. There is **no full-screen Now Playing
view** and **no persistent player surface** — once you leave the episode you were playing,
there is no way to see what's playing or control it. The design supplies two pieces that
close this gap:

- a **Now Playing** screen (cover, scrubber, transport, meta chips), and
- a **mini player** docked above the bottom bar that appears whenever something is playing
  and expands to Now Playing on tap.

## Goal

Implement both surfaces, wired to the existing `player` (PlayerController) seam:

- **`NowPlayingPage.qml`** — a pushed page mapping 1:1 to `belle.css .player`.
- **`MiniPlayer.qml`** — a reusable 56px dock bound to `player`, shown on the tab landing
  pages (Updates, Subscriptions, Me) **and** the Episode detail page, expanding to Now
  Playing on tap.

Non-goals (YAGNI): playback-speed control, a queue/up-next screen, comments from the
player, scrubber waveform, gestures beyond tap. These appear as **static placeholders** so
the screen matches the mock, and are wired later.

## Decisions (from brainstorming)

1. **Now Playing presentation:** a **pushed `Page`** (like `EpisodePage`), header lead is a
   **down-chevron** that `pageStack.pop()`s — not a custom slide-up sheet. Consistent with
   the existing PageStack nav; lowest Symbian risk.
2. **Mini player scope:** tab landing pages **and** Episode detail. Built once as a
   reusable `MiniPlayer.qml`.
3. **Speed chip + bottom toolbar (list/comment/headphones):** static, non-interactive
   placeholders. `AudioEngine` has no playback-rate API and Symbian MMF generally ignores
   `setPlaybackRate`, so `1.x×` is display-only.

## Current state (verified)

- `player` (PlayerController) is registered via `setContextProperty` (`main.cpp:438`) and
  exposes `state`, `position`, `duration`, `currentEid`, `currentTitle`,
  `playEpisode/pause/resume/stop/seek`, and the download helpers. State enum:
  `Idle/Downloading/Preparing/Playing/Paused/Error`.
- `playEpisode(url, eid, title)` is called from **one place** — `EpisodePage.qml:306`.
  PlayerController tracks only `currentEid`/`currentTitle`; it has **no cover or show name**,
  which the player surfaces need.
- Bottom nav is a **per-page `BelleTabBar`** (content anchors to `tabBar.top`); confirmed in
  `UpdatesPage.qml`, `SubscriptionsPage.qml`, `HomePage.qml`. `EpisodePage` has no tab bar
  (`hidesToolBar: true`), its `Flickable` fills to `parent.bottom`.
- `BelleHeader.qml` hardcodes `gfx/icon-back.svg` as its lead icon.
- Icon assets present: `icon-chevron-down.svg`, `icon-play.svg`, `icon-play-white.svg`,
  `icon-list.svg`, `icon-comment.svg`, `icon-check.svg`, `icon-queue.svg`,
  `tab-headphones.svg`. **Missing:** pause + rewind/forward glyphs.

## Design

### Components

**1. `src/PlayerController.{h,cpp}` — the only backend change**

Carry cover + show through the single source of truth so both surfaces can render identity:

- Add read-only properties `currentCoverUrl` (QString) and `currentShow` (QString) with
  `currentCoverUrlChanged` / `currentShowChanged` signals, mirroring `currentTitle`.
- Extend the signature:
  `playEpisode(const QUrl &url, const QString &eid, const QString &title, const QString &coverUrl, const QString &show)`.
  Set/emit `m_currentCoverUrl` and `m_currentShow` alongside `m_currentTitle` (same guarded
  pattern as `PlayerController.cpp:51–52`).
- Update the lone caller, `EpisodePage.qml:306`, to pass `page.coverUrl` and `page.showTitle`.

No change to the download/seek/state machine.

**2. `qml/BelleHeader.qml` — backward-compatible tweak**

Add `property string leadIconSource: "gfx/icon-back.svg"` and bind the lead `Image.source`
to it. Existing pages are unaffected; `NowPlayingPage` passes `"gfx/icon-chevron-down.svg"`.

**3. `qml/NowPlayingPage.qml` — new pushed page** (`hidesToolBar: true`)

Maps to `belle.css .player`:

- `BelleHeader` — title `qsTr("Now Playing")`, `leadIconSource: "gfx/icon-chevron-down.svg"`,
  `onBackClicked: pageStack.pop()`, no action icon.
- **Cover** 208×208, radius 12: violet gradient `Rectangle` with an `Image`
  (`player.currentCoverUrl`, `PreserveAspectCrop`) on top — same construction as the
  EpisodePage hero cover.
- **`pl-show`** → `player.currentShow`; **`pl-title`** → `player.currentTitle` (centered).
- **Scrubber:** track + fill = `position/duration`; a draggable knob whose release calls
  `player.seek(value)` (MMF-safe — goes through C++, never touches a QML `Audio.position`).
  Time row: elapsed `mmss(position)` left, `-mmss(duration-position)` right.
- **Transport:** rewind-15 (`seek(max(0, position-15000))`), big play/pause
  (72px gradient circle; `player.state === playingState ? pause() : resume()`,
  icon toggles play/pause-white), forward-30 (`seek(min(duration, position+30000))`).
- **Meta chips:** "On device" (`icon-check` + `t(onDevice)`, accent — always true on this
  path), `1.0×` speed chip (static), comment chip (static).
- **Bottom toolbar:** three inert glossy icons — list / comment / headphones.

Helper functions (`mmss`, transport math) declared at `Page` root only (QML 1.1 rule).

**4. `qml/MiniPlayer.qml` — new reusable dock** (56px)

Bound entirely to `player`; the host page only positions it and handles its one signal.

- `visible: player.currentEid !== "" && (player.state === player.preparingState ||
  player.state === player.playingState || player.state === player.pausedState)`.
- Layout (`belle.css .miniplayer`): 38px cover thumb (`currentCoverUrl`),
  `mini-title` = `currentTitle`, `mini-time` = `mmss(position) / mmss(duration)`,
  a 38px play/pause toggle (`pause()`/`resume()`), a static queue icon.
- `signal expandRequested`. A full-width `MouseArea` **behind** the play button emits it
  (the play button's own `MouseArea` sits on top — same layering rule as the Updates row
  tap target). Play/pause does not bubble to expand.

**5. Navigation wiring**

- Each host page gains `signal openPlayerRequested` and connects
  `miniPlayer.onExpandRequested: page.openPlayerRequested()`.
- `AppWindow.qml` owns **one** `NowPlayingPage { id: nowPlayingPage }` and pushes it from
  each page's `onOpenPlayerRequested` (same pattern as `episodeRequested` →
  `pageStack.push(episodePage)`), guarding against double-push when it's already current.

**6. Host-page embedding** (`UpdatesPage`, `SubscriptionsPage`, `HomePage`, `EpisodePage`)

- Add `MiniPlayer { id: miniPlayer }` docked at the bottom: on tab pages
  `anchors.bottom: tabBar.top`; on Episode `anchors.bottom: parent.bottom`.
- Re-anchor the scrolling content's bottom to
  `miniPlayer.visible ? miniPlayer.top : <tabBar.top | parent.bottom>` so the list/flick
  region shrinks when the dock appears and never hides content behind it.

**7. New assets** (`qml/gfx/`, registered in `qml/qml.qrc`)

`icon-pause-white.svg` (big button), `icon-pause.svg` (mini), `icon-rewind.svg`,
`icon-forward.svg` (the `15`/`30` render as a `Text` overlay per the mock), and a small
`icon-speed.svg` for the chip. SVGs follow the project rule: size via the `viewBox`, not
`width`/`height`.

### Data flow

```
tap mini player
  → host page.openPlayerRequested()
  → AppWindow pushes nowPlayingPage
  → NowPlayingPage binds player.{currentCoverUrl,currentShow,currentTitle,position,duration,state}

scrubber drag release / skip / play-pause
  → player.seek(ms) | player.pause() | player.resume()
  → AudioEngine (QMediaPlayer) — position written in C++ only
  → positionChanged/stateChanged propagate back to both surfaces
```

### Error handling / edge cases

- **Idle / nothing playing:** mini player hidden; Now Playing unreachable (only entered via
  the dock), so it never renders an empty state.
- **Duration not yet known** (`duration === 0` during Preparing): scrubber fill clamps to 0,
  knob disabled, right time shows `--:--`; re-binds when `durationChanged` fires.
- **Seek while paused/preparing:** `player.seek` already guards `m_audio`; safe.
- **Same episode open in EpisodePage while it plays:** the inline CTA equalizer and the dock
  both show — accepted (the chosen "tab pages + Episode detail" scope).

## Verification

1. **Simulator build compiles and runs** (raster, 360×640) with the new C++ signature and
   QML — primary regression guard for the host build.
2. **Interactive flow in the Simulator** (per the project's "verify QML flow interactively"
   rule — build + static review is not enough): play an episode from Episode detail →
   confirm the dock appears with cover/title/time and a working play/pause → tap it →
   Now Playing opens with correct identity, the scrubber tracks position, skip ±15/30 move
   playback, play/pause toggles, the down-chevron pops back. Capture a screenshot of the
   running Simulator.
3. **On device (later):** confirm scrubber seek and skip behave on MMF; log anything odd in
   `docs/DEVICE_NOTES.md` under a dated heading.

## Risks / open items

1. **Scrubber seek on MMF.** Dragging then `seek()` is the one new playback interaction.
   `AudioEngine.seek` + `seekable` already exist (used by the engine); confirm on device a
   mid-file seek doesn't stall MMF. Log to DEVICE_NOTES.
2. **`playEpisode` signature change.** Q_INVOKABLE arity changes; the single QML caller is
   updated in the same change. Grep confirms no other caller.
3. **Cover art over HTTPS.** Now Playing reuses the existing `Image` + `SslIgnoringNam`
   path already used for covers elsewhere — no new network handling.
4. **Mini player re-anchoring.** Four pages get the same bottom re-anchor; verify each
   page's content bottom follows `miniPlayer.visible` and nothing clips behind the 56px dock.
