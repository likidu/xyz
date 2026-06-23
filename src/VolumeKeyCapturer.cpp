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
