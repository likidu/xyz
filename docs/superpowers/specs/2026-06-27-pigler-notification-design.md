# Pigler now-playing notification — design

**Date:** 2026-06-27
**Status:** Approved (design); pending spec review
**Task source:** `tasks/pigler_notification.md`

## Goal

Show the currently-playing episode as a Symbian status-panel notification via the
**Pigler Notifications API (PNA)**. Tapping the notification foregrounds the app and
opens that episode's detail page. Use a placeholder icon for now. Document the
end-user install requirement in `README.md`.

Non-goal: in-notification transport controls (Pigler is tap-only), a branded icon,
or cold-start tap handling (see Out of scope).

## Background — how Pigler works

Pigler is a homebrew Symbian notification service for self-signed apps. The end user
installs `Pigler.sis` (the notification server/plugin) once and reboots; apps then
talk to it over IPC. Reference: <https://nnproject.cc/pna/>, source
`github.com/piglerorg/pigler`.

The official `qt-tester` uses a thin Qt wrapper, `QPiglerAPI` (in the repo's
`qt-library`), over the native `PiglerAPI` + `PiglerTapServer`. Relevant surface
(verbatim from `qt-library/inc/QPiglerAPI.h`):

```cpp
qint32 init(QString name);              // register app, connect to server; <0 = failure
qint32 createNotification(QString title, QString message);   // returns notification id
qint32 updateNotification(qint32 id, QString title, QString message);
qint32 setNotification(qint32 id, QString title, QString message);
qint32 setNotificationIcon(qint32 id, QImage icon);          // QImage scaled to bitmap size
qint32 setLaunchAppOnTap(qint32 id, bool launch);            // foreground app on tap
qint32 setRemoveOnTap(qint32 id, bool remove);
qint32 removeNotification(qint32 id);
qint32 removeAllNotifications();
qint32 getAPIVersion();
void   close();
signals:
    void handleTap(qint32 notificationId);   // emitted when a notification is tapped
```

`createNotification` is `setNotification(0, …)`. Icons are provided as a `QImage`,
which the wrapper converts to ARGB32 and centres into the server's bitmap size.
Tap delivery runs through a `CActive` tap server, which works inside the Qt for
Symbian event loop (Qt installs a `CActiveScheduler`).

## Decisions

1. **Build integration: vendor Pigler source** (not the prebuilt `.lib`). Compile the
   `QPiglerAPI` + `sym-library` sources directly, only under the `symbian:` scope,
   linking `-lrandom -laknnotify`. Transparent, no binary-blob/ABI matching, mirrors
   how `qt-tester`'s `pigler.pri` builds.
2. **Seam: a dedicated `NowPlayingNotifier` C++ class** (context property `notifier`),
   owning the `QPiglerAPI` and observing `player`. Keeps all Pigler/Symbian specifics
   behind one boundary, consistent with the existing manager pattern
   (`audioEngine`, `player`, `tlsChecker`, `VolumeKeyCapturer`).
3. **Lifecycle: visible while an episode is loaded.** Appears when playback starts,
   persists through pause, removed on stop and on app close. Keyed on
   "episode loaded" (`player.currentEid != ""` / state back to `Idle`), not play/pause.
4. **Content: line 1 = episode title, line 2 = show name.** Maps to
   `player.currentTitle` and `player.currentShow`.

## Architecture

New component `src/NowPlayingNotifier.{h,cpp}`, exposed to QML as `notifier`. It wraps
a `QPiglerAPI`. All Pigler calls are wrapped in `#ifdef Q_OS_SYMBIAN`; on the
simulator/desktop build the class compiles to a safe no-op so the app builds and runs
unchanged (same strategy already used for `VolumeKeyCapturer` in `main.cpp`).

Vendored Pigler sources live under `src/pigler/`, added to `Xyz.pro` **only inside the
`symbian:` scope**.

```
player (PlayerController) ──signals──▶ NowPlayingNotifier ──▶ QPiglerAPI ──IPC──▶ Pigler server
        currentEidChanged                  │  create/update/remove
        currentTitleChanged                │  setNotificationIcon (once)
        currentShowChanged                 │  setLaunchAppOnTap(true)
        stateChanged                       │
                                           └─ handleTap(id) ──▶ emit openCurrentEpisodeRequested()
                                                                        │
AppWindow.qml  Connections{ target: notifier; onOpenCurrentEpisodeRequested: openEpisodeForCurrent() }
```

### Component: `NowPlayingNotifier`

Responsibilities: own the Pigler connection; maintain exactly **one** notification that
mirrors the current episode; translate a tap into a QML navigation request. It reads
the episode from `player` directly (constructor takes `PlayerController*`), so callers
pass no episode data.

Public shape (Symbian and non-Symbian both compile; bodies differ):

```cpp
class NowPlayingNotifier : public QObject {
    Q_OBJECT
public:
    explicit NowPlayingNotifier(PlayerController *player, QObject *parent = 0);
    ~NowPlayingNotifier();                 // remove notification + api.close()
    void init();                           // QPiglerAPI::init("Xiaoyuzhou"); set availability
signals:
    void openCurrentEpisodeRequested();    // tap → QML opens the current episode page
private slots:
    void refresh();                        // create/update/remove from current player state
    void onTap(qint32 id);                 // → emit openCurrentEpisodeRequested()
private:
    PlayerController *m_player;
    QPiglerAPI       *m_api;               // Symbian only
    int  m_notifId;                        // -1 = none
    bool m_available;                      // false if Pigler server absent / init failed
    bool m_iconSet;                        // placeholder icon applied once
};
```

Behaviour table (driven by `refresh()`, connected to the four player signals):

| Player state | Action |
| --- | --- |
| `currentEid` becomes non-empty (episode loaded) | If `m_notifId < 0`: `createNotification(title, show)`, set placeholder icon, `setLaunchAppOnTap(id, true)`. Else `updateNotification(m_notifId, title, show)`. |
| `currentTitle` / `currentShow` change (same episode) | `updateNotification(m_notifId, title, show)`. |
| State returns to `Idle` / `currentEid` empties (stop) | `removeNotification(m_notifId)`; `m_notifId = -1`. |
| Pause / resume | No change — notification stays (lifecycle decision 3). |
| Destruction (app close) | `removeNotification`, `api.close()`. |

Every action is a no-op when `!m_available`. `init()` checks the `init()` return code
(and optionally `getAPIVersion()`); on failure logs once and leaves `m_available =
false` so the rest of the app is unaffected.

### Tap → episode page

`QPiglerAPI::handleTap(id)` is connected to `onTap`, which emits
`openCurrentEpisodeRequested()`. `AppWindow.qml` adds:

```qml
Connections {
    target: notifier
    onOpenCurrentEpisodeRequested: openEpisodeForCurrent()
}
```

`setLaunchAppOnTap(id, true)` brings the app to the foreground; the existing
`openEpisodeForCurrent()` (AppWindow.qml:31) opens the detail page for the now-playing
episode. Because there is a single notification bound to the single current episode, no
id→eid mapping is needed. `openEpisodeForCurrent()` already guards on
`player.currentEid === ""`, so a stale tap is safe.

### Placeholder icon

Ship one small PNG, `qml/gfx/notif-icon.png`, added to `qml/qml.qrc`. `init()` (or the
first `createNotification`) loads it via `QImage(":/qml/gfx/notif-icon.png")` and calls
`setNotificationIcon(m_notifId, img)` once (`m_iconSet`). The wrapper scales it to the
server's bitmap size. Explicitly a placeholder per the task; a branded icon is a later
swap of this one asset.

## Vendored Pigler sources & build changes

From `qt-library/pigler.pri` + `headers.pri` + `qt-tester.pro`, vendor under
`src/pigler/` (preserving each file's `#include`s; the full transitive header set,
including `IPiglerTapHandler.h` if separate, is captured during implementation):

- `QPiglerAPI.{h,cpp}` (from `qt-library`)
- `PiglerAPI.{h,cpp}`, `PiglerTapServer.{h,cpp}` (from `sym-library`)
- `PiglerProtocol.h` (from `plugin/inc`)

`Xyz.pro`, inside the existing `symbian {}` block:

```pro
    DEFINES += PIGLER_API_ANNA_RECONNECT          # matches qt-tester reference build
    INCLUDEPATH += src/pigler
    LIBS += -lrandom -laknnotify
    SOURCES += src/pigler/QPiglerAPI.cpp \
               src/pigler/PiglerAPI.cpp \
               src/pigler/PiglerTapServer.cpp \
               src/NowPlayingNotifier.cpp
    HEADERS += src/pigler/QPiglerAPI.h \
               src/pigler/PiglerAPI.h \
               src/pigler/PiglerTapServer.h \
               src/pigler/PiglerProtocol.h \
               src/NowPlayingNotifier.h
```

`NowPlayingNotifier.{h,cpp}` are added to the top-level (cross-platform) `SOURCES`/
`HEADERS` too, since the class exists on all platforms (with the Pigler body compiled
out off-Symbian). The vendored `src/pigler/*` files are referenced **only** in the
`symbian:` scope. No new capability beyond the four already self-signed
(`NetworkServices ReadUserData WriteUserData UserEnvironment`) — confirmed at
compile-check.

### main.cpp wiring

After `PlayerController player(&audioEngine);` and alongside the other context
properties:

```cpp
NowPlayingNotifier notifier(&player);
view.rootContext()->setContextProperty("notifier", &notifier);
```

Call `notifier.init()` after `view.show()` / `processEvents()` — same ordering as
`VolumeKeyCapturer`, so the Pigler connection and its tap `CActive` register once the
app is foreground and the scheduler is running. (Exact placement verified during
implementation.)

## Error handling / graceful degradation

- **Pigler not installed** (user skipped `Pigler.sis`): `init()` returns failure →
  `m_available = false`, logged once. App runs normally, no notifications.
- **Any API call** is guarded on `m_available` and a valid `m_notifId`.
- **Off-Symbian**: the whole Pigler path is `#ifdef Q_OS_SYMBIAN`-compiled out; the
  class's public methods are safe no-ops. Simulator/desktop build and run unchanged.

## README

Add a "Notifications (Pigler)" section: to get now-playing notifications, install the
**Pigler Notifications API** from <https://nnproject.cc/pna/> (`Pigler.sis`) and reboot
the phone. Without it the app still works, just without notifications.

## Verification

1. **Simulator build** still compiles and runs (Pigler compiled out) — no regression to
   existing playback/navigation.
2. **Symbian ARM compile-check** via `scripts/build-symbian.ps1` (RVCT 4.0) — confirms
   the vendored sources + `-lrandom -laknnotify` link and no new capability is required.
3. **On-device** (Pigler installed): play an episode → notification shows episode title
   + show name; pause → notification stays; tap → app foregrounds and opens that
   episode's detail page; stop → notification disappears. Record the run (with any error
   codes) in `docs/DEVICE_NOTES.md` under a dated heading, per the project's
   platform-experiment rule.

## Out of scope

- Cold-start tap (app fully closed, then notification tapped): we remove the
  notification on app close, so a stale tap shouldn't normally occur. `getLastTappedNotification()`
  could later handle it if desired.
- In-notification play/pause controls (Pigler is tap-only).
- A real branded notification icon (placeholder PNG now).

## Risks to resolve during implementation

- Exact transitive file/header set of the vendored Pigler sources (e.g. a separate
  `IPiglerTapHandler.h`) — resolved by downloading from the repo and compiling.
- Whether `PlayerController::stop()` clears `currentEid` or only resets state — the
  `refresh()` logic listens to both `currentEidChanged` and `stateChanged` so removal
  fires regardless; confirm during implementation.
- `init()` timing vs. foreground (mirror `VolumeKeyCapturer`'s post-`show()` placement).
