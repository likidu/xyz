#ifndef NOWPLAYINGNOTIFIER_H
#define NOWPLAYINGNOTIFIER_H

#include <QtCore/QObject>
#include <QtCore/QString>

class PlayerController;
#ifdef Q_OS_SYMBIAN
class QPiglerAPI;
#endif

// Mirrors the current episode into a single Pigler status-panel notification
// (Symbian only). Off Symbian every method is a no-op so the app builds and
// runs unchanged. Owns its QPiglerAPI; reads the episode straight from
// PlayerController, so callers pass no data.
class NowPlayingNotifier : public QObject
{
    Q_OBJECT

public:
    explicit NowPlayingNotifier(PlayerController *player, QObject *parent = 0);
    ~NowPlayingNotifier();

    // Connect to the Pigler server and start observing the player. Call once,
    // after the main window is shown/foreground (mirrors VolumeKeyCapturer).
    void init();

signals:
    // Emitted when the user taps the notification; AppWindow opens the
    // current episode's detail page.
    void openCurrentEpisodeRequested();

private slots:
    void refresh();   // reconcile the notification with current player state
    void onTap(qint32 notificationId);

private:
    PlayerController *m_player;
#ifdef Q_OS_SYMBIAN
    void applyIcon();
    QPiglerAPI *m_api;
    int  m_notifId;    // -1 = no notification shown
    bool m_available;  // false if the Pigler server is absent / init failed
    bool m_iconSet;    // placeholder icon applied once
#endif
};

#endif // NOWPLAYINGNOTIFIER_H
