Symbian Belle Device Notes
==========================

Hardware: Nokia C7 (Belle FP2)

## 2026-06-27 — Pigler now-playing notification: tap dismissed it (server default is remove-on-tap)

**Feature:** now-playing notification via the Pigler Notifications API (PNA), driven by
`NowPlayingNotifier` (state-keyed: shown while `Playing`/`Paused`, removed on stop/close).
Requires the user-installed `Pigler.sis` server (nnproject.cc/pna).

**Device test (first run, Pigler.sis installed):** notification **pops up** correctly with the
episode title/show, and tapping it **does foreground the app** (so `setLaunchAppOnTap(true)`
works). **Bug:** the tap also **dismissed the notification even though the episode kept
playing** — it stayed gone (no recreate) until the next play/pause transition.

**Root cause:** Pigler's server creates a notification with `removeOnTap` defaulting to **true**
(standard notification-center behaviour). `PiglerAPI::SetNotification` (our create path) only
sends the text — it does not set `removeOnTap` — so we inherited the server default. Our client
never called `setRemoveOnTap`. A tap therefore told the server to delete the item; foregrounding
the app triggers no playback-state change, so `NowPlayingNotifier::refresh()` is never re-invoked
and the notification is not recreated while playback continues.

**Fix:** in `NowPlayingNotifier::refresh()`, immediately after `setLaunchAppOnTap(m_notifId, true)`
on the create path, also call `m_api->setRemoveOnTap(m_notifId, false)`. The notification now
persists across a tap and is removed only when playback leaves `Playing`/`Paused` (stop/idle) or
the app closes.

**Status:** **Confirmed fixed on device (2026-06-27).** After the fix, tapping the notification
foregrounds the app and opens the episode page, and the notification **persists** while playback
continues; it is removed on Stop as expected. Builds `armv5 udeb` (RVCT 4.0) cleanly.

## 2026-06-27 — Side volume keys needed "warm-up" presses: RemCon target registered before foreground

**Symptom (device):** the side volume rocker controls playback volume (see 2026-06-22), but
on a fresh launch the **first few presses do nothing — both up AND down** — then it suddenly
starts working and is fine for the rest of the session.

**Root cause:** `VolumeKeyCapturer::NewL()` (which calls `CRemConInterfaceSelector::OpenTargetL()`)
ran in `main()` **before `view.show()`**, i.e. before the app had a foreground window group.
Symbian's RemCon routing (the Target Selector Plugin) delivers the rocker's media keys to the
**foreground app's** registered target; registering before the window is foreground means the
TSP doesn't route the keys to us until focus re-resolves — which only happens after the first
press(es). Both directions being dead (not just up) is what distinguishes this from the
unrelated quirk below. The Qt Wiki RemCon sample has the same early-registration shape and
doesn't address it.

**Fix:** moved the `#ifdef Q_OS_SYMBIAN` `VolumeKeyCapturer::NewL(&audioEngine)` block in
`src/main.cpp` to **after `view.show()`**, preceded by `QApplication::processEvents()` so the
window-server foreground event is delivered before we `OpenTargetL()`. Added a `qDebug` in
`MrccatoCommand` so `xyz.log` shows `VolumeKeyCapturer: command op=.. action=..` — use it to
confirm commands now arrive **from the first press**.

**Status:** compiles for `armv5 udeb` (RVCT 4.0) cleanly; **pending on-device confirmation** on
the X7-00. To verify: fresh launch, start playback, press the rocker once, check `xyz.log` for
the command line on the very first press (volume should also step). If warm-up persists, the
log will show whether `MrccatoCommand` fires during the dead presses — if it still doesn't,
the next step is to defer registration to a `QTimer::singleShot(0, …)` after the event loop
starts rather than just `processEvents()`.

**Separate latent quirk (not this bug):** `AudioEngine` starts `m_volume = 1.0` (max) and
`setVolume()` early-returns when unchanged, so on a fresh start **Volume Up is a no-op until
you've pressed Down once**. There is no QML volume UI, so the rocker is the only control.
Left as-is (changing the default startup loudness is a UX call); flagged in case it confuses
verification — test with Volume Down, or rely on the `xyz.log` line which logs regardless.

## 2026-06-26 — Discovery: real feed is a loadMoreKey walk with several entry types

**Symptom (device, after the nesting fix below):** only one section (an editor-pick
collection) rendered. Pulled the **live** `/v1/discovery-feed/list` using the simulator's
stored token (logged in on the sim, read `auth.accessToken` from
`%LOCALAPPDATA%\Nokia\QtSimulator\data\xyz.db`, replayed the call from PowerShell with the
iOS-spoof headers). The live feed is **nothing like the proxy doc**:

1. **It's a `loadMoreKey` pagination walk, not 3 fixed selector keys.** Real cursors:
   page0 → `topList` → `discoveryTopic` → `pick` → end (empty key). Our hardcoded
   `mediumDiscoveryPictorial` is **stale and returns HTTP 400**, so Hottest never loaded.
   `discoveryTopic` still happened to be a valid cursor, which is why one section showed.
2. **Sections arrive as several entry types**, each `{type, data}`, only one of which we
   parsed:
   - `DISCOVERY_EPISODE_RECOMMEND` — `data{title:"为你推荐", targetType, target[].episode}`
   - `EDITOR_PICK` — `data{picks[].episode}` (no title → hardcode 编辑精选)
   - `TOP_LIST` — `data[]{title, items[].item}` (boards 最热榜 / 锋芒榜 / 新星榜)
   - `DISCOVERY_COLLECTION` — `data[]{title, targetType, target[].episode}` (the only one
     we had handled); also carries PODCAST modules we skip.
   - skipped: `DISCOVERY_HEADER`, `DISCOVERY_PICTORIAL`, `CATEGORY_ENTRANCE`, `NEW_POWER`,
     `DISCOVERY_PICK`, `ONBOARDING_PROMPT`, `DISCOVERY_BANNER`, `PILOT`.

**Fix (commit cbd7b3b):** `fetchDiscovery` now walks the feed following `loadMoreKey`
(capped at 6 pages), accumulating EPISODE sections; `shapeDiscoverySections` handles all
four entry types via a shared `appendEpisodeSection` helper (note the differing episode
key: `episode` for target/picks, `item` for top-list rows). The mock was rewritten to the
real 4-page walk so it can't mask this again. **Verified against the LIVE API in the
simulator: pages=4, sections=6** (为你推荐 / 编辑精选 / 最热榜 / 锋芒榜 / 新星榜 / a topic
collection). Lesson: don't trust the proxy doc for discovery shapes — replay the live call
with a sim token. Still pending: device re-test to confirm the visual render.

## 2026-06-26 — Discovery empty on device ("Nothing to discover yet") — response nesting fix

**Symptom (real device):** Discovery rendered the empty state. Diagnosis: a 2xx came back
(so `discoveryLoaded` fired and `loadedOnce` latched) but `shapeDiscoverySections` parsed
**zero** sections. Reproduced in-sim with a temporary section-count log: `sections=0
buckets=0/0/0 anyOk=1`.

**Root cause:** the real upstream `/v1/discovery-feed/list` returns feed entries directly
under the **top-level `data`** key (`{"data":[ {type:DISCOVERY_COLLECTION, data:[modules]}, … ],
"loadMoreKey":…}`) — single-nested, exactly like inbox/subscription. Our `shapeDiscoverySections`
read **`data.data[]`** (double-nested), which I'd copied from the ultrazg/xyz proxy **doc**. That
doc double-wraps because the proxy's `utils/response.go` `ReturnJson` nests the *entire* upstream
body under another `data` (`{code,msg,data:<upstreamBody>}`) — a **proxy artifact**, not the real
shape. So `top.data` was a list, `.toMap()` was empty, and nothing parsed. The Task-2 mock encoded
the *same* proxy shape, so the sim passed while the device failed.

**Fix (commit 8b814cd):** read entries from top-level `data[]`, with a `data.data[]` fallback for
robustness; corrected the mock to the real single-nested shape. Re-verified in-sim: `sections=4
buckets=2/1/1`. **General rule for this proxy: a doc that shows `data.X` means the real upstream
returns `X` at top level — strip one `data` when porting, and build mocks to the real upstream
shape.** Still pending: a real-device re-test to confirm the fix end-to-end.

## 2026-06-25 — Discovery page (multi-section discovery-feed), simulator data-path verified

Added the Discovery tab (compass / index 0, previously inert). `xyzApi.fetchDiscovery()`
chains **3 sequential** `POST /v1/discovery-feed/list` calls — default, then
`loadMoreKey:"discoveryTopic"`, then `loadMoreKey:"mediumDiscoveryPictorial"`. Sequential,
not concurrent, because `XyzApiClient` is single-reply (`m_reply` + `abortActiveRequest()`
cancels any in-flight call); a small phase counter (`finishDiscoveryPhase`) advances 0→1→2
and emits `discoveryLoaded()` once at the end. **Episode-only:** only `targetType=="EPISODE"`
modules become sections; PODCAST modules and `NEW_POWER`/etc. entries are skipped (there is
no podcast detail page). The response is **double-nested** (`data.data[].data[].target[].episode`),
unlike inbox's single `data[]`. Each episode is shaped to a superset of `EpisodePage.openWith`'s
seed so cards tap straight through.

**Verification (simulator, against `scripts/mock-content.ps1` with a body-aware discovery
branch):**
- Built the sim target clean; launched `Xyz.exe` via the generated `Xyz.run.ps1` with
  `XYZ_API_BASE=http://localhost:8099` and a temporary `initialPage: discoveryPage` (reverted
  after) to open straight onto Discovery.
- App init log reached `[IMPORT PATHS]` with **no QML load error**, i.e. `DiscoveryPage.qml`
  parsed and the page activated.
- Instrumented the mock to log requests: the app fired **exactly the three discovery calls in
  order** with the correct bodies — `{"returnAll":"false"}`, then
  `{"loadMoreKey":"discoveryTopic","returnAll":"false"}`, then
  `{"loadMoreKey":"mediumDiscoveryPictorial","returnAll":"false"}`. This confirms the whole
  data path end-to-end: page activation → `load()` → `fetchDiscovery()` → the native 3-phase
  chain firing and advancing through every phase (each returned 200).
- `returnAll` goes on the wire as the JSON **string** `"false"` (matches the ultrazg/xyz Go
  proxy, which sends a Go string). Flag only if the live API rejects it.

**Post-review hardening (header + retry).** Final review caught that discovery requests need
`abtest-info: {"old_user_discovery_feed":"enable"}` (the Go proxy sets it; the shared
`applyContentHeaders` did not) — now sent **for discovery requests only**. The mock can't catch
this, so it's a likely live "empty feed" cause if missing; still needs a real-token confirmation.
Also: if **all three** feed calls fail at HTTP/parse level, the client no longer emits
`discoveryLoaded`, so the page's `loadedOnce` stays false and a transient failure retries on the
next tab visit (mirrors `fetchInbox`); a *successful* empty feed shows the normal empty state.

**Could NOT capture pixels in this headless run.** The QML view is OpenGL-backed, so
`PrintWindow` renders black, and the standalone app exits cleanly without the Qt Simulator
harness in a non-interactive session. Card layout/bindings were instead confirmed by static
QML-1.1 review. **A human visual pass (or a real-device run) is still pending** — open the app,
tap the compass tab, and confirm the four sections (大家都在听 / 编辑精选 / 中年人运动全面指南
with its subtitle / 最热榜) render with covers and that a card opens EpisodePage. Also still
**unverified against the live API** — confirm the section titles + double-nesting on the real
endpoint before trusting (the mock has diverged from real before).

## 2026-06-25 — Refresh-token 401 retry

Simulator + PowerShell mock verification (`scripts/mock-content.ps1`, `localhost:8099`).

**Happy path (expired access token, valid refresh token):** The mock gates all content
endpoints with 401 until a refresh succeeds. Observed mock request sequence:

```
POST /v1/inbox/list -> 401 (gated)
POST /app_auth_tokens.refresh -> 200 (refresh)
POST /v1/inbox/list -> 200
```

The C++ `XyzApiClient` correctly intercepted the 401, fired a one-shot refresh (sending
both tokens in headers, empty body), stored the new `x-jike-access-token` /
`x-jike-refresh-token` returned in the body, and silently replayed the inbox request —
no `sessionExpired` emitted, no logout.

**Negative path (dead refresh token):** Mock's refresh handler returns 401. Observed:

```
POST /v1/inbox/list -> 401 (gated)
POST /app_auth_tokens.refresh -> 401 (refresh denied)
```

No retried inbox 200. The `m_refreshAttempted` guard prevented a loop, and
`sessionExpired` was emitted as expected (test page would show "SESSION EXPIRED").

**Pending:** Real-device confirmation of the refresh request shape — specifically that
the live jike gateway accepts the empty body and the `x-jike-refresh-token` header on
`POST /app_auth_tokens.refresh`. Simulator + mock is conclusive for the C++ control flow
but cannot validate the actual HTTP negotiation with the real backend. Watch one specific
detail: the empty refresh POST still goes out with `Content-Type: application/json` (from
`applyContentHeaders`), whereas the ultrazg/xyz Go proxy uses
`application/x-www-form-urlencoded`. If the live gateway rejects the empty JSON-typed body
(it returns `rpc_error`/HTTP 400 on shape it dislikes), every refresh would silently fail
→ logout; in that case match the proxy's content-type for the refresh request.

## 2026-06-23 — Downloads page storage meter via native RFs::Volume (simulator-verified)

Result: the new Downloads Manager page shows a real phone-memory meter. **Simulator-verified
only — NOT yet device-checked** (pending an on-device run). The `DownloadRegistry`
(`downloads`) sums on-device episode sizes itself; the disk total/free comes from a native
query.

**Disk space (no QStorageInfo in Qt 4.7).** `MemoryMonitor` covers **RAM** (HAL
`EMemoryRAM`/`EMemoryRAMFree`), not disk, so the meter needs its own query:
`RFs::Connect()` → derive the drive from the download dir's leading letter via
`RFs::CharToDrive()` → `RFs::Volume(vol, drive)` and read `vol.iSize` / `vol.iFree`. Guarded
`#ifdef Q_OS_SYMBIAN` like the HAL block; links `-lefsrv` under `symbian {}`. On device the
download dir resolves to `C:/Data/Xyz/audio` (public, per the 2026-06-14 data-cage note), so
the meter reports the **C: phone-memory** volume — matching the "Phone memory" label.

**Off-device fallback:** a `#elif defined(Q_OS_WIN)` branch uses `GetDiskFreeSpaceExW` so the
meter shows real numbers in the Simulator (verified: 353.92 / 926.14 GB on the dev box).
`#else` returns 0/0 and the QML meter degrades (hides the GB readout, keeps the downloads
figure). Sizes/list are real: seeded two cached files (34/55 MB) → Account subtitle showed
"2 episodes · 89.0 MB", rows showed per-file sizes.

**Screenshotting the Simulator (tooling note).** A directly-launched Simulator-Qt `Xyz.exe`
creates **no top-level window of its own** — its UI renders inside the host **"Qt Simulator"**
window (separate process). So capture *that* window, not the app PID's window (the app PID
has `MainWindowHandle=0`). `PrintWindow(hwnd, hdc, PW_RENDERFULLCONTENT=2)` into a `Bitmap`
DC works; `Graphics.CopyFromScreen` throws "handle is invalid" in this non-interactive
session (no screen DC). Run the capture under **Windows PowerShell 5.1 (`powershell.exe`)**,
not pwsh 7 — `System.Drawing.Bitmap` is forwarded to a missing assembly in .NET Core.

## 2026-06-22 — Side volume keys control playback via RemCon (Nokia X7-00)

Result: the phone's **side volume up/down keys now control podcast playback volume** on
device (Nokia X7-00) and work well — each press steps `AudioEngine` volume by ±10%.

**Key lesson:** the dedicated side volume keys are **RemCon media keys, not window-server
key events.** They are never delivered to the Qt app as `QKeyEvent`/`Qt::Key_VolumeUp`, so
a QML `Keys` handler or a `QApplication` event filter sees **nothing** (that was the exact
"pressing the keys does nothing" symptom). Approaches that DON'T work for the side rocker:
a Qt event filter (keys never arrive) and `RWindowGroup::CaptureKey` on
`EStdKeyIncVolume`/`DecVolume` (the X7-00 rocker doesn't emit those WS scan codes).

What works: register a **`CRemConCoreApiTarget`** (`remconcoreapi.lib` +
`remconinterfacebase.lib`) via `CRemConInterfaceSelector::OpenTargetL()`. Its
`MrccatoCommand` observer receives `ERemConCoreApiVolumeUp`/`...VolumeDown`, routed to
`AudioEngine::nudgeVolume(±0.1)`. Send the required ack with a local `TRequestStatus` +
`User::WaitForRequest` — **no `CActive` needed**; no stray-signal / `E32USER-CBase` panic
observed on device. Act on non-`ERemConCoreApiButtonRelease` actions so one tap = one step.

**Capability:** works with the existing caps (`NetworkServices ReadUserData WriteUserData
UserEnvironment`) — RemCon target registration needed **no** extra capability; no
`KErrPermissionDenied` (-46), so `LocalServices` was not required. Self-signed SIS installs
and runs fine.

Build/wiring: native `src/VolumeKeyCapturer.{h,cpp}` is `#ifdef Q_OS_SYMBIAN`-guarded and
added to `Xyz.pro` only under `symbian {}`, so the Simulator (mingw) build never compiles it
and stays green. Constructed in `main.cpp` via `TRAPD` (a leave just logs + disables the
keys — graceful degradation). See `docs/superpowers/specs/2026-06-20-volume-keys-design.md`.

## 2026-06-19 — Episode page two-step Download→Play works on device (+ a QDir::entryList glob trap)

Result: the episode page's two-step **Download → Play** is **device-verified** — an
undownloaded episode shows "Download · <size>", tapping downloads with progress, then
"On device · <size>" + Play plays the cached `.m4a`. Download/play reuse the
device-verified PlayerController/EpisodeDownloader stack (so the MMF `-14`/reboot caveat
from the entry below still applies to playback itself).

**Bug found on device (not in the simulator):** every episode opened straight to the
**Play** state with nothing actually downloaded, and the file system showed no per-episode
files. Cause: the new cache check `EpisodeDownloader::cachedPath()` resolved the cached
file with `QDir::entryList(QStringList() << eid + ".*", QDir::Files)`. **On Symbian that
name-filter glob is unreliable** — it returned the one stale clip in the audio dir
(`C:/Data/Xyz/audio/selftest.m4a`, left over from the player self-test) for **every** eid,
so `isDownloaded(eid)` was always true. (It never reproduced in the Qt Simulator because
MinGW's `entryList` filters correctly; and a build + QML-log check passes without ever
exercising the flow — only an interactive run catches it.)

Fix: probe known extensions by **direct `QFile::exists("<eid>.m4a"|.mp3|...)`** instead of
the glob. This is the same lesson as the data-cage notes below — **don't trust `QDir`
listing/`exists()` semantics on Symbian; do a direct, specific I/O check.** (audioDir() is
a PUBLIC path, so `QFile::exists` there is reliable; the cage caveat is `/private` only.)
Note the bug would also have struck after any real download — one cached file made *all*
episodes read as downloaded — so it was a true defect, not just stale-state.

## 2026-06-19 — Player: real m4a download+play works on device — the -14 was a stuck MMF, cleared by reboot

Result: the Self-test "Player" download → play of a **real downloaded Xiaoyuzhou `.m4a`**
now plays **with audio** on device — position/duration advance and sound comes out. This is
the **same build** that returned `symbian -14` (KErrInUse) at the audio-output stage on
2026-06-14 — **no code changes since**. The only difference was a **phone reboot**.

Conclusion: the persistent `-14` from the 2026-06-14 saga was **not a code bug** — it was a
**wedged MMF audio-output state** accumulated from the earlier run of failed experiments.
Symbian MMF is a shared OS server with no graceful recovery (same family as the 2026-02-17
`-12014` position-write brick that kills *all* audio until restart). Once its audio output
is stuck "in use", **no amount of correct play-timing or path-fixing can reacquire it** —
which is exactly why deferred-play + public-path were right yet `-14` never cleared. A device
restart resets the MMF server and the (already-correct) code just works.

This retroactively **validates the 2026-06-14 fixes** — they were correct all along:
- download to a **public** path MMF can read (`E:/Xyz/audio` → `C:/Data/Xyz/audio`), never
  the `/private/<UID>` data cage;
- defer `play()` until `mediaStatus` reaches Loaded(3)/Buffered(6).
So m4a/AAC decodes and plays through `PlayerController` on device.

**Rule for the next audio test:** if experiments start failing with `-14` / silent output /
`mediaStatus` stuck after an earlier crash or a `-12014`, **reboot the phone before
concluding the code is wrong**, and re-confirm any audio fix on a freshly-rebooted device. A
run of failed MMF acquisitions can poison the audio server for the rest of the session.

## 2026-06-14 — Player: MMF can't read the private data cage (silent playback)

Symptom (C7): first episode player test. Download completed (real file, took a while),
the player reached `playingState` (pill "pass"), but **no audio**, and both position and
duration stayed **0:00** ("playing 0:00 / 0:00"). No `QMediaPlayer` error / InvalidMedia
was surfaced.

Root cause: `EpisodeDownloader::audioDir()` probed `QDesktopServices::DataLocation` first,
which on this self-signed app is the **`/private/<UID>/` data cage** (same place the DB
lands — see 2026-02-17 SQLite note). The downloaded `.m4a` therefore saved into the cage.
**Symbian MMF runs in a separate server process and cannot read another app's data cage**,
so `QMediaPlayer` got a path it couldn't open → flipped to PlayingState but never loaded
or decoded → duration 0, position 0, silence, and (unhelpfully) no clean error.

Why "Play tone" (qrc:) worked but this didn't: Qt stages a `qrc:` resource to an
accessible temp file before handing it to MMF, so that path is readable; our caged file
was not. Same lesson as the 2026-02-18 artwork cache, which had to write to **`E:/`**
(public) for the images to load.

Fix: download media only to **PUBLIC** locations the MMF server can read — prefer
`E:/Xyz/audio` (memory card), then `C:/Data/Xyz/audio` (public phone storage, already
proven writable: the app log lives at `C:/Data/Xyz/logs`). On Symbian, never use
DataLocation/app-private for media. (`audioDir()` now lists only public bases on device;
DataLocation remains a desktop/simulator fallback under `#ifndef Q_OS_SYMBIAN`.)

Diagnostics added to the Self-test "Player" section to make the next device test
conclusive: it now shows the resolved `src:` file path and the live MMF `[mediaStatus N]`
(0 unknown · 2 loading · 3 loaded · 4 stalled · 5 buffering · 6 buffered · 8 invalidMedia).

Re-test (same day): the cage fix **worked** — MMF now opens the file and `mediaStatus`
climbs `5 → 6` (BufferedMedia), confirming the file is readable and the m4a/AAC codec
decodes. But a **new** error surfaced: `symbian -14` = **KErrInUse**, with playback still
silent and position/duration stuck at 0:00. The log showed `state -> 1` (we called
`play()`) *before* `status -> 5/6` — i.e. **`play()` was called before the media loaded.**

Second root cause: on Symbian, calling `play()` before the media reaches LoadedMedia makes
MMF acquire the audio output prematurely; the buffered clip then can't take the output
("already in use", -14), so it buffers but never sounds. ("Play tone" dodges this only
because a tiny local WAV loads almost instantly.)

Fix: `PlayerController` now **defers `play()` until mediaStatus reaches Loaded(3)/Buffered(6)**
(`m_waitingToPlay` + an `onAudioStatusChanged` watcher), so there's exactly one,
correctly-timed play. Kept in the controller, not the shared `AudioEngine`, so "Play tone"
and the episode page are untouched. setMedia() on Symbian opens the file and emits
LoadedMedia without needing play(), so there's no load deadlock.

Re-test of the deferred-play fix: **did NOT clear -14.** `src:` confirmed
`C:/Data/Xyz/audio/selftest.m4a` (public, readable). So -14 is **not** a play-timing
race — it fires at the audio-output stage regardless of when play() is called. Hypothesis
#2 was wrong. (Also seen: retry after a -14 sticks at `mediaStatus 0` — a separate replay
bug, `AudioEngine::setSource` early-returns on an unchanged URL so nothing reloads.)

Full log (xyz.log) analysis: the deferred-play fix works exactly as intended — for an m4a
the sequence is `status 2 → 3 (loaded)` → "media loaded, starting play()" → `play()` →
`state 1` → `status 5 → 6 (buffered)` → **`state 2` (player auto-pauses)** → `Error
Symbian:-14`. So -14 fires at the **output** stage, after a single, correctly-timed
play(). Timing is ruled out.

**Key correction:** the "Play tone" self-test never actually played on device — the log
shows `SelfTestPage.qml:50: TypeError: 'audioEngine.setSource' is not a function`.
`setSource` is a Q_PROPERTY WRITE accessor, **not callable from QML** (must assign the
`source` property instead). So there was NO confirmed working audio output on this device;
the earlier "MMF init OK" note was not from a real device run. The player path works in
C++ only because PlayerController calls setSource() directly.

Next step is diagnostic, not a -14 fix: fixed "Play tone" to assign `audioEngine.source`
(callable) so we can learn whether a plain local PCM `.wav` plays through AudioEngine AT
ALL. If the tone errors too → output is fundamentally broken on this device (investigate
QMediaPlayer setup / capabilities / CMdaAudioPlayerUtility). If the tone plays → -14 is
m4a/AAC-specific. Also fixed: playEpisode now `reset()`s the engine so repeat plays of the
same eid reload (retry was sticking because setSource ignores an unchanged URL).

**Resolved 2026-06-19:** `-14` was a wedged MMF audio-output state, **not** a code bug — the
same build plays a real m4a fine after a phone reboot. See the 2026-06-19 entry above.

## 2026-06-14 — Virtual keyboard not opening for login text fields

Symptom (Nokia X7, Belle): tapping the phone-number field on LoginPage did not raise
the on-screen keyboard, so login couldn't proceed. Worked in the Qt Simulator (desktop
input context), failed on device.

Cause: both LoginPage `phoneInput` and VerifyCodePage `codeInput` are raw QtQuick 1.1
`TextInput` elements. Per the QtQuick 1 docs, on Symbian the software input panel (VKB)
opens on a *click that reaches the TextInput*, not merely on active focus (that's the
non-Symbian behavior — hence it worked in the simulator). The code only called
`forceActiveFocus()`:
- LoginPage: an overlay `MouseArea` swallows the tap, so the click never reaches the
  `TextInput`.
- VerifyCodePage: `codeInput` is an invisible 1x1 (`opacity:0`) field that can't be
  tapped at all.
So focus moved but the panel never appeared.

Fix: call `TextInput.openSoftwareInputPanel()` explicitly wherever we `forceActiveFocus()`
(both pages' tap handlers, plus VerifyCodePage `onStatusChanged`).

Follow-up (same day, X7): the VKB now opens — but opening it on the verify page left the
*next* page (Updates / My Subscriptions) shrunk, with a black gap under the bottom tab bar.
Cause: `XyzPageStackWindow`'s `sip` spacer is sized to `inputContext.height` while
`inputContext.visible` is true, and `contentArea` is anchored to `sip.top`. The panel was
never dismissed, so after `pageStack.clear()`/`push` on login the SIP stayed "Visible" and
kept reserving keyboard height. Fix: `codeInput.closeSoftwareInputPanel()` in VerifyCodePage
`onStatusChanged` when `status === PageStatus.Deactivating`, so the SIP collapses before the
next page activates. Lesson: every manual `openSoftwareInputPanel()` needs a matching
`closeSoftwareInputPanel()` on page exit.

Status: VKB opening confirmed on X7; shrunk-next-page fix pending re-test.

## 2026-06-13 — M2 content screens (remote images, content API)

- Content API is `api.xiaoyuzhoufm.com` (iOS-app headers), separate from the auth host.
  `XyzApiClient` reuses the AuthClient pattern (single in-flight reply, qjson, ignore SSL).
- Remote cover/avatar `Image`s load through the QML engine's `SslIgnoringNamFactory`
  (stale CA tolerated). Memory bounded via `sourceSize` caps + ListView/GridView lazy
  delegates — watch `memoryMonitor` on-device with 20+ covers.
- QML 1.1 limits: no circular Image clipping (avatars are rounded squares); avatar stack
  uses positive spacing (no negative-margin overlap). Date/number formatting done in C++
  (`shapeInboxItem`/`shapeSubscription`), not QML bindings.
- Reminder: editing only `.qml`/`.qrc`/svgs does not retrigger rcc — delete
  `build-simulator/debug/rcc/qrc_qml.cpp` + `obj/qrc_qml.o` before rebuilding.

### Simulator visual verification (mock, 2026-06-13)

Visual verification PASSED in the Qt Simulator (Nokia N8 frame) against the local mock
(`scripts/mock-content.ps1`, `XYZ_API_BASE=http://localhost:8099`) with a token seeded
into the sim DB (`%LOCALAPPDATA%\Nokia\QtSimulator\data\xyz.db`, `kv` table) to boot
straight to Updates without SMS.

Confirmed working:
- **Updates cards**: covers loaded, 2-line title/desc, meta row with inline icons,
  commentCount "99+" cap, relative times ("21h ago" / "1d ago"), action row + play circle,
  title bar + "My Subscriptions" pill, bottom tab bar.
- **Subscriptions grid**: 3-col covers, "Often" badge, header toggle.
- **Subscriptions list**: search placeholder, Starred empty-state, "All Subscriptions"
  rows with avatar stacks, hosts · when.
- **Navigation**: Updates → My Subscriptions → grid → toggle → list all worked.
- Remote cover/avatar images (HTTPS) load through `SslIgnoringNamFactory` as expected.
- App log (`C:/Data/Xyz/logs/xyz.log`): clean, no QML binding errors.

### Screenshot-capture gotcha (Qt Simulator, non-interactive shell)

The app is built console-subsystem AND its GUI renders inside the **Qt Simulator** host
window (window class `QWidget`, title `Qt Simulator`), NOT under the launched `Xyz.exe`
PID — so `Process.MainWindowHandle` is 0 and per-PID window enumeration fails.

To capture a screenshot:
1. Enumerate top-level windows by class/title (`Qt Simulator`).
2. Call `SetProcessDPIAware()` first — without it, the capture is cropped.
3. Use `PrintWindow(hwnd, hdc, 2)`.

GUI windows are also not visible to a non-interactive shell session; offscreen QML still
renders and logs binding errors to `C:/Data/Xyz/logs/xyz.log`.

## 2026-06-06 — SMS login API: TLS 1.2, QML XHR error quirk, qrc rebuilds (Simulator)

Findings from wiring the SMS login flow to the official 小宇宙 API. Stage = Qt
Simulator (desktop); device retest still pending, but these are mostly Qt-version /
server-side facts that apply on-device too.

### TLS 1.2 is mandatory for the auth host
`podcaster-api.xiaoyuzhoufm.com` **rejects TLS 1.0** (curl `--tls-max 1.0` → connect
fails / HTTP 000) and requires **TLS 1.2** (curl `--tlsv1.2` → HTTP 400 for a bad body,
i.e. it talks). The Simulator's bundled OpenSSL is **1.0.2u** (TLS-1.2 capable), and
Qt 4.7.4's `QSslSocket` negotiates TLS 1.2 fine through it — the in-app TLS self-test
(`https://tls-v1-2.badssl.com:1012/`) passes (`supportsSsl: true`,
"TLS 1.2 handshake and HTTP GET succeeded"). So no patched DLLs are needed in the
Simulator. **On the C7, verify the device OpenSSL/QtNetwork can do TLS 1.2** before
trusting the live flow; if not, fall back to a LAN-hosted ultrazg/xyz proxy
(see docs/API_NOTES.md).

### Qt 4.7 QML `XMLHttpRequest` zeroes `status` on HTTP errors
For 4xx/5xx responses, `xhr.status` is correct at readyState 2/3 (HEADERS_RECEIVED,
LOADING) but **resets to 0 at readyState 4 (DONE)**, and `responseText` is empty at
DONE too. Observed via logging: server returned 400, states 2/3 showed `status=400`,
state 4 showed `status=0 body=""`. This made every error look like a "Network error".
**Fix:** in `qml/js/Api.js` capture the last non-zero `status` and last non-empty
`responseText` across `onreadystatechange`, and use those in the callback. The 200
success path is unaffected — `status`, `responseText`, and `getResponseHeader()`
(used to read the `x-jike-access-token` / `x-jike-refresh-token` headers) all work
correctly at DONE. Validated end-to-end against a local mock returning 200 + token
headers; validated the error path against the real API (shows the server's `msg`,
e.g. "无效参数").

**Update (native migration):** auth was later moved off QML XHR into a native C++
`AuthClient` (`src/AuthClient.{h,cpp}`) + vendored qjson, so this quirk no longer
affects login — native `QNetworkReply` reads status cleanly from
`HttpStatusCodeAttribute`. Kept here as reference for any future QML-side XHR use.

### Auth requests go through the QML engine NAM, so spoof headers live in C++
QML XHR cannot set forbidden headers (`User-Agent`, `Referer`). They are injected
host-keyed in `SslIgnoringNam::createRequest` (src/main.cpp). The real API accepting
our request (returning a normal 400, not a 403 bot-block) confirms the browser-spoof
header set is accepted.

### Build gotcha: editing only `.qml` does NOT rebuild the qrc
The qmake-generated MinGW Makefile's `rcc` rule depends on `qml/qml.qrc` but **not** on
the individual `.qml`/`.js` files it lists. So `mingw32-make` won't regenerate
`qrc_qml.cpp` when you change a `.qml` without touching the `.qrc` — you get a fresh
process running stale embedded QML. **Workaround:** delete
`build-simulator/<cfg>/rcc/qrc_qml.cpp` + `obj/qrc_qml.o` before rebuilding (or
`touch` the `.qrc`, or build `-Clean`).

## 2026-02-18 — Artwork Cache & Image Proxy

### Problem
Detail page artwork never displays. List page images (loaded directly via QML
`Image.source`) work fine.

### Root Causes (multiple, layered)

1. **Missing guid/imageUrlHash in detail page params.**
   `SubscriptionsPage.openPodcastDetail()` didn't pass `podcastGuid` or
   `imageUrlHash` to `PodcastDetailPage`. The proxy URL condition failed,
   falling back to the original full-size image URL (3000x3000, 3.5MB).

2. **Wrong file extension from proxy URL.**
   `extensionFromUrl()` parses the URL path for a dot. The proxy URL
   (`/hash/.../feed/.../128`) has no extension, so it defaulted to `.jpg`.
   But the proxy returns PNG. Qt on Symbian can't auto-detect format mismatch
   — file saved as `cover.jpg` containing PNG data fails to decode.
   Fix: read `Content-Type` response header to determine extension.

3. **SSL errors killing downloads silently.**
   `ArtworkCacheManager` used its own plain `QNetworkAccessManager`. QML images
   work because they go through `SslIgnoringNam` (auto-ignores SSL errors via
   `createRequest` override). The cache manager's `onSslErrors` slot fired too
   late. Fix: connect `ignoreSslErrors()` directly on the reply, same pattern
   as `SslIgnoringNam`.

4. **Cleanup loop deleting the temp file before rename.**
   The "remove old cover files" loop matched ALL files starting with `cover`,
   including the `.part` temp file just written. `QFile::rename()` then failed
   because the source was deleted. Fix: skip the temp file in the cleanup loop.

5. **Raw file paths instead of file:// URLs.**
   `artworkCached` signal emitted raw paths (`E:/Podin/.../cover.png`) but QML
   `Image.source` requires `file:///` URLs. Needed `QUrl::fromLocalFile()`.

6. **findCachedFile matching .part files.**
   Leftover `.part` files from failed downloads were returned as valid cache
   hits, preventing re-download. Fix: skip `.part` in `findCachedFile`.

### Key Lessons
- QML `Image.source` loaded via `QDeclarativeNetworkAccessManagerFactory` gets
  SSL error handling for free; C++ `QNetworkAccessManager` instances do not.
  Always connect `ignoreSslErrors()` on replies for Symbian HTTPS.
- Never guess file extension from URL — use `Content-Type` header.
- When cleaning up old files before rename, exclude the source temp file.
- Always emit `file:///` URLs (via `QUrl::fromLocalFile()`) for QML images.


## 2026-02-17 — Audio Seeking — KErrMMAudioDevice (-12014)

### Problem
Writing `position` property on QML Audio element causes KErrMMAudioDevice
(-12014), bricking ALL audio until phone restart. MMF is a shared OS service
with no graceful recovery.

### Key Facts
- Error -12014 is Symbian MMF, not Qt. Corrupts audio device at OS level.
- QML property bindings may trigger writes at unexpected state transitions.
- Even guarding to `playingState`/`pausedState` didn't prevent it.

### Resolution
C++ `AudioEngine` wrapping `QMediaPlayer::setPosition()` with state guards.
Defers seek via `m_pendingSeek` if not ready. Works correctly on device.


## 2026-02-17 — SQLite Persistence on Self-Signed SIS

### Problem
Database falls back to `:memory:` — subscriptions lost on restart.

### Root Causes
1. **Data caging**: `/private/<UID>/` dirs writable but invisible to
   `QDir::exists()`. Code skipped them before testing SQLite.
2. **Driver mismatch**: Test used `QSQLITE`, production used `QSYMSQL`.
3. **Path separators**: Forward slashes failed with QSYMSQL.

### Fix
Skip `exists()`/`mkpath()` for `/private/` paths, go straight to SQLite write
test. Use same driver for test as production. Use `toNativeSeparators()`.

### Key Lesson
On Symbian, data-caged directories are writable but invisible. Never rely on
`QDir::exists()` — go straight to I/O test.
