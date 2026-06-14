Symbian Belle Device Notes
==========================

Hardware: Nokia C7 (Belle FP2)

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
