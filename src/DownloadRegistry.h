#ifndef DOWNLOADREGISTRY_H
#define DOWNLOADREGISTRY_H

#include <QtCore/QObject>
#include <QtCore/QString>
#include <QtCore/QVariantList>
#include <QtCore/QVariantMap>

class StorageManager;
class PlayerController;

// Source of truth for downloaded episodes and the phone-memory figures shown on the
// Downloads page. Persists per-episode metadata as a JSON array in StorageManager
// (key "downloads.index") and watches PlayerController to flip the in-flight entry to
// `done` once its file lands. Only one download runs at a time (the player's limit),
// so the single not-done entry is "the active download" -- its live progress is read
// straight off `player` in QML rather than mirrored here. Exposed to QML as `downloads`.
class DownloadRegistry : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList items READ items NOTIFY itemsChanged)
    Q_PROPERTY(int count READ count NOTIFY itemsChanged)
    Q_PROPERTY(QString downloadsText READ downloadsText NOTIFY itemsChanged)
    Q_PROPERTY(qint64 diskTotalBytes READ diskTotalBytes NOTIFY meterChanged)
    Q_PROPERTY(qint64 diskFreeBytes READ diskFreeBytes NOTIFY meterChanged)
    Q_PROPERTY(qint64 downloadsBytes READ downloadsBytes NOTIFY meterChanged)

public:
    explicit DownloadRegistry(StorageManager *storage, PlayerController *player,
                              QObject *parent = 0);

    QVariantList items() const { return m_items; }
    int count() const;                 // number of completed (on-device) episodes
    QString downloadsText() const;     // formatted sum of completed sizes ("248 MB")
    qint64 diskTotalBytes() const { return m_diskTotal; }
    qint64 diskFreeBytes() const { return m_diskFree; }
    qint64 downloadsBytes() const;

    // Record (or refresh) an episode as downloading -- called by EpisodePage at the
    // moment it asks the player to download. `meta` carries eid,title,show,
    // durationText,coverUrl,sizeText,audioUrl.
    Q_INVOKABLE void note(const QVariantMap &meta);
    Q_INVOKABLE void remove(const QString &eid);   // delete the file + drop the entry
    Q_INVOKABLE void clearAll();                    // delete every file + clear the list
    Q_INVOKABLE void refresh();                     // reconcile with disk + recompute meter

signals:
    void itemsChanged();
    void meterChanged();

private slots:
    void onPlayerStateChanged();
    void onDownloadDeleted();

private:
    void load();
    void save();
    int indexOf(const QString &eid) const;
    void recomputeMeter();
    static QString formatBytes(qint64 bytes);
    static void queryDisk(const QString &dir, qint64 &total, qint64 &free);

    StorageManager *m_storage;
    PlayerController *m_player;
    QVariantList m_items;    // each map: eid,title,show,durationText,coverUrl,
                             //           sizeText,sizeBytes,audioUrl,addedAt,done
    QString m_activeEid;     // the entry currently downloading (done==false), or ""
    qint64 m_diskTotal;
    qint64 m_diskFree;
};

#endif // DOWNLOADREGISTRY_H
