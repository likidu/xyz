#include "EpisodeDownloader.h"
#include "AppConfig.h"

#include <QtCore/QDebug>
#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QFileInfo>
#include <QtCore/QStringList>
#include <QtCore/QVariant>
#include <QtGui/QDesktopServices>
#include <QtNetwork/QNetworkAccessManager>
#include <QtNetwork/QNetworkReply>
#include <QtNetwork/QNetworkRequest>
#include <QtNetwork/QSslError>

namespace {
// Downloads are long, so the watchdog is stall-based (reset on each chunk) rather
// than the single 15 s deadline XyzApiClient uses for short API calls.
const int kStallMs = 30000;
const int kMaxRedirects = 5;
}

EpisodeDownloader::EpisodeDownloader(QObject *parent)
    : QObject(parent)
    , m_nam(new QNetworkAccessManager(this))
    , m_reply(0)
    , m_file(0)
    , m_redirects(0)
{
    m_stall.setSingleShot(true);
    connect(&m_stall, SIGNAL(timeout()), this, SLOT(onStallTimeout()));
}

EpisodeDownloader::~EpisodeDownloader()
{
    cancel();
}

void EpisodeDownloader::start(const QUrl &url, const QString &eid)
{
    cancel();               // clear any prior transfer
    m_redirects = 0;
    m_eid = eid;

    const QString dir = audioDir();
    if (dir.isEmpty()) {
        failWith(QString::fromLatin1("No writable storage for downloads."));
        return;
    }

    const QString ext = extensionForUrl(url);
    m_finalPath = QDir(dir).filePath(eid + ext);
    m_partPath = QDir(dir).filePath(eid + QLatin1String(".part"));

    if (QFile::exists(m_finalPath)) {       // cache hit -- skip the download
        qDebug() << "EpisodeDownloader: cache hit" << m_finalPath;
        emit finished(m_finalPath);
        return;
    }

    m_file = new QFile(m_partPath);
    if (!m_file->open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        delete m_file;
        m_file = 0;
        failWith(QString::fromLatin1("Cannot open download file: %1").arg(m_partPath));
        return;
    }

    startGet(url);
}

void EpisodeDownloader::startGet(const QUrl &url)
{
    QNetworkRequest request(url);
    // CDN host, not the jike gateway -- no spoof/token headers, just a UA.
    request.setRawHeader("User-Agent", "Xiaoyuzhou/2.57.1 (build:1576; iOS 17.4.1)");

    m_reply = m_nam->get(request);
    connect(m_reply, SIGNAL(readyRead()), this, SLOT(onReadyRead()));
    connect(m_reply, SIGNAL(finished()), this, SLOT(onReplyFinished()));
    connect(m_reply, SIGNAL(downloadProgress(qint64, qint64)),
            this, SLOT(onDownloadProgress(qint64, qint64)));
    // Tolerate the device's outdated CA store, same as XyzApiClient / SslIgnoringNam.
    connect(m_reply, SIGNAL(sslErrors(const QList<QSslError> &)),
            m_reply, SLOT(ignoreSslErrors()));
    m_stall.start(kStallMs);
}

void EpisodeDownloader::onReadyRead()
{
    if (!m_reply || !m_file)
        return;
    // Drain only the currently-buffered bytes to disk; never accumulate the whole
    // body in RAM.
    m_file->write(m_reply->readAll());
    m_stall.start(kStallMs);    // reset the stall watchdog on progress
}

void EpisodeDownloader::onDownloadProgress(qint64 received, qint64 total)
{
    emit progress(received, total);
}

void EpisodeDownloader::onReplyFinished()
{
    m_stall.stop();
    if (!m_reply)
        return;

    QNetworkReply *reply = m_reply;
    m_reply = 0;

    if (m_file && reply->error() == QNetworkReply::NoError)
        m_file->write(reply->readAll());    // flush any trailing bytes

    const QNetworkReply::NetworkError netErr = reply->error();
    const QString netErrStr = reply->errorString();
    const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const QVariant redirect = reply->attribute(QNetworkRequest::RedirectionTargetAttribute);
    const QUrl baseUrl = reply->url();
    reply->deleteLater();

    // Qt 4.7 does not auto-follow redirects; CDNs frequently 3xx. Re-issue manually.
    if (redirect.isValid()) {
        if (++m_redirects > kMaxRedirects) {
            failWith(QString::fromLatin1("Too many redirects."));
            return;
        }
        const QUrl next = baseUrl.resolved(redirect.toUrl());
        if (m_file) {           // discard the redirect body, reuse the open file
            m_file->seek(0);
            m_file->resize(0);
        }
        qDebug() << "EpisodeDownloader: redirect ->" << next.toString();
        startGet(next);
        return;
    }

    if (netErr != QNetworkReply::NoError) {
        failWith(netErrStr.isEmpty() ? QString::fromLatin1("Download failed.") : netErrStr);
        return;
    }
    if (status >= 400) {
        failWith(QString::fromLatin1("Server returned HTTP %1").arg(status));
        return;
    }

    // Success: finalize <eid>.part -> <eid>.<ext>.
    if (m_file) {
        m_file->flush();
        m_file->close();
        delete m_file;
        m_file = 0;
    }
    if (QFile::exists(m_finalPath))
        QFile::remove(m_finalPath);
    if (!QFile::rename(m_partPath, m_finalPath)) {
        failWith(QString::fromLatin1("Could not finalize download file."));
        return;
    }
    qDebug() << "EpisodeDownloader: finished" << m_finalPath;
    emit finished(m_finalPath);
}

void EpisodeDownloader::onStallTimeout()
{
    failWith(QString::fromLatin1("Download stalled (no data)."));
}

void EpisodeDownloader::cancel()
{
    cleanupReply();
    closeAndRemovePart();
}

void EpisodeDownloader::cleanupReply()
{
    m_stall.stop();
    if (m_reply) {
        disconnect(m_reply, 0, this, 0);
        m_reply->abort();
        m_reply->deleteLater();
        m_reply = 0;
    }
}

void EpisodeDownloader::closeAndRemovePart()
{
    if (m_file) {
        m_file->close();
        delete m_file;
        m_file = 0;
    }
    if (!m_partPath.isEmpty())
        QFile::remove(m_partPath);
}

void EpisodeDownloader::failWith(const QString &error)
{
    cleanupReply();
    closeAndRemovePart();
    emit failed(error);
}

// Resolve a writable, PUBLIC download directory by an actual write test. Media must
// NOT go in the app's /private/<uid> data cage (where DataLocation points on
// Symbian): the MMF server is a separate process that can't read the cage, so caged
// files play silently with duration 0. Prefer the memory card, then public phone
// storage. (See docs/DEVICE_NOTES.md 2026-06-14.)
QString EpisodeDownloader::audioDir()
{
    if (!m_audioDir.isEmpty())
        return m_audioDir;

    QStringList bases;
    bases << QLatin1String(AppConfig::kMemoryCardBase);   // E:/Xyz      (public)
    bases << QLatin1String(AppConfig::kPhoneBase);         // C:/Data/Xyz (public)
#ifndef Q_OS_SYMBIAN
    // Desktop/simulator has no cross-process cage restriction; fall back to the
    // standard data location if the public paths above aren't writable here.
    const QString dataLoc = QDesktopServices::storageLocation(QDesktopServices::DataLocation);
    if (!dataLoc.isEmpty())
        bases << dataLoc;
#endif

    QStringList candidates;
    for (int i = 0; i < bases.size(); ++i)
        candidates << QDir(bases.at(i)).filePath(QLatin1String("audio"));
    for (int i = 0; i < bases.size(); ++i)
        candidates << bases.at(i);

    for (int i = 0; i < candidates.size(); ++i) {
        if (tryMakeWritable(candidates.at(i))) {
            m_audioDir = candidates.at(i);
            qDebug() << "EpisodeDownloader: audio dir =" << m_audioDir;
            return m_audioDir;
        }
    }
    qWarning() << "EpisodeDownloader: no writable download dir found";
    return QString();
}

bool EpisodeDownloader::tryMakeWritable(const QString &dir)
{
    QDir d(dir);
    const bool isPrivate = dir.contains(QLatin1String("/private/"), Qt::CaseInsensitive);
    if (!isPrivate) {
        if (!d.exists() && !d.mkpath(QLatin1String(".")))
            return false;
    } else {
        d.mkpath(QLatin1String("."));       // best effort; caged dirs may refuse
    }

    // Data-caged paths lie about exists()/mkpath(); the only reliable check is an
    // actual write.
    QFile probe(d.filePath(QLatin1String(".wtest")));
    if (!probe.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return false;
    const bool ok = probe.write("x", 1) == 1;
    probe.close();
    probe.remove();
    return ok;
}

QString EpisodeDownloader::extensionForUrl(const QUrl &url)
{
    const QString suffix = QFileInfo(url.path()).suffix().toLower();
    if (suffix == QLatin1String("mp3") || suffix == QLatin1String("m4a")
        || suffix == QLatin1String("aac") || suffix == QLatin1String("wav")
        || suffix == QLatin1String("ogg") || suffix == QLatin1String("mp4"))
        return QLatin1Char('.') + suffix;
    return QLatin1String(".m4a");           // Xiaoyuzhou typically serves m4a
}
