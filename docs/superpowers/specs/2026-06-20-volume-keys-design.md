# Hardware Volume-Key Control for Playback — Design

**Date:** 2026-06-20
**Status:** Approved (design), pending implementation
**Target device:** Nokia X7-00 (Symbian Anna/Belle), self-signed SIS

## Problem

On the X7-00, pressing the side volume up/down keys while a podcast is playing does
**nothing** — no loudness change, no system volume HUD. The app never wired the volume
keys: the only key handler in the tree is `AppWindow.qml:195` (`Keys.onReleased` →
`Qt.Key_Escape`), and `git log -S "Key_Volume"` is empty (the feature never existed —
this is **not** a regression from the recent `QMediaPlayer` delete fix).

**Why "nothing at all":** On Symbian, the dedicated side volume keys are **media keys
routed through the RemCon (Remote Control) framework**, not window-server key events.
They are never delivered to a Qt app as `QKeyEvent`/`Qt::Key_VolumeUp`. So neither a QML
`Keys` handler nor a `QApplication` event filter ever sees them.

## Goal

The side up/down keys step the **podcast playback volume** by **±10%** (10 steps,
silent→max). **No on-screen UI.** The Simulator build is unaffected (native code compiled
out).

Non-goals (YAGNI): in-app volume indicator UI, press-and-hold continuous ramp tuning,
mute toggle, remapping any other media keys.

## Approaches considered

| Approach | Mechanism | Verdict |
|----------|-----------|---------|
| A. Qt event filter on `Qt::Key_VolumeUp/Down` | Watch `QKeyEvent` in an app event filter | ❌ Won't work — side keys are never delivered as key events (this is exactly the current "nothing happens"). |
| B. `RWindowGroup::CaptureKey` on `EStdKeyIncVolume/DecVolume` | Capture window-server scan codes | ❌ Unreliable — the X7-00 side rocker doesn't emit those WS scan codes (same root cause as A). |
| C. **RemCon Core API target** | Register `CRemConCoreApiTarget`; observer receives volume operations | ✅ **Chosen** — documented, reliable mechanism for the side keys on Anna/Belle. |

## Design (Approach C)

### Components

**1. `AudioEngine::nudgeVolume(double delta)` — new method on existing class**

```cpp
void AudioEngine::nudgeVolume(double delta)
{
    const double newVol = qBound(0.0, m_volume + delta, 1.0);
    setVolume(newVol);   // existing path: stores m_volume, applies to m_player if it
                         // exists, emits volumeChanged
}
```

- Single source of clamping to `[0.0, 1.0]`.
- Reuses the existing `setVolume()` (`AudioEngine.cpp:61`), which already guards
  `m_player` (so adjusting while paused/stopped is safe and applies on next play) and
  emits `volumeChanged`.
- Step constant lives at the call site (`VolumeKeyCapturer`), not in `AudioEngine`:
  `±0.1`.

**2. `src/VolumeKeyCapturer.{h,cpp}` — new native class, fully `#ifdef Q_OS_SYMBIAN`-guarded**

- Implements `MRemConCoreApiTargetObserver`.
- Owns `CRemConInterfaceSelector* iSelector` and `CRemConCoreApiTarget* iCoreTarget`.
- Two-phase construction: `static VolumeKeyCapturer* NewL(AudioEngine* engine)` →
  `ConstructL()` creates the selector, creates the core-API target
  (`CRemConCoreApiTarget::NewL(*iSelector, *this)`), then `iSelector->OpenTargetL()`.
- Holds a raw `AudioEngine*` (not owned). Lifetime: constructed after and destroyed
  before `audioEngine` in `main()`, so the pointer is always valid.
- Observer callback:

```cpp
void VolumeKeyCapturer::MrccatoCommand(TRemConCoreApiOperationId aOperationId,
                                       TRemConCoreApiButtonAction aButtonAct)
{
    // Act once per discrete press (ignore the matching release).
    if (aButtonAct == ERemConCoreApiButtonRelease)
        return;
    TInt err = KErrNone;
    switch (aOperationId) {
    case ERemConCoreApiVolumeUp:
        iEngine->nudgeVolume(+0.1);
        iCoreTarget->VolumeUpResponse(iStatus, KErrNone);   // required RemCon ack
        break;
    case ERemConCoreApiVolumeDown:
        iEngine->nudgeVolume(-0.1);
        iCoreTarget->VolumeDownResponse(iStatus, KErrNone);
        break;
    default:
        break;
    }
}
```

> Implementation note: the exact response-send signature (`...Response`) and whether an
> active `TRequestStatus` / `SetActive()` is needed will be confirmed against the SDK
> RemCon headers during implementation. The observer contract and operation IDs above are
> the stable part of the design.

**3. `Xyz.pro` — inside the existing `symbian {}` block**

```pro
symbian {
    LIBS += -lremconcoreapi -lremconinterfacebase
    SOURCES += src/VolumeKeyCapturer.cpp
    HEADERS += src/VolumeKeyCapturer.h
}
```

The native source/header are added **only** under `symbian {}` so the Simulator (mingw)
build never compiles them. The files are additionally `#ifdef Q_OS_SYMBIAN`-guarded as
defense-in-depth.

**4. `main.cpp` — construct after `AudioEngine audioEngine;` (line 413)**

```cpp
#ifdef Q_OS_SYMBIAN
    VolumeKeyCapturer *volumeKeys = 0;
    TRAPD(vkErr, volumeKeys = VolumeKeyCapturer::NewL(&audioEngine));
    if (vkErr != KErrNone)
        qWarning("VolumeKeyCapturer init failed: %d (volume keys disabled)", vkErr);
#endif
    // ... existing view setup / app.exec() ...
#ifdef Q_OS_SYMBIAN
    delete volumeKeys;   // before audioEngine goes out of scope
#endif
```

### Data flow

```
side key press
  → Symbian RemCon framework
  → CRemConCoreApiTarget
  → VolumeKeyCapturer::MrccatoCommand(ERemConCoreApiVolumeUp/Down)
  → AudioEngine::nudgeVolume(±0.1)
  → m_player->setVolume(0–100) + emit volumeChanged
```

### Error handling

- Volume always clamped to `[0.0, 1.0]` in `nudgeVolume`.
- RemCon registration leaving/failing is **non-fatal**: log a `qWarning` and continue.
  The app runs normally; only the volume keys are inert (graceful degradation).

## Verification

No host unit test is possible — this is device RemCon hardware. Verification is twofold:

1. **Simulator build still compiles and runs** with the native class compiled out
   (the `#ifdef Q_OS_SYMBIAN` / `symbian {}` guards). This is the regression guard for
   the non-device build.
2. **On-device (X7-00):** play an episode, press volume up/down. Confirm loudness steps
   in ~10% increments and ~10 presses span silent→max. Record the result — and any
   capability error — in `docs/DEVICE_NOTES.md` under a dated heading.

## Risks / open items (confirm on device, log to DEVICE_NOTES.md)

1. **Capability.** RemCon target registration may need an extra capability. Start with the
   current caps (`NetworkServices ReadUserData WriteUserData UserEnvironment`); if
   registration returns `KErrPermissionDenied`, add `LocalServices` (still self-signable)
   and rebuild.
2. **System volume HUD suppression.** Becoming the RemCon volume target likely suppresses
   the OS volume HUD, so with no in-app UI there is **no visual feedback** on press. This
   matches the approved decision (no UI). If it proves disorienting on device, a minimal
   transient indicator is a small, separate follow-up.
3. **Press-and-hold.** v1 acts once per discrete press. If holding a key behaves oddly
   (no repeat, or runaway repeat), revisit how `TRemConCoreApiButtonAction` repeats are
   handled.
4. **RemCon response API exactness.** The precise `...Response`/`TRequestStatus` usage is
   confirmed against SDK headers at implementation time (see note in component 2).
