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
    // Filled in Task 4 (Symbian). No-op off Symbian.
}

void NowPlayingNotifier::refresh()
{
    // Filled in Task 4 (Symbian). No-op off Symbian.
}

#ifdef Q_OS_SYMBIAN
void NowPlayingNotifier::applyIcon()
{
}

void NowPlayingNotifier::onTap(qint32 /*notificationId*/)
{
    emit openCurrentEpisodeRequested();
}
#endif
