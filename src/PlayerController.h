#ifndef PLAYERCONTROLLER_H
#define PLAYERCONTROLLER_H

#include <QtCore/QObject>
#include <QtCore/QString>
#include <QtCore/QUrl>

#include "EpisodeDownloader.h"

class AudioEngine;

// The QML-facing player seam. Orchestrates download-then-play: an episode URL is
// fetched to local flash by EpisodeDownloader, then handed to AudioEngine as a
// local file:// (MMF's most stable input). Exposes one unified object the episode
// page binds to -- it relays AudioEngine's position/duration/state so callers need
// not touch `audioEngine` directly.
class PlayerController : public QObject
{
    Q_OBJECT

    Q_PROPERTY(int state READ state NOTIFY stateChanged)
    Q_PROPERTY(double downloadProgress READ downloadProgress NOTIFY downloadProgressChanged)
    Q_PROPERTY(int position READ position NOTIFY positionChanged)
    Q_PROPERTY(int duration READ duration NOTIFY durationChanged)
    Q_PROPERTY(QString errorString READ errorString NOTIFY errorStringChanged)
    Q_PROPERTY(QString currentEid READ currentEid NOTIFY currentEidChanged)
    Q_PROPERTY(QString currentTitle READ currentTitle NOTIFY currentTitleChanged)
    // Local file handed to the player (diagnostic: confirms a PUBLIC, MMF-readable path).
    Q_PROPERTY(QString currentSourcePath READ currentSourcePath NOTIFY currentSourcePathChanged)

    // State constants for QML (mirrors AudioEngine's convention).
    Q_PROPERTY(int idleState READ idleState CONSTANT)
    Q_PROPERTY(int downloadingState READ downloadingState CONSTANT)
    Q_PROPERTY(int preparingState READ preparingState CONSTANT)
    Q_PROPERTY(int playingState READ playingState CONSTANT)
    Q_PROPERTY(int pausedState READ pausedState CONSTANT)
    Q_PROPERTY(int errorState READ errorState CONSTANT)

public:
    explicit PlayerController(AudioEngine *audio, QObject *parent = 0);

    int state() const { return m_state; }
    double downloadProgress() const { return m_downloadProgress; }
    int position() const;
    int duration() const;
    QString errorString() const { return m_errorString; }
    QString currentEid() const { return m_currentEid; }
    QString currentTitle() const { return m_currentTitle; }
    QString currentSourcePath() const { return m_currentSourcePath; }

    int idleState() const { return Idle; }
    int downloadingState() const { return Downloading; }
    int preparingState() const { return Preparing; }
    int playingState() const { return Playing; }
    int pausedState() const { return Paused; }
    int errorState() const { return Error; }

    // Fetch `url` to disk, then play it. `eid` keys the on-disk cache; `title` is
    // surfaced via currentTitle for any now-playing UI.
    Q_INVOKABLE void playEpisode(const QUrl &url, const QString &eid, const QString &title);
    Q_INVOKABLE void pause();
    Q_INVOKABLE void resume();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void seek(int positionMs);

    // Two-step (download, then play) for the episode page.
    Q_INVOKABLE void download(const QUrl &url, const QString &eid);  // download only
    Q_INVOKABLE void cancelDownload();
    Q_INVOKABLE bool isDownloaded(const QString &eid);
    Q_INVOKABLE QString downloadedSizeText(const QString &eid);
    Q_INVOKABLE void deleteDownload(const QString &eid);

signals:
    void stateChanged();
    void downloadProgressChanged();
    void positionChanged();
    void durationChanged();
    void errorStringChanged();
    void currentEidChanged();
    void currentTitleChanged();
    void currentSourcePathChanged();

private slots:
    void onDownloadProgress(qint64 received, qint64 total);
    void onDownloadFinished(const QString &localPath);
    void onDownloadFailed(const QString &error);
    void onAudioStateChanged();
    void onAudioStatusChanged();
    void onAudioPositionChanged();
    void onAudioDurationChanged();
    void onAudioErrorChanged();

private:
    enum State { Idle = 0, Downloading = 1, Preparing = 2, Playing = 3, Paused = 4, Error = 5 };

    void setState(int s);
    void setDownloadProgress(double p);
    void setErrorString(const QString &e);
    void maybeStartPlayback();
    static QString formatBytes(qint64 bytes);

    AudioEngine *m_audio;
    EpisodeDownloader m_downloader;
    bool m_waitingToPlay;       // source set, deferring play() until media loads
    bool m_downloadOnly;        // download() without auto-play
    int m_state;
    double m_downloadProgress;
    QString m_errorString;
    QString m_currentEid;
    QString m_currentTitle;
    QString m_currentSourcePath;
};

#endif // PLAYERCONTROLLER_H
