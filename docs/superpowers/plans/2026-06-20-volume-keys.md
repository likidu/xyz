# Hardware Volume-Key Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Nokia X7-00 side volume keys step podcast playback volume by ±10%.

**Architecture:** The side volume keys are RemCon media keys (not window-server key events), so we register a native `CRemConCoreApiTarget` whose observer routes `VolumeUp`/`VolumeDown` to a new `AudioEngine::nudgeVolume(±0.1)`. All native code is `#ifdef Q_OS_SYMBIAN`-guarded and added to `Xyz.pro` only under the `symbian {}` scope, so the Simulator (mingw) build is untouched.

**Tech Stack:** Qt 4.7.4 / QtMobility multimedia, Symbian SR1 (SymbianSR1Qt474 SDK, RVCT 4.0 via sbsv2/Raptor), RemCon Core API (`remconcoreapi.lib`, `remconinterfacebase.lib`).

## Global Constraints

- **Step size:** ±0.1 (10 steps silent→max). Clamp volume to `[0.0, 1.0]`.
- **No UI:** volume change only; no on-screen indicator in this plan.
- **Simulator build must stay green:** native source/header added to `Xyz.pro` ONLY inside `symbian {}`; the files are additionally wrapped in `#ifdef Q_OS_SYMBIAN`.
- **Capabilities:** start with the current set (`NetworkServices ReadUserData WriteUserData UserEnvironment`). Only if device registration returns `KErrPermissionDenied`, add `LocalServices` (still self-signable).
- **No host unit-test harness exists** in this project (only `qml/SelfTestPage.qml` + on-device testing). Verification is: Simulator build compiles & runs, then on-device behavior. This is a documented project reality, not an omission.
- **Device-experiment logging:** after the device test, append a dated `## 2026-06-20 — …` entry to `docs/DEVICE_NOTES.md` with the result and any error codes (per CLAUDE.md).
- **Symbian audio rule (unchanged):** never write the QML `Audio.position` property; drive playback only through `audioEngine`. (Not touched here, but the project rule stands.)

## File Structure

- **Create:** `src/VolumeKeyCapturer.h` — declares the native RemCon target/observer. One responsibility: own the RemCon registration and translate volume commands into `AudioEngine` calls.
- **Create:** `src/VolumeKeyCapturer.cpp` — implements it. Symbian-only.
- **Modify:** `src/AudioEngine.h` / `src/AudioEngine.cpp` — add `nudgeVolume(double)`.
- **Modify:** `Xyz.pro` — link RemCon libs and compile the native source, under `symbian {}` only.
- **Modify:** `src/main.cpp` — construct/destroy the capturer around `app.exec()`, Symbian-guarded.
- **Modify:** `docs/DEVICE_NOTES.md` — record the device test.

---

### Task 1: `AudioEngine::nudgeVolume(double delta)`

This is the cross-platform piece (compiles on Simulator and Symbian). It is the only part verifiable on the host.

**Files:**
- Modify: `src/AudioEngine.h` (public method declaration, near `setVolume` at line 52)
- Modify: `src/AudioEngine.cpp` (implementation, after `setVolume` at lines 61–71)

**Interfaces:**
- Consumes: existing `AudioEngine::setVolume(double)` and member `double m_volume`.
- Produces: `Q_INVOKABLE void AudioEngine::nudgeVolume(double delta);` — adjusts current volume by `delta`, clamped to `[0.0, 1.0]`. Made `Q_INVOKABLE` so it is callable both from `VolumeKeyCapturer` (C++) and, for verification, from QML/SelfTestPage. Task 2's `VolumeKeyCapturer` calls `nudgeVolume(+0.1)` / `nudgeVolume(-0.1)`.

- [ ] **Step 1: Declare the method in the header**

In `src/AudioEngine.h`, directly after the `void setVolume(double vol);` line (line 52), add:

```cpp
    Q_INVOKABLE void nudgeVolume(double delta);
```

- [ ] **Step 2: Implement it**

In `src/AudioEngine.cpp`, immediately after the closing brace of `setVolume()` (after line 71), add:

```cpp
void AudioEngine::nudgeVolume(double delta)
{
    setVolume(qBound(0.0, m_volume + delta, 1.0));
}
```

(`qBound` comes from `<QtGlobal>`, already transitively included via QObject. `setVolume` already no-ops on an unchanged value, applies to `m_player` only when it exists, and emits `volumeChanged`.)

- [ ] **Step 3: Verify the clamp logic by inspection**

Confirm the three cases hold in the code above:
- `m_volume = 0.50`, `delta = +0.1` → `0.60` (normal step).
- `m_volume = 0.95`, `delta = +0.1` → `qBound(0,1.05,1)` = `1.0` (clamped high).
- `m_volume = 0.05`, `delta = -0.1` → `qBound(0,-0.05,1)` = `0.0` (clamped low).

- [ ] **Step 4: Build the Simulator target to confirm it compiles**

Run: `pwsh scripts/build-simulator.ps1 -Config Debug`
Expected: `[INFO] Build succeeded: ...\build-simulator\debug\Xyz.exe` and exit code 0.

- [ ] **Step 5 (optional host runtime check): exercise from SelfTestPage**

If you want runtime confirmation on the Simulator (the keys themselves never fire there), temporarily add to `qml/SelfTestPage.qml` a button with `onClicked: { audioEngine.nudgeVolume(0.1); console.log("vol=" + audioEngine.volume) }` and a second with `-0.1`, run `pwsh build-simulator/debug/Xyz.run.ps1`, click past 1.0 and below 0.0, confirm the logged `vol` clamps at `1` and `0`. **Revert this temporary QML before committing** (keep the change surgical).

- [ ] **Step 6: Commit**

```bash
git add src/AudioEngine.h src/AudioEngine.cpp
git commit -m "feat(audio): add AudioEngine::nudgeVolume(delta) clamped to [0,1]"
```

---

### Task 2: Native RemCon volume-key capture + wiring

Everything here compiles only for Symbian; it is verified by the Symbian build linking and by the on-device test. Drawn as one task because none of the sub-pieces (class, `.pro`, `main.cpp`) is independently testable — they only become real on the device together.

**Files:**
- Create: `src/VolumeKeyCapturer.h`
- Create: `src/VolumeKeyCapturer.cpp`
- Modify: `Xyz.pro` (inside the `symbian {}` block, lines 30–49)
- Modify: `src/main.cpp` (around `AudioEngine audioEngine;` line 413 and before `return app.exec();` line 444)
- Modify: `docs/DEVICE_NOTES.md`

**Interfaces:**
- Consumes: `AudioEngine::nudgeVolume(double)` from Task 1.
- Produces: `VolumeKeyCapturer::NewL(AudioEngine*)` (static two-phase factory) returning an owning pointer the caller must `delete`.

- [ ] **Step 1: Create the header `src/VolumeKeyCapturer.h`**

```cpp
#ifndef VOLUMEKEYCAPTURER_H
#define VOLUMEKEYCAPTURER_H

#ifdef Q_OS_SYMBIAN

#include <e32base.h>
#include <remconcoreapitarget.h>
#include <remconcoreapitargetobserver.h>
#include <remconinterfaceselector.h>

class AudioEngine;

// Registers a RemCon Core API target so the phone's side volume keys (which are
// RemCon media keys, not window-server key events) reach the app, and steps the
// podcast playback volume via AudioEngine::nudgeVolume(). Symbian-only.
class VolumeKeyCapturer : public CBase, public MRemConCoreApiTargetObserver
{
public:
    static VolumeKeyCapturer* NewL(AudioEngine* aEngine);
    ~VolumeKeyCapturer();

    // MRemConCoreApiTargetObserver — all are pure virtual and must be defined.
    void MrccatoCommand(TRemConCoreApiOperationId aOperationId,
                        TRemConCoreApiButtonAction aButtonAct);
    void MrccatoPlay(TRemConCoreApiPlaybackSpeed aSpeed,
                     TRemConCoreApiButtonAction aButtonAct);
    void MrccatoTuneFunction(TBool aTwoPart, TUint aMajorChannel,
                             TUint aMinorChannel,
                             TRemConCoreApiButtonAction aButtonAct);
    void MrccatoSelectDiskFunction(TUint aDisk,
                                   TRemConCoreApiButtonAction aButtonAct);
    void MrccatoSelectAvInputFunction(TUint8 aAvInputSignalNumber,
                                      TRemConCoreApiButtonAction aButtonAct);
    void MrccatoSelectAudioInputFunction(TUint8 aAudioInputSignalNumber,
                                         TRemConCoreApiButtonAction aButtonAct);

private:
    VolumeKeyCapturer(AudioEngine* aEngine);
    void ConstructL();

    AudioEngine* iEngine;                  // not owned
    CRemConInterfaceSelector* iSelector;   // owned
    CRemConCoreApiTarget* iCoreTarget;     // owned by iSelector, not deleted here
};

#endif // Q_OS_SYMBIAN
#endif // VOLUMEKEYCAPTURER_H
```

> **Before relying on the observer signatures:** open the SDK headers
> `…\SymbianSR1Qt474\epoc32\include\mw\remconcoreapitargetobserver.h` and
> `remconcoreapitarget.h` and confirm the exact pure-virtual method list and the
> `…Response` signatures for this SDK. Adjust the stubs/signatures if they differ.
> (This is the one spot the design flagged as confirm-at-implementation.)

- [ ] **Step 2: Create the implementation `src/VolumeKeyCapturer.cpp`**

```cpp
#include "VolumeKeyCapturer.h"

#ifdef Q_OS_SYMBIAN

#include "AudioEngine.h"

VolumeKeyCapturer::VolumeKeyCapturer(AudioEngine* aEngine)
    : iEngine(aEngine), iSelector(0), iCoreTarget(0)
{
}

VolumeKeyCapturer* VolumeKeyCapturer::NewL(AudioEngine* aEngine)
{
    VolumeKeyCapturer* self = new (ELeave) VolumeKeyCapturer(aEngine);
    CleanupStack::PushL(self);
    self->ConstructL();
    CleanupStack::Pop(self);
    return self;
}

void VolumeKeyCapturer::ConstructL()
{
    iSelector = CRemConInterfaceSelector::NewL();
    iCoreTarget = CRemConCoreApiTarget::NewL(*iSelector, *this);
    iSelector->OpenTargetL();
}

VolumeKeyCapturer::~VolumeKeyCapturer()
{
    delete iSelector;   // owns and tears down iCoreTarget
}

void VolumeKeyCapturer::MrccatoCommand(TRemConCoreApiOperationId aOperationId,
                                       TRemConCoreApiButtonAction aButtonAct)
{
    // Act once per press/click; ignore the matching release so a single tap = one step.
    if (aButtonAct == ERemConCoreApiButtonRelease)
        return;

    TRequestStatus status;
    switch (aOperationId) {
    case ERemConCoreApiVolumeUp:
        iCoreTarget->VolumeUpResponse(status, KErrNone);
        User::WaitForRequest(status);
        if (iEngine)
            iEngine->nudgeVolume(0.1);
        break;
    case ERemConCoreApiVolumeDown:
        iCoreTarget->VolumeDownResponse(status, KErrNone);
        User::WaitForRequest(status);
        if (iEngine)
            iEngine->nudgeVolume(-0.1);
        break;
    default:
        break;
    }
}

// Unused observer callbacks — required overrides, no-ops.
void VolumeKeyCapturer::MrccatoPlay(TRemConCoreApiPlaybackSpeed, TRemConCoreApiButtonAction) {}
void VolumeKeyCapturer::MrccatoTuneFunction(TBool, TUint, TUint, TRemConCoreApiButtonAction) {}
void VolumeKeyCapturer::MrccatoSelectDiskFunction(TUint, TRemConCoreApiButtonAction) {}
void VolumeKeyCapturer::MrccatoSelectAvInputFunction(TUint8, TRemConCoreApiButtonAction) {}
void VolumeKeyCapturer::MrccatoSelectAudioInputFunction(TUint8, TRemConCoreApiButtonAction) {}

#endif // Q_OS_SYMBIAN
```

> The local-`TRequestStatus` + `User::WaitForRequest` pattern sends the required RemCon
> ack synchronously (the response completes immediately), avoiding a `CActive`. If the
> device panics with a stray-signal / `E32USER-CBase` on key press, switch to acknowledging
> via a `CActive` (member `TRequestStatus`, `SetActive()` after each `…Response`, empty
> `RunL`). Decide based on device behavior; the synchronous form is the simpler default.

- [ ] **Step 3: Wire the libraries and source into `Xyz.pro`**

In `Xyz.pro`, inside the existing `symbian {` block (after `TARGET.CAPABILITY += …`, around line 38), add:

```pro
    # Hardware volume keys come through the RemCon framework, not key events.
    LIBS += -lremconcoreapi -lremconinterfacebase
    SOURCES += src/VolumeKeyCapturer.cpp
    HEADERS += src/VolumeKeyCapturer.h
```

(Do NOT add these to the top-level `SOURCES`/`HEADERS` lists at lines 51–71 — keeping them under `symbian {}` is what protects the Simulator build.)

- [ ] **Step 4: Construct and destroy the capturer in `src/main.cpp`**

Add the include near the other manager includes (after line 33, `#include "PlayerController.h"`):

```cpp
#ifdef Q_OS_SYMBIAN
#include "VolumeKeyCapturer.h"
#endif
```

Immediately after `AudioEngine audioEngine;` (line 413), add:

```cpp
#ifdef Q_OS_SYMBIAN
    VolumeKeyCapturer *volumeKeys = 0;
    TRAPD(vkErr, volumeKeys = VolumeKeyCapturer::NewL(&audioEngine));
    if (vkErr != KErrNone)
        qWarning("VolumeKeyCapturer init failed: %d (volume keys disabled)", vkErr);
#endif
```

Change the final line `return app.exec();` (line 444) to capture the result and clean up:

```cpp
    const int rc = app.exec();
#ifdef Q_OS_SYMBIAN
    delete volumeKeys;   // before audioEngine goes out of scope
#endif
    return rc;
```

- [ ] **Step 5: Confirm the Simulator build is still green (regression guard)**

Run: `pwsh scripts/build-simulator.ps1 -Config Debug -Clean`
Expected: build succeeds, `Xyz.exe` produced. The native class must NOT be compiled here (it is guarded out); if the linker complains about RemCon symbols on the Simulator, the `.pro` additions leaked outside `symbian {}` — fix Step 3.

- [ ] **Step 6: Build the self-signed SIS for the device**

Run: `pwsh scripts/build-sis.ps1 -Config Release -Arch armv5`
Expected: `[INFO] Done. Self-signed SIS ready: …\build-symbian\armv5-release\Xyz_selfsigned.sis`.
- If qmake/make fails to find `remconcoreapi.lib`, confirm the lib name against `…\SymbianSR1Qt474\epoc32\release\armv5\lib\` and adjust the `-l` names in Step 3.

- [ ] **Step 7: Deploy and test on the X7-00**

Transfer the `.sis` (e.g. Bluetooth), install, launch, start playing an episode, then press the side volume up/down keys. Confirm:
- Loudness changes audibly.
- ~10 up-presses go silent→max; ~10 down-presses go max→silent (±10% per press).
- If installation refuses or the app logs `VolumeKeyCapturer init failed: -46` (`KErrPermissionDenied`), add `LocalServices` to `TARGET.CAPABILITY` in `Xyz.pro` (line 38) and rebuild (Step 6).
- Note whether the system volume HUD still appears (informs the deferred indicator decision).

- [ ] **Step 8: Record the device result in `docs/DEVICE_NOTES.md`**

Append a dated entry:

```markdown
## 2026-06-20 — Side volume keys control playback via RemCon

Captured the X7-00 side volume keys with CRemConCoreApiTarget (remconcoreapi.lib).
Plain Qt key events never see these keys — they route through RemCon. Routed
VolumeUp/Down to AudioEngine::nudgeVolume(±0.1). Capabilities used: <list>.
System volume HUD: <appeared / suppressed>. Result: <works / issue + error code>.
```

- [ ] **Step 9: Commit**

```bash
git add src/VolumeKeyCapturer.h src/VolumeKeyCapturer.cpp Xyz.pro src/main.cpp docs/DEVICE_NOTES.md
git commit -m "feat(audio): capture X7-00 side volume keys via RemCon, route to playback volume"
```

---

## Self-Review

**1. Spec coverage:**
- RemCon target capture (spec component 2) → Task 2 Steps 1–2. ✓
- `nudgeVolume` clamp (spec component 1) → Task 1. ✓
- `.pro` libs under `symbian {}` (spec component 3) → Task 2 Step 3. ✓
- `main.cpp` TRAPD construct + graceful degradation (spec component 4) → Task 2 Step 4. ✓
- ±0.1 / no UI (spec goal) → Global Constraints + Task 1 Step 2 + Task 2 Step 2. ✓
- Verification: Simulator green + device test (spec) → Task 1 Step 4, Task 2 Steps 5–7. ✓
- Risks: capability fallback (Task 2 Step 7), HUD note (Step 7), hold-behavior (`ButtonRelease` filter, Step 2), response-API confirmation (Step 1/2 notes), DEVICE_NOTES (Step 8). ✓

**2. Placeholder scan:** No "TBD"/"add error handling" placeholders. The two "confirm against SDK headers" notes are concrete verification actions with exact file paths, not deferred design.

**3. Type consistency:** `nudgeVolume(double)` declared in Task 1, called identically in Task 2. `NewL(AudioEngine*)` defined and consumed consistently. Member names (`iEngine`, `iSelector`, `iCoreTarget`) consistent between header and cpp.
