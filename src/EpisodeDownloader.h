#ifndef EPISODEDOWNLOADER_H
#define EPISODEDOWNLOADER_H

#include <QtCore/QObject>
#include <QtCore/QString>
#include <QtCore/QUrl>
#include <QtCore/QTimer>

class QNetworkAccessManager;
class QNetworkReply;
class QFile;

// Downloads one episode audio URL to a local file, streaming the body to disk in
// chunks (never holding the whole file in RAM -- critical on the ~256 MB C7). The
// HTTPS fetch goes through Qt's own QNetworkAccessManager so it can tolerate the
// device's stale CA store via ignoreSslErrors(); the native MMF streaming stack
// cannot. Caches by eid: a completed file is reused instead of refetched, and the
// in-flight file is written as <eid>.part then renamed on success.
class EpisodeDownloader : public QObject
{
    Q_OBJECT

public:
    explicit EpisodeDownloader(QObject *parent = 0);
    ~EpisodeDownloader();

    // Download `url`, keyed by `eid` (the cache filename). Emits finished()
    // immediately if a completed file for `eid` already exists.
    void start(const QUrl &url, const QString &eid);
    void cancel();

    // Cache queries that do NOT start a transfer (drive the episode page's
    // download/play state). cachedPath returns the existing <eid>.<ext> file or "".
    QString cachedPath(const QString &eid);
    bool isCached(const QString &eid);
    qint64 cachedSizeBytes(const QString &eid);
    bool removeCached(const QString &eid);

    // The resolved writable download directory (drives the storage meter's volume query).
    QString storageDir() { return audioDir(); }

signals:
    void progress(qint64 received, qint64 total);
    void finished(const QString &localPath);
    void failed(const QString &error);

private slots:
    void onReadyRead();
    void onReplyFinished();
    void onDownloadProgress(qint64 received, qint64 total);
    void onStallTimeout();

private:
    void startGet(const QUrl &url);
    QString audioDir();                          // writable dir by I/O probe; cached
    bool tryMakeWritable(const QString &dir);    // real write test (data-cage aware)
    static QString extensionForUrl(const QUrl &url);
    void cleanupReply();
    void closeAndRemovePart();
    void failWith(const QString &error);

    QNetworkAccessManager *m_nam;
    QNetworkReply *m_reply;
    QFile *m_file;
    QTimer m_stall;
    int m_redirects;
    QString m_audioDir;     // cached writable download dir
    QString m_eid;
    QString m_partPath;
    QString m_finalPath;
};

#endif // EPISODEDOWNLOADER_H
