# Project Instructions

## Project Overview
- Qt 4.7 / QML 1.1 application for Symbian Belle (Nokia C7 class), self-signed SIS deployment.
- Generated from the qt-symbian-belle-starter template.
- See `docs/PLAN.md` for milestones, `docs/DEVICE_NOTES.md` for the device experiment log.
- **Xiaoyuzhou FM API**: `docs/API_NOTES.md` is the working reference. Its source of truth is
  the **ultrazg/xyz** Go proxy (v1.10.0), cloned locally at `C:\Users\liya\Repos\xyz-go` — read
  `doc/docs/*.md` (per-endpoint docs) and `handlers/*.go` + `service/service.go` +
  `constant/url.go` (real request/response shapes) directly. No need to run the localhost:23020
  proxy to look something up.

## Architecture
- C++ managers in `src/` are exposed to QML via `setContextProperty` in `main.cpp`:
  `storage` (StorageManager), `memoryMonitor`, `tlsChecker`, `audioEngine`.
- `StorageManager` handles SQLite with multi-candidate writable-path fallback.
- QML uses Symbian Components 1.1; `AppWindow.qml` is the root, pages live in `qml/`.

## Critical Symbian Rules
- **NEVER write the `position` property on a QML `Audio` element** — causes
  KErrMMAudioDevice (-12014) and bricks ALL audio until phone restart. Drive
  playback through the C++ `audioEngine` (`QMediaPlayer::setPosition()`).
- **Data caging**: `/private/<UID>/` dirs are writable but invisible to
  `QDir::exists()`. Skip exists/mkpath checks and go straight to an I/O test.
- **SQL driver**: prefer `QSYMSQL` over `QSQLITE` on Symbian. Test with the same
  driver production code uses.
- **Path separators**: use `QDir::toNativeSeparators()` for paths passed to SQL
  drivers on Symbian.

## QML 1.1 Compatibility Rules
- **No block expressions in property bindings** — use a helper function or ternary.
- **No named function declarations inside non-root elements** — declare functions
  at the `Page`/root level only.
- **No negative anchor margins** — size a larger `Item` for touch targets instead.
- **SVG icon sizing**: Symbian renders icons using the SVG `viewBox` dimensions,
  ignoring `width`/`height`. To resize, change both the `width`/`height` and the
  `viewBox`, wrapping paths in `<g transform="scale(factor)">`.

## Notifications (Pigler)
- Status-panel notifications use the **Pigler Notifications API (PNA)** — a separate
  on-device server the user installs (`Pigler.sis` from nnproject.cc/pna). The app
  degrades gracefully without it. This pattern is the reusable way to add any
  notification to a self-signed Belle app.
- `NowPlayingNotifier` (context property `notifier`) wraps the vendored `QPiglerAPI`
  (`src/pigler/`, from upstream `piglerorg/pigler`) and observes `player`. All Pigler
  code is under `#ifdef Q_OS_SYMBIAN`; off-Symbian the class is a no-op so the
  simulator still builds. Tap → app foreground + `handleTap` signal → QML
  (`openEpisodeForCurrent`). Lifecycle is state-keyed (`Playing`/`Paused`).
- Build: vendored sources + `LIBS += -lrandom -laknnotify` go ONLY in the `symbian {}`
  scope of `Xyz.pro`; no capability beyond the four already self-signed.
- **Gotcha — removeOnTap:** Pigler's server default is *remove-on-tap*, so a tap
  deletes the notification. For a persistent one, call `setRemoveOnTap(id, false)` at
  creation (alongside `setLaunchAppOnTap(id, true)`).
- **Gotcha — slots behind `#ifdef`:** moc processes headers on every platform, but a
  slot declared inside `#ifdef Q_OS_SYMBIAN` is missing from the meta-object on other
  platforms, so a string-based `connect(SIGNAL(...), SLOT(...))` wires up to nothing —
  silently, at runtime. Declare such slots unconditionally; guard only the body.
  Compile-checks (both simulator and ARM) will NOT catch this.

## Device Experimentation Log
- After ANY audio/media/platform-API experiment, record it in `docs/DEVICE_NOTES.md`
  with a dated heading (`## YYYY-MM-DD — Title`), including error codes and failed
  approaches. Read it before touching audio/media code — Symbian MMF is fragile.
