#include "NowPlayingNotifier.h"
#include "PlayerController.h"

#ifdef Q_OS_SYMBIAN
#include <QtCore/QtGlobal>
#include <QtGui/QImage>
#include "QPiglerAPI.h"
#endif

NowPlayingNotifier::NowPlayingNotifier(PlayerController *player, QObject *parent)
    : QObject(parent)
    , m_player(player)
#ifdef Q_OS_SYMBIAN
    , m_api(0)
    , m_notifId(-1)
    , m_available(false)
    , m_iconSet(false)
#endif
{
}

NowPlayingNotifier::~NowPlayingNotifier()
{
#ifdef Q_OS_SYMBIAN
    if (m_api) {
        if (m_available && m_notifId >= 0)
            m_api->removeNotification(m_notifId);
        m_api->close();
        // m_api is parented to this and deleted by QObject.
    }
#endif
}

void NowPlayingNotifier::init()
{
#ifdef Q_OS_SYMBIAN
    m_api = new QPiglerAPI(this);
    const qint32 rc = m_api->init(QString::fromLatin1("Xiaoyuzhou"));
    if (rc < 0) {
        qWarning("Pigler init failed (%d); notifications disabled. "
                 "Install Pigler.sis from https://nnproject.cc/pna", rc);
        m_available = false;
        return;
    }
    m_available = true;

    connect(m_api, SIGNAL(handleTap(qint32)), this, SLOT(onTap(qint32)));

    // Reconcile whenever the current episode or playback state changes.
    connect(m_player, SIGNAL(currentEidChanged()),   this, SLOT(refresh()));
    connect(m_player, SIGNAL(currentTitleChanged()), this, SLOT(refresh()));
    connect(m_player, SIGNAL(currentShowChanged()),  this, SLOT(refresh()));
    connect(m_player, SIGNAL(stateChanged()),        this, SLOT(refresh()));

    refresh();   // seed from whatever is already loaded
#endif
}

void NowPlayingNotifier::refresh()
{
#ifdef Q_OS_SYMBIAN
    if (!m_available)
        return;

    const int state = m_player->state();
    const bool active = (state == m_player->playingState()
                         || state == m_player->pausedState());

    if (!active) {
        // Not in a playback session (idle/stopped/downloading/error) -> clear.
        if (m_notifId >= 0) {
            m_api->removeNotification(m_notifId);
            m_notifId = -1;
            m_iconSet = false;
        }
        return;
    }

    const QString title = m_player->currentTitle();
    const QString show  = m_player->currentShow();

    if (m_notifId < 0) {
        m_notifId = m_api->createNotification(title, show);
        if (m_notifId < 0) {   // creation failed; retry on the next change
            m_notifId = -1;
            return;
        }
        m_api->setLaunchAppOnTap(m_notifId, true);
        // A tap should foreground the app, NOT dismiss the notification: it is a
        // now-playing indicator that must persist until playback stops. Pigler's
        // server default is remove-on-tap, so override it explicitly.
        m_api->setRemoveOnTap(m_notifId, false);
        applyIcon();
    } else {
        m_api->updateNotification(m_notifId, title, show);
    }
#endif
}

#ifdef Q_OS_SYMBIAN
void NowPlayingNotifier::applyIcon()
{
    if (m_iconSet || m_notifId < 0)
        return;
    QImage icon(QString::fromLatin1(":/qml/gfx/notif-icon.png"));
    if (!icon.isNull()) {
        m_api->setNotificationIcon(m_notifId, icon);
        m_iconSet = true;
    }
}
#endif

void NowPlayingNotifier::onTap(qint32 /*notificationId*/)
{
    emit openCurrentEpisodeRequested();
}
