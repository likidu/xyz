# Pigler Now-Playing Notification — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the currently-playing episode as a Symbian Pigler status-panel notification (episode title + show name); tapping it foregrounds the app and opens that episode's detail page.

**Architecture:** A cross-platform `NowPlayingNotifier` QObject (context property `notifier`) owns a vendored `QPiglerAPI`, observes `PlayerController` (`player`), and maintains exactly one notification mirroring the current episode. All Pigler/Symbian code is `#ifdef Q_OS_SYMBIAN`-guarded so the simulator/desktop build compiles a no-op and runs unchanged. Tap → `handleTap` signal → `notifier.openCurrentEpisodeRequested()` → `AppWindow.qml` calls the existing `openEpisodeForCurrent()`.

**Tech Stack:** Qt 4.7 / C++ (Qt4 SIGNAL/SLOT), QML 1.1 (Symbian Components 1.1), RVCT 4.0 for ARM, vendored Pigler `qt-library` + `sym-library` sources from `github.com/piglerorg/pigler`.

**Design spec:** `docs/superpowers/specs/2026-06-27-pigler-notification-design.md`

## Global Constraints

- All Pigler/Symbian-specific code MUST be inside `#ifdef Q_OS_SYMBIAN`; the win32/simulator build MUST compile and run unchanged (no-op notifier).
- Vendored Pigler sources and `LIBS += -lrandom -laknnotify` go **only** inside the existing `symbian {}` scope in `Xyz.pro`.
- No new Symbian capability beyond the four already self-signed: `NetworkServices ReadUserData WriteUserData UserEnvironment`. If the ARM compile-check demands more, STOP and report.
- **NEVER** write the `position` property on a QML `Audio` element (unrelated here, but the project-wide rule stands).
- App UID3 stays `0xE7B5C0DE`.
- Pigler `init()` app name string: `"Xiaoyuzhou"`.
- Notification content: line 1 = `player.currentTitle`, line 2 = `player.currentShow`.
- Placeholder icon asset: `qml/gfx/notif-icon.png`, referenced as `:/qml/gfx/notif-icon.png`.

## Verification model (read first)

This project has **no unit-test harness**; native Symbian IPC and on-device notification behavior cannot be unit-tested here. Per the project's established practice (see `docs/DEVICE_NOTES.md` and the memory on verifying QML flows), each task is verified by:

- **Simulator build + run** — `pwsh scripts/build-simulator.ps1 -Config Debug` then launch — proves cross-platform compile safety and no regression to existing playback/navigation.
- **Symbian ARM compile-check** — `pwsh scripts/build-symbian.ps1 -Config Debug -Arch armv5` — proves the Symbian/Pigler code compiles and links under RVCT 4.0.
- **On-device manual test** (final task) — the human runs it on the Nokia C7 with `Pigler.sis` installed and logs the result to `docs/DEVICE_NOTES.md`.

Where the skill's template says "run the test," substitute the relevant build/run command above.

---

### Task 1: Vendor Pigler sources + Symbian build wiring

Bring the Pigler Qt/Symbian sources into the repo and make them compile under RVCT. Nothing uses them yet — the deliverable is "the vendored library compiles and links in the ARM build, and the simulator build is unaffected."

**Files:**
- Create: `src/pigler/` containing (copied verbatim from the cloned repo): `QPiglerAPI.h`, `QPiglerAPI.cpp`, `PiglerAPI.h`, `PiglerAPI.cpp`, `PiglerTapServer.h`, `PiglerTapServer.cpp`, `PiglerProtocol.h`, **and any header these `#include` transitively** (notably `IPiglerTapHandler.h` if it is a separate file).
- Modify: `Xyz.pro` (inside the existing `symbian {}` block, around line 31-55)

**Interfaces:**
- Consumes: nothing.
- Produces: the `QPiglerAPI` class (header `src/pigler/QPiglerAPI.h`) available to later tasks — key methods `qint32 init(QString name)`, `qint32 createNotification(QString title, QString message)`, `qint32 updateNotification(qint32 id, QString title, QString message)`, `qint32 removeNotification(qint32 id)`, `qint32 setNotificationIcon(qint32 id, QImage icon)`, `qint32 setLaunchAppOnTap(qint32 id, bool launch)`, `void close()`, and signal `void handleTap(qint32 notificationId)`.

- [ ] **Step 1: Clone the Pigler repo into the scratchpad**

```bash
git clone --depth 1 https://github.com/piglerorg/pigler.git \
  "C:/Users/liya/AppData/Local/Temp/claude/C--Users-liya-Repos-xyz/bd1c8b7c-5658-4b38-b0f7-ec9363f82f42/scratchpad/pigler"
```

Expected: clone succeeds; directories `qt-library/`, `sym-library/`, `plugin/` are present.

- [ ] **Step 2: Copy the required sources into `src/pigler/`**

Create `src/pigler/` and copy these files from the clone:
- `qt-library/inc/QPiglerAPI.h`, `qt-library/src/QPiglerAPI.cpp`
- `sym-library/inc/PiglerAPI.h`, `sym-library/src/PiglerAPI.cpp`
- `sym-library/inc/PiglerTapServer.h`, `sym-library/src/PiglerTapServer.cpp`
- `plugin/inc/PiglerProtocol.h`

```bash
mkdir -p src/pigler
SCRATCH="C:/Users/liya/AppData/Local/Temp/claude/C--Users-liya-Repos-xyz/bd1c8b7c-5658-4b38-b0f7-ec9363f82f42/scratchpad/pigler"
cp "$SCRATCH/qt-library/inc/QPiglerAPI.h"        src/pigler/
cp "$SCRATCH/qt-library/src/QPiglerAPI.cpp"      src/pigler/
cp "$SCRATCH/sym-library/inc/PiglerAPI.h"        src/pigler/
cp "$SCRATCH/sym-library/src/PiglerAPI.cpp"      src/pigler/
cp "$SCRATCH/sym-library/inc/PiglerTapServer.h"  src/pigler/
cp "$SCRATCH/sym-library/src/PiglerTapServer.cpp" src/pigler/
cp "$SCRATCH/plugin/inc/PiglerProtocol.h"        src/pigler/
```

- [ ] **Step 3: Resolve transitive headers**

Grep the copied files for local `#include "..."` and copy any referenced header that is not yet in `src/pigler/` (search the clone's `qt-library/inc`, `sym-library/inc`, `plugin/inc`). The most likely extra is `IPiglerTapHandler.h`.

```bash
grep -rhoE '#include "[^"]+"' src/pigler/ | sort -u
# for each name not already in src/pigler, find and copy it from the clone:
find "$SCRATCH" -name 'IPiglerTapHandler.h' -exec cp {} src/pigler/ \;
```

Flatten includes if needed: since everything now lives in one flat `src/pigler/` dir, the existing `#include "QPiglerAPI.h"`-style includes resolve via the `INCLUDEPATH += src/pigler` added in Step 4. Do not rewrite the include lines.

- [ ] **Step 4: Wire `Xyz.pro` (symbian scope only)**

Add to the existing `symbian {}` block in `Xyz.pro` (after the `LIBS += -lremconcoreapi ...` lines):

```pro
    # Pigler Notifications API (vendored from github.com/piglerorg/pigler).
    # Status-panel notifications via the user-installed Pigler.sis server.
    DEFINES += PIGLER_API_ANNA_RECONNECT
    INCLUDEPATH += src/pigler
    LIBS += -lrandom -laknnotify
    SOURCES += src/pigler/QPiglerAPI.cpp \
               src/pigler/PiglerAPI.cpp \
               src/pigler/PiglerTapServer.cpp
    HEADERS += src/pigler/QPiglerAPI.h \
               src/pigler/PiglerAPI.h \
               src/pigler/PiglerTapServer.h \
               src/pigler/PiglerProtocol.h
```

- [ ] **Step 5: Verify the simulator build is unaffected**

Run: `pwsh scripts/build-simulator.ps1 -Config Debug`
Expected: completes with exit code 0; `build-simulator/debug/Xyz.exe` is produced. (The `src/pigler/*` files and symbian LIBS are inside the `symbian {}` scope, so the win32 build never sees them.)

- [ ] **Step 6: Verify the Symbian ARM compile-check**

Run: `pwsh scripts/build-symbian.ps1 -Config Debug -Arch armv5`
Expected: the vendored `src/pigler/*.cpp` compile and the binary links (resolving `-lrandom -laknnotify`) with exit code 0 and no missing-capability error. If a header is missing → return to Step 3. If a capability error appears → STOP and report (Global Constraints).

- [ ] **Step 7: Commit**

```bash
git add src/pigler Xyz.pro
git commit -m "feat(notify): vendor Pigler API sources + Symbian build wiring"
```

---

### Task 2: `NowPlayingNotifier` cross-platform skeleton + main.cpp wiring

Create the seam class with its full public interface, compiling on every platform (no-op off Symbian), and expose it to QML. No notification behavior yet beyond connect/seed — the deliverable is "the simulator build compiles, runs, and the `notifier` context property exists with no regression."

**Files:**
- Create: `src/NowPlayingNotifier.h`, `src/NowPlayingNotifier.cpp`
- Modify: `Xyz.pro` (top-level `SOURCES`/`HEADERS`, lines 57-79)
- Modify: `src/main.cpp` (include near other manager includes; construct after `DownloadRegistry downloads(...)` at line 421; context property near line 437; `notifier.init()` inside the `#ifdef Q_OS_SYMBIAN` post-`show()` block near line 463)

**Interfaces:**
- Consumes: `PlayerController*` (from `src/PlayerController.h`) and, on Symbian, `QPiglerAPI` from Task 1.
- Produces: `class NowPlayingNotifier : public QObject` with `explicit NowPlayingNotifier(PlayerController *player, QObject *parent = 0)`, `void init()`, signal `void openCurrentEpisodeRequested()`, slot `void refresh()`. QML context property name: `notifier`.

- [ ] **Step 1: Create `src/NowPlayingNotifier.h`**

```cpp
#ifndef NOWPLAYINGNOTIFIER_H
#define NOWPLAYINGNOTIFIER_H

#include <QtCore/QObject>
#include <QtCore/QString>

class PlayerController;
#ifdef Q_OS_SYMBIAN
class QPiglerAPI;
#endif

// Mirrors the current episode into a single Pigler status-panel notification
// (Symbian only). Off Symbian every method is a no-op so the app builds and
// runs unchanged. Owns its QPiglerAPI; reads the episode straight from
// PlayerController, so callers pass no data.
class NowPlayingNotifier : public QObject
{
    Q_OBJECT

public:
    explicit NowPlayingNotifier(PlayerController *player, QObject *parent = 0);
    ~NowPlayingNotifier();

    // Connect to the Pigler server and start observing the player. Call once,
    // after the main window is shown/foreground (mirrors VolumeKeyCapturer).
    void init();

signals:
    // Emitted when the user taps the notification; AppWindow opens the
    // current episode's detail page.
    void openCurrentEpisodeRequested();

private slots:
    void refresh();   // reconcile the notification with current player state
#ifdef Q_OS_SYMBIAN
    void onTap(qint32 notificationId);
#endif

private:
    PlayerController *m_player;
#ifdef Q_OS_SYMBIAN
    void applyIcon();
    QPiglerAPI *m_api;
    int  m_notifId;    // -1 = no notification shown
    bool m_available;  // false if the Pigler server is absent / init failed
    bool m_iconSet;    // placeholder icon applied once
#endif
};

#endif // NOWPLAYINGNOTIFIER_H
```

- [ ] **Step 2: Create `src/NowPlayingNotifier.cpp` (skeleton bodies)**

This compiles on all platforms. The Symbian behavior is filled in Task 4; here `refresh()`/`init()` are present but minimal so the class links.

```cpp
#include "NowPlayingNotifier.h"
#include "PlayerController.h"

#ifdef Q_OS_SYMBIAN
#include <QtCore/QtGlobal>
#include <QtGui/QImage>
#include "QPiglerAPI.h"
#endif

NowPlayingNotifier::NowPlayingNotifier(PlayerController *player, QObject *parent)
    : QObject(parent)
    , m_player(player)
#ifdef Q_OS_SYMBIAN
    , m_api(0)
    , m_notifId(-1)
    , m_available(false)
    , m_iconSet(false)
#endif
{
}

NowPlayingNotifier::~NowPlayingNotifier()
{
#ifdef Q_OS_SYMBIAN
    if (m_api) {
        if (m_available && m_notifId >= 0)
            m_api->removeNotification(m_notifId);
        m_api->close();
        // m_api is parented to this and deleted by QObject.
    }
#endif
}

void NowPlayingNotifier::init()
{
    // Filled in Task 4 (Symbian). No-op off Symbian.
}

void NowPlayingNotifier::refresh()
{
    // Filled in Task 4 (Symbian). No-op off Symbian.
}

#ifdef Q_OS_SYMBIAN
void NowPlayingNotifier::applyIcon()
{
}

void NowPlayingNotifier::onTap(qint32 /*notificationId*/)
{
    emit openCurrentEpisodeRequested();
}
#endif
```

- [ ] **Step 3: Add the class to `Xyz.pro` top-level lists**

In `Xyz.pro`, append to the cross-platform `SOURCES` (ends line 67) and `HEADERS` (ends line 79):

```pro
SOURCES += \
    ...existing...
    src/DownloadRegistry.cpp \
    src/NowPlayingNotifier.cpp

HEADERS += \
    ...existing...
    src/DownloadRegistry.h \
    src/NowPlayingNotifier.h
```

(Add `src/NowPlayingNotifier.cpp` / `.h` as new continuation lines; do not duplicate existing entries.)

- [ ] **Step 4: Wire into `src/main.cpp`**

(a) Near the other manager includes at the top of `main.cpp`, add:

```cpp
#include "NowPlayingNotifier.h"
```

(b) After `DownloadRegistry downloads(&storage, &player);` (line 421):

```cpp
    NowPlayingNotifier notifier(&player);
```

(c) After `view.rootContext()->setContextProperty("downloads", &downloads);` (line 437):

```cpp
    view.rootContext()->setContextProperty("notifier", &notifier);
```

(d) Inside the existing `#ifdef Q_OS_SYMBIAN` block after `view.show();`, after the `VolumeKeyCapturer` setup (after line 462, still inside the ifdef), add:

```cpp
    // Pigler notifications register after the window is foreground (same reason
    // as VolumeKeyCapturer above: needs the app focused / scheduler running).
    notifier.init();
```

- [ ] **Step 5: Verify the simulator build + run**

Run: `pwsh scripts/build-simulator.ps1 -Config Debug`
Expected: exit 0, `build-simulator/debug/Xyz.exe` produced.

Run: `pwsh build-simulator/debug/Xyz.run.ps1`
Expected: the app launches and behaves exactly as before (notifier is a no-op off Symbian). Close it after confirming no crash/regression.

- [ ] **Step 6: Verify the Symbian ARM compile-check**

Run: `pwsh scripts/build-symbian.ps1 -Config Debug -Arch armv5`
Expected: compiles and links with exit 0 (the skeleton `init()`/`refresh()` are empty but valid; `onTap` emits the signal).

- [ ] **Step 7: Commit**

```bash
git add src/NowPlayingNotifier.h src/NowPlayingNotifier.cpp Xyz.pro src/main.cpp
git commit -m "feat(notify): NowPlayingNotifier seam + main.cpp wiring (no-op skeleton)"
```

---

### Task 3: Placeholder notification icon asset

Add the placeholder PNG the notification will display, and register it in the qrc so `:/qml/gfx/notif-icon.png` resolves.

**Files:**
- Create: `qml/gfx/notif-icon.png` (64×64)
- Modify: `qml/qml.qrc` (add the file under the `/qml` prefix alongside the other `gfx/icon-*.svg` entries)

**Interfaces:**
- Consumes: nothing.
- Produces: resource path `:/qml/gfx/notif-icon.png` for Task 4's `applyIcon()`.

- [ ] **Step 1: Generate the placeholder PNG**

Run (PowerShell — draws a dark brand circle with a white center dot; this is explicitly a placeholder):

```powershell
Add-Type -AssemblyName System.Drawing
$size = 64
$bmp = New-Object System.Drawing.Bitmap $size, $size
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.Clear([System.Drawing.Color]::Transparent)
$bg = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255,43,45,66))
$g.FillEllipse($bg, 2, 2, ($size-4), ($size-4))
$fg = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
$g.FillEllipse($fg, 22, 22, 20, 20)
$g.Dispose()
$out = Join-Path (Get-Location) 'qml\gfx\notif-icon.png'
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Host "wrote $out"
```

Expected: prints `wrote ...\qml\gfx\notif-icon.png`; the file exists and is a valid 64×64 PNG.

- [ ] **Step 2: Register it in `qml/qml.qrc`**

Add a line next to the other `gfx/` entries (inside the `<qresource prefix="/qml">` block):

```xml
        <file>gfx/notif-icon.png</file>
```

- [ ] **Step 3: Verify the build picks up the resource**

Run: `pwsh scripts/build-simulator.ps1 -Config Debug`
Expected: exit 0. (rcc embeds the new PNG; a missing/misnamed file fails the build, so a clean build confirms the qrc entry resolves.)

- [ ] **Step 4: Commit**

```bash
git add qml/gfx/notif-icon.png qml/qml.qrc
git commit -m "feat(notify): placeholder notification icon asset"
```

---

### Task 4: Implement the Symbian notification behavior

Fill in `init()`, `refresh()`, and `applyIcon()` so the single notification is created/updated/removed in step with the player, and taps fire the QML signal.

**Files:**
- Modify: `src/NowPlayingNotifier.cpp` (replace the skeleton `init()`, `refresh()`, `applyIcon()` from Task 2)

**Interfaces:**
- Consumes: `PlayerController` getters/signals from `src/PlayerController.h` — `QString currentEid()`/`currentEidChanged()`, `QString currentTitle()`/`currentTitleChanged()`, `QString currentShow()`/`currentShowChanged()`, `stateChanged()`; and `QPiglerAPI` from Task 1. Resource `:/qml/gfx/notif-icon.png` from Task 3.
- Produces: a fully working `notifier` that emits `openCurrentEpisodeRequested()` on tap (consumed by Task 5).

- [ ] **Step 1: Replace `init()` with the real implementation**

In `src/NowPlayingNotifier.cpp`, replace the empty `init()` body with:

```cpp
void NowPlayingNotifier::init()
{
#ifdef Q_OS_SYMBIAN
    m_api = new QPiglerAPI(this);
    const qint32 rc = m_api->init(QString::fromLatin1("Xiaoyuzhou"));
    if (rc < 0) {
        qWarning("Pigler init failed (%d); notifications disabled. "
                 "Install Pigler.sis from https://nnproject.cc/pna", rc);
        m_available = false;
        return;
    }
    m_available = true;

    connect(m_api, SIGNAL(handleTap(qint32)), this, SLOT(onTap(qint32)));

    // Reconcile whenever the current episode or playback state changes.
    connect(m_player, SIGNAL(currentEidChanged()),   this, SLOT(refresh()));
    connect(m_player, SIGNAL(currentTitleChanged()), this, SLOT(refresh()));
    connect(m_player, SIGNAL(currentShowChanged()),  this, SLOT(refresh()));
    connect(m_player, SIGNAL(stateChanged()),        this, SLOT(refresh()));

    refresh();   // seed from whatever is already loaded
#endif
}
```

- [ ] **Step 2: Replace `refresh()` with the create/update/remove logic**

```cpp
void NowPlayingNotifier::refresh()
{
#ifdef Q_OS_SYMBIAN
    if (!m_available)
        return;

    const QString eid   = m_player->currentEid();
    const QString title = m_player->currentTitle();
    const QString show  = m_player->currentShow();

    if (eid.isEmpty()) {
        // Stopped / idle -> clear the notification.
        if (m_notifId >= 0) {
            m_api->removeNotification(m_notifId);
            m_notifId = -1;
            m_iconSet = false;
        }
        return;
    }

    if (m_notifId < 0) {
        m_notifId = m_api->createNotification(title, show);
        if (m_notifId < 0) {   // creation failed; retry on the next change
            m_notifId = -1;
            return;
        }
        m_api->setLaunchAppOnTap(m_notifId, true);
        applyIcon();
    } else {
        m_api->updateNotification(m_notifId, title, show);
    }
#endif
}
```

- [ ] **Step 3: Replace `applyIcon()` with the placeholder-icon loader**

```cpp
#ifdef Q_OS_SYMBIAN
void NowPlayingNotifier::applyIcon()
{
    if (m_iconSet || m_notifId < 0)
        return;
    QImage icon(QString::fromLatin1(":/qml/gfx/notif-icon.png"));
    if (!icon.isNull()) {
        m_api->setNotificationIcon(m_notifId, icon);
        m_iconSet = true;
    }
}
#endif
```

(Leave `onTap()` from Task 2 as-is — it already emits `openCurrentEpisodeRequested()`.)

- [ ] **Step 4: Verify the simulator build still compiles (no-op path intact)**

Run: `pwsh scripts/build-simulator.ps1 -Config Debug`
Expected: exit 0. The new code is entirely inside `#ifdef Q_OS_SYMBIAN`, so win32 still builds the no-op.

- [ ] **Step 5: Verify the Symbian ARM compile-check**

Run: `pwsh scripts/build-symbian.ps1 -Config Debug -Arch armv5`
Expected: exit 0; `NowPlayingNotifier.cpp` compiles against `QPiglerAPI` and `PlayerController` and links. If `PlayerController::stop()` turns out not to clear `currentEid`, the `stateChanged()` connection still drives removal when state returns to Idle — no code change needed, but note it for the device test.

- [ ] **Step 6: Commit**

```bash
git add src/NowPlayingNotifier.cpp
git commit -m "feat(notify): create/update/remove Pigler notification from player state"
```

---

### Task 5: QML tap wiring → open the episode page

Connect the notifier's tap signal to the existing navigation so a tap opens the current episode's detail page.

**Files:**
- Modify: `qml/AppWindow.qml` (add a `Connections` element at the root level of `XyzPageStackWindow`, e.g. after the function block, before the page declarations)

**Interfaces:**
- Consumes: context property `notifier` and its signal `openCurrentEpisodeRequested()` (Task 2/4); existing function `openEpisodeForCurrent()` (`qml/AppWindow.qml:31`).
- Produces: end-to-end tap → episode page behavior.

- [ ] **Step 1: Add the `Connections` element**

In `qml/AppWindow.qml`, inside the root `XyzPageStackWindow { ... }`, add (placement: after the `handleTab` function / alongside other top-level children — not inside a function):

```qml
    // A tap on the Pigler now-playing notification opens the current
    // episode's detail page (Pigler has already foregrounded the app).
    Connections {
        target: notifier
        onOpenCurrentEpisodeRequested: openEpisodeForCurrent()
    }
```

- [ ] **Step 2: Verify the simulator build + run**

Run: `pwsh scripts/build-simulator.ps1 -Config Debug`
Expected: exit 0.

Run: `pwsh build-simulator/debug/Xyz.run.ps1`
Expected: app launches; no QML error about `notifier` or `onOpenCurrentEpisodeRequested` in the console (the context property exists cross-platform). The signal simply never fires in the simulator. Close after confirming.

- [ ] **Step 3: Commit**

```bash
git add qml/AppWindow.qml
git commit -m "feat(notify): tap notification opens the current episode page"
```

---

### Task 6: README install instructions

Document that end users must install the Pigler server before notifications work.

**Files:**
- Modify: `README.md` (add a "Notifications (Pigler)" section)

**Interfaces:**
- Consumes: nothing. Produces: user-facing docs.

- [ ] **Step 1: Add the section to `README.md`**

Append (or place in a sensible existing section) the following. If `README.md` has a features/requirements area, put it there; otherwise add a new top-level section near the end:

```markdown
## Notifications (Pigler)

The now-playing notification uses the **Pigler Notifications API (PNA)**, a
separate on-device service. To see notifications, install it on the phone:

1. Download and install **`Pigler.sis`** from <https://nnproject.cc/pna/>.
2. Reboot the phone.

Without Pigler installed the app runs normally — you just won't get the
status-panel notification. Tapping the notification opens the app at the
currently playing episode. The notification icon is currently a placeholder.
```

- [ ] **Step 2: Verify**

Read back `README.md` and confirm the section renders (valid Markdown, working link). No build needed.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: note Pigler install requirement for notifications"
```

---

### Task 7: On-device verification + DEVICE_NOTES log

The human runs the built SIS on the Nokia C7 (with `Pigler.sis` installed) and records the result. This is the real acceptance test.

**Files:**
- Modify: `docs/DEVICE_NOTES.md` (append a dated entry)

**Interfaces:**
- Consumes: a signed SIS from the Symbian build (`scripts/build-sis.ps1` / `scripts/package-symbian.ps1`).
- Produces: a recorded pass/fail with any Symbian error codes.

- [ ] **Step 1: Build + package the SIS**

Run: `pwsh scripts/build-symbian.ps1 -Config Release -Arch armv5`
Then package per the project's flow (e.g. `pwsh scripts/build-sis.ps1` or `pwsh scripts/package-symbian.ps1`).
Expected: a self-signed SIS is produced.

- [ ] **Step 2: Install and run the device test checklist**

On the device (with `Pigler.sis` already installed + rebooted):
1. Install and launch the app.
2. Start playing an episode → a notification appears in the status panel showing the **episode title** (line 1) and **show name** (line 2) with the placeholder icon.
3. Pause playback → the notification **stays**.
4. Resume, then tap the notification → the app comes to the **foreground** and the **episode detail page** for that episode opens.
5. Stop playback (or close the app) → the notification is **removed**.
6. (Negative) Without Pigler installed, the app still plays normally with no notification and no crash.

- [ ] **Step 3: Record the result in `docs/DEVICE_NOTES.md`**

Append a dated heading per the project rule (`## YYYY-MM-DD — Title`), e.g.:

```markdown
## 2026-06-27 — Pigler now-playing notification

- Pigler.sis vX installed; app build <git short sha>.
- Result: <pass/fail per checklist step>.
- Error codes / surprises: <e.g. init() return value, any KErr*>.
- Notes: <icon size, single-line vs two-line rendering, tap latency>.
```

- [ ] **Step 4: Commit**

```bash
git add docs/DEVICE_NOTES.md
git commit -m "docs(device): log Pigler notification on-device test"
```

---

## Self-Review

**Spec coverage:**
- Goal (show current episode, tap → detail page) → Tasks 4 + 5. ✓
- Vendor source (decision A1) + `-lrandom -laknnotify`, symbian scope → Task 1. ✓
- Dedicated `NowPlayingNotifier` seam (decision B1), no-op off Symbian → Tasks 2 + 4. ✓
- Lifecycle: visible while loaded, persists through pause, removed on stop/close → Task 4 `refresh()` (keyed on `currentEid`, stop clears, destructor removes). ✓
- Content: title = episode, line 2 = show → Task 4 `createNotification(title, show)`. ✓
- Placeholder icon → Task 3 + `applyIcon()`. ✓
- Graceful degradation if Pigler absent → Task 4 `init()` `m_available` guard. ✓
- README install note → Task 6. ✓
- Verification: simulator build, ARM compile-check, on-device log → every task + Task 7. ✓

**Placeholder scan:** No "TBD/TODO/handle edge cases" left; the one genuinely repo-dependent detail (exact transitive header set of the vendored sources) is handled by an explicit clone-and-grep step (Task 1 Step 3), not a hand-wave.

**Type consistency:** `NowPlayingNotifier(PlayerController*, QObject*)`, `init()`, `refresh()`, `onTap(qint32)`, `applyIcon()`, signal `openCurrentEpisodeRequested()`, members `m_api/m_notifId/m_available/m_iconSet` — defined in Task 2 header, used identically in Task 4. `QPiglerAPI` method names match Task 1's Produces block (`init`, `createNotification`, `updateNotification`, `removeNotification`, `setNotificationIcon`, `setLaunchAppOnTap`, `close`, `handleTap`). QML `notifier` / `openCurrentEpisodeRequested` / `openEpisodeForCurrent()` match across Tasks 2, 4, 5. ✓
