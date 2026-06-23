Symbian Belle Device Notes
==========================

Hardware: Nokia C7 (Belle FP2)

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
