#include "DownloadRegistry.h"
#include "StorageManager.h"
#include "PlayerController.h"

#include <QtCore/QByteArray>
#include <QtCore/QDateTime>
#include <QtCore/QDebug>
#include <QtCore/QStringList>

#include "parser.h"       // vendored qjson (Qt 4 has no QJsonDocument)
#include "serializer.h"

#ifdef Q_OS_SYMBIAN
#include <f32file.h>
#endif
#ifdef Q_OS_WIN
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif

namespace {
const char *const kIndexKey = "downloads.index";
}

DownloadRegistry::DownloadRegistry(StorageManager *storage, PlayerController *player,
                                   QObject *parent)
    : QObject(parent)
    , m_storage(storage)
    , m_player(player)
    , m_diskTotal(0)
    , m_diskFree(0)
{
    load();
    if (m_player) {
        connect(m_player, SIGNAL(stateChanged()), this, SLOT(onPlayerStateChanged()));
        connect(m_player, SIGNAL(downloadDeleted()), this, SLOT(onDownloadDeleted()));
    }
    refresh();
}

int DownloadRegistry::count() const
{
    int n = 0;
    for (int i = 0; i < m_items.size(); ++i) {
        if (m_items.at(i).toMap().value(QLatin1String("done")).toBool())
            ++n;
    }
    return n;
}

qint64 DownloadRegistry::downloadsBytes() const
{
    qint64 total = 0;
    for (int i = 0; i < m_items.size(); ++i) {
        const QVariantMap e = m_items.at(i).toMap();
        if (e.value(QLatin1String("done")).toBool())
            total += e.value(QLatin1String("sizeBytes")).toLongLong();
    }
    return total;
}

QString DownloadRegistry::downloadsText() const
{
    return formatBytes(downloadsBytes());
}

int DownloadRegistry::indexOf(const QString &eid) const
{
    for (int i = 0; i < m_items.size(); ++i) {
        if (m_items.at(i).toMap().value(QLatin1String("eid")).toString() == eid)
            return i;
    }
    return -1;
}

void DownloadRegistry::note(const QVariantMap &meta)
{
    const QString eid = meta.value(QLatin1String("eid")).toString();
    if (eid.isEmpty())
        return;

    QVariantMap e;
    e[QLatin1String("eid")] = eid;
    e[QLatin1String("title")] = meta.value(QLatin1String("title"));
    e[QLatin1String("show")] = meta.value(QLatin1String("show"));
    e[QLatin1String("durationText")] = meta.value(QLatin1String("durationText"));
    e[QLatin1String("coverUrl")] = meta.value(QLatin1String("coverUrl"));
    e[QLatin1String("audioUrl")] = meta.value(QLatin1String("audioUrl"));
    e[QLatin1String("addedAt")] = QDateTime::currentDateTime().toString(Qt::ISODate);

    // If the file is already on disk and the player isn't mid-fetch for it, this is a
    // cache hit -- record it as done straight away (the player's finished() may have
    // fired synchronously, before this entry existed to observe stateChanged).
    const bool already = m_player && m_player->isDownloaded(eid)
                         && m_player->state() != m_player->downloadingState();
    if (already) {
        const qint64 bytes = m_player->downloadedSizeBytes(eid);
        e[QLatin1String("done")] = true;
        e[QLatin1String("sizeBytes")] = (qlonglong)bytes;
        e[QLatin1String("sizeText")] = formatBytes(bytes);
        if (m_activeEid == eid)
            m_activeEid.clear();
    } else {
        e[QLatin1String("done")] = false;
        e[QLatin1String("sizeBytes")] = (qlonglong)0;
        e[QLatin1String("sizeText")] = meta.value(QLatin1String("sizeText"));
        m_activeEid = eid;
    }

    const int idx = indexOf(eid);
    if (idx >= 0)
        m_items.removeAt(idx);
    m_items.prepend(e);   // most-recent first

    save();
    emit itemsChanged();
    if (already) {
        recomputeMeter();
    }
}

void DownloadRegistry::remove(const QString &eid)
{
    const int idx = indexOf(eid);
    if (idx >= 0)
        m_items.removeAt(idx);
    if (m_activeEid == eid)
        m_activeEid.clear();
    if (m_player)
        m_player->deleteDownload(eid);   // robust (MMF-lock aware) file removal
    save();
    emit itemsChanged();
    recomputeMeter();
}

void DownloadRegistry::clearAll()
{
    if (m_player) {
        for (int i = 0; i < m_items.size(); ++i) {
            const QString eid = m_items.at(i).toMap().value(QLatin1String("eid")).toString();
            if (!eid.isEmpty())
                m_player->deleteDownload(eid);
        }
    }
    m_items.clear();
    m_activeEid.clear();
    save();
    emit itemsChanged();
    recomputeMeter();
}

void DownloadRegistry::refresh()
{
    bool changed = false;
    QVariantList kept;
    for (int i = 0; i < m_items.size(); ++i) {
        QVariantMap e = m_items.at(i).toMap();
        const QString eid = e.value(QLatin1String("eid")).toString();
        const bool done = e.value(QLatin1String("done")).toBool();
        if (done) {
            if (m_player && !m_player->isDownloaded(eid)) {
                changed = true;            // file vanished -- drop it
                continue;
            }
            // refresh the on-disk size in case it changed since it was recorded
            if (m_player) {
                const qint64 bytes = m_player->downloadedSizeBytes(eid);
                if (e.value(QLatin1String("sizeBytes")).toLongLong() != bytes) {
                    e[QLatin1String("sizeBytes")] = (qlonglong)bytes;
                    e[QLatin1String("sizeText")] = formatBytes(bytes);
                    changed = true;
                }
            }
        }
        kept.append(e);
    }
    if (changed) {
        m_items = kept;
        save();
        emit itemsChanged();
    }
    recomputeMeter();
}

void DownloadRegistry::onPlayerStateChanged()
{
    if (m_activeEid.isEmpty() || !m_player)
        return;
    if (m_player->state() == m_player->downloadingState())
        return;   // still fetching

    const QString eid = m_activeEid;
    m_activeEid.clear();
    const int idx = indexOf(eid);
    if (idx < 0)
        return;

    if (m_player->isDownloaded(eid)) {
        QVariantMap e = m_items.at(idx).toMap();
        const qint64 bytes = m_player->downloadedSizeBytes(eid);
        e[QLatin1String("done")] = true;
        e[QLatin1String("sizeBytes")] = (qlonglong)bytes;
        e[QLatin1String("sizeText")] = formatBytes(bytes);
        m_items[idx] = e;
    } else {
        m_items.removeAt(idx);   // cancelled or failed -- never landed
    }
    save();
    emit itemsChanged();
    recomputeMeter();
}

void DownloadRegistry::onDownloadDeleted()
{
    refresh();
}

void DownloadRegistry::load()
{
    if (!m_storage)
        return;
    const QString raw = m_storage->value(QLatin1String(kIndexKey), QString());
    if (raw.isEmpty())
        return;
    QJson::Parser parser;
    bool ok = false;
    const QVariant root = parser.parse(raw.toUtf8(), &ok);
    if (ok)
        m_items = root.toList();
    else
        qWarning() << "DownloadRegistry: could not parse stored index";
}

void DownloadRegistry::save()
{
    if (!m_storage)
        return;
    QJson::Serializer serializer;
    const QByteArray json = serializer.serialize(m_items);
    m_storage->setValue(QLatin1String(kIndexKey), QString::fromUtf8(json));
}

void DownloadRegistry::recomputeMeter()
{
    qint64 total = 0;
    qint64 free = 0;
    queryDisk(m_player ? m_player->downloadStorageDir() : QString(), total, free);
    if (total != m_diskTotal || free != m_diskFree) {
        m_diskTotal = total;
        m_diskFree = free;
    }
    emit meterChanged();   // also covers downloadsBytes()/downloadsText changes
}

QString DownloadRegistry::formatBytes(qint64 bytes)
{
    if (bytes <= 0)
        return QString();
    const double mb = double(bytes) / (1024.0 * 1024.0);
    if (mb >= 1.0)
        return QString::fromLatin1("%1 MB").arg(mb, 0, 'f', 1);
    return QString::fromLatin1("%1 KB").arg(double(bytes) / 1024.0, 0, 'f', 0);
}

void DownloadRegistry::queryDisk(const QString &dir, qint64 &total, qint64 &free)
{
    total = 0;
    free = 0;
    if (dir.isEmpty())
        return;
#ifdef Q_OS_SYMBIAN
    RFs fs;
    if (fs.Connect() != KErrNone)
        return;
    TInt drive = EDriveC;
    if (dir.length() >= 2 && dir.at(1) == QLatin1Char(':')) {
        TInt parsed = EDriveC;
        if (RFs::CharToDrive(TChar(dir.at(0).toUpper().unicode()), parsed) == KErrNone)
            drive = parsed;
    }
    TVolumeInfo vol;
    if (fs.Volume(vol, drive) == KErrNone) {
        total = (qint64)vol.iSize;
        free = (qint64)vol.iFree;
    }
    fs.Close();
#elif defined(Q_OS_WIN)
    ULARGE_INTEGER ulFreeAvail, ulTotal, ulTotalFree;
    if (GetDiskFreeSpaceExW(reinterpret_cast<const wchar_t *>(dir.utf16()),
                            &ulFreeAvail, &ulTotal, &ulTotalFree)) {
        total = (qint64)ulTotal.QuadPart;
        free = (qint64)ulFreeAvail.QuadPart;
    }
#else
    Q_UNUSED(dir);
#endif
}
