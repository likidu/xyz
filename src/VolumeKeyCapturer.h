#ifndef VOLUMEKEYCAPTURER_H
#define VOLUMEKEYCAPTURER_H

#include <QtGlobal>   // defines Q_OS_SYMBIAN before we test it

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
