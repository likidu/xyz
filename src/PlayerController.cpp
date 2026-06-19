#include "PlayerController.h"
#include "AudioEngine.h"

#include <QtCore/QDebug>

PlayerController::PlayerController(AudioEngine *audio, QObject *parent)
    : QObject(parent)
    , m_audio(audio)
    , m_waitingToPlay(false)
    , m_state(Idle)
    , m_downloadProgress(0.0)
{
    connect(&m_downloader, SIGNAL(progress(qint64, qint64)),
            this, SLOT(onDownloadProgress(qint64, qint64)));
    connect(&m_downloader, SIGNAL(finished(QString)),
            this, SLOT(onDownloadFinished(QString)));
    connect(&m_downloader, SIGNAL(failed(QString)),
            this, SLOT(onDownloadFailed(QString)));

    if (m_audio) {
        connect(m_audio, SIGNAL(stateChanged()), this, SLOT(onAudioStateChanged()));
        connect(m_audio, SIGNAL(statusChanged()), this, SLOT(onAudioStatusChanged()));
        connect(m_audio, SIGNAL(positionChanged()), this, SLOT(onAudioPositionChanged()));
        connect(m_audio, SIGNAL(durationChanged()), this, SLOT(onAudioDurationChanged()));
        connect(m_audio, SIGNAL(errorStringChanged()), this, SLOT(onAudioErrorChanged()));
    }
}

int PlayerController::position() const { return m_audio ? m_audio->position() : 0; }
int PlayerController::duration() const { return m_audio ? m_audio->duration() : 0; }

void PlayerController::playEpisode(const QUrl &url, const QString &eid, const QString &title)
{
    if (!m_audio) {
        setErrorString(QLatin1String("Audio unavailable."));
        setState(Error);
        return;
    }

    m_downloader.cancel();
    m_waitingToPlay = false;
    // reset() (not prepareForNewSource) so it also clears the engine's cached source
    // URL -- otherwise replaying the same eid is a no-op (setSource ignores an
    // unchanged URL) and the deferred play never re-fires.
    m_audio->reset();                   // stop + clear media + clear source/state

    if (m_currentEid != eid) { m_currentEid = eid; emit currentEidChanged(); }
    if (m_currentTitle != title) { m_currentTitle = title; emit currentTitleChanged(); }
    setErrorString(QString());
    setDownloadProgress(0.0);
    setState(Downloading);

    qDebug() << "PlayerController: playEpisode eid=" << eid << "url=" << url.toString();
    m_downloader.start(url, eid);
}

void PlayerController::pause()  { if (m_audio) m_audio->pause(); }
void PlayerController::resume() { if (m_audio) m_audio->play(); }

void PlayerController::stop()
{
    m_downloader.cancel();
    m_waitingToPlay = false;
    if (m_audio)
        m_audio->stop();
    setDownloadProgress(0.0);
    setState(Idle);
}

void PlayerController::seek(int positionMs)
{
    if (m_audio)
        m_audio->seek(positionMs);
}

void PlayerController::onDownloadProgress(qint64 received, qint64 total)
{
    if (total > 0)
        setDownloadProgress(double(received) / double(total));
}

void PlayerController::onDownloadFinished(const QString &localPath)
{
    if (!m_audio)
        return;
    if (m_currentSourcePath != localPath) {
        m_currentSourcePath = localPath;
        emit currentSourcePathChanged();
    }
    setDownloadProgress(1.0);
    setState(Preparing);
    qDebug() << "PlayerController: download ready, loading" << localPath;
    // Defer play() until the media is loaded. On Symbian, play()-before-loaded races
    // MMF's audio-output acquisition and fails with KErrInUse (-14): the clip buffers
    // (mediaStatus 6) but never sounds and position/duration stay 0.
    m_waitingToPlay = true;
    m_audio->setSource(QUrl::fromLocalFile(localPath));
    maybeStartPlayback();   // in case it's already loaded (e.g. replay)
}

void PlayerController::maybeStartPlayback()
{
    if (!m_waitingToPlay || !m_audio)
        return;
    const int st = m_audio->status();
    if (st == m_audio->loadedStatus() || st == m_audio->bufferedStatus()) {
        m_waitingToPlay = false;
        qDebug() << "PlayerController: media loaded (status" << st << "), starting play()";
        m_audio->play();
    }
}

void PlayerController::onAudioStatusChanged()
{
    maybeStartPlayback();
}

void PlayerController::onDownloadFailed(const QString &error)
{
    qWarning() << "PlayerController: download failed:" << error;
    setErrorString(error);
    setDownloadProgress(0.0);
    setState(Error);
}

void PlayerController::onAudioStateChanged()
{
    if (!m_audio)
        return;
    // The download phase owns the state machine; ignore the audio engine's
    // stopped/loading transitions until we've handed it a file.
    if (m_state == Downloading)
        return;

    const int as = m_audio->state();
    if (as == m_audio->playingState()) {
        setState(Playing);
    } else if (as == m_audio->pausedState()) {
        setState(Paused);
    } else if (as == m_audio->stoppedState()) {
        // Only treat a stop as "done" once playback has actually begun -- during
        // Preparing the engine is briefly stopped before play() takes effect.
        if (m_state == Playing || m_state == Paused)
            setState(Idle);
    }
}

void PlayerController::onAudioPositionChanged() { emit positionChanged(); }
void PlayerController::onAudioDurationChanged() { emit durationChanged(); }

void PlayerController::onAudioErrorChanged()
{
    if (!m_audio)
        return;
    const QString err = m_audio->errorString();
    if (!err.isEmpty()) {
        setErrorString(err);
        setState(Error);
    }
}

void PlayerController::setState(int s)
{
    if (m_state == s)
        return;
    m_state = s;
    emit stateChanged();
}

void PlayerController::setDownloadProgress(double p)
{
    // Always emit the 0.0/1.0 endpoints; throttle the noisy middle to ~1% steps.
    if (p != 0.0 && p != 1.0 && qAbs(p - m_downloadProgress) < 0.01)
        return;
    if (m_downloadProgress == p)
        return;
    m_downloadProgress = p;
    emit downloadProgressChanged();
}

void PlayerController::setErrorString(const QString &e)
{
    if (m_errorString == e)
        return;
    m_errorString = e;
    emit errorStringChanged();
}
