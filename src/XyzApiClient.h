#ifndef XYZAPICLIENT_H
#define XYZAPICLIENT_H

#include <QtCore/QObject>
#include <QtCore/QString>
#include <QtCore/QTimer>
#include <QtCore/QVariantList>
#include <QtCore/QVariantMap>
#include <QtNetwork/QNetworkAccessManager>
#include <QtNetwork/QNetworkReply>
#include <QtNetwork/QSslError>

class StorageManager;

// Native content client for api.xiaoyuzhoufm.com (mirrors AuthClient's shape).
// Exposed to QML as the `xyzApi` context property.
class XyzApiClient : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY errorMessageChanged)
    Q_PROPERTY(QVariantList inboxItems READ inboxItems NOTIFY inboxLoaded)
    Q_PROPERTY(QVariantList subscriptions READ subscriptions NOTIFY subscriptionsLoaded)
    Q_PROPERTY(QVariantMap episode READ episode NOTIFY episodeLoaded)
    Q_PROPERTY(QVariantList comments READ comments NOTIFY commentsLoaded)
    Q_PROPERTY(int commentsTotal READ commentsTotal NOTIFY commentsLoaded)
    Q_PROPERTY(bool hasMoreComments READ hasMoreComments NOTIFY commentsLoaded)
    Q_PROPERTY(QVariantList discoverySections READ discoverySections NOTIFY discoveryLoaded)

public:
    explicit XyzApiClient(StorageManager *storage, QObject *parent = 0);

    bool busy() const;
    QString errorMessage() const;
    QVariantList inboxItems() const;
    QVariantList subscriptions() const;
    QVariantMap episode() const;
    QVariantList comments() const;
    int commentsTotal() const;
    bool hasMoreComments() const;
    QVariantList discoverySections() const;

    Q_INVOKABLE void fetchInbox();
    Q_INVOKABLE void fetchSubscriptions();
    Q_INVOKABLE void fetchEpisode(const QString &eid);
    Q_INVOKABLE void fetchComments(const QString &eid);
    // Append the next page using the loadMoreKey returned by the last comments fetch.
    Q_INVOKABLE void loadMoreComments();
    Q_INVOKABLE void fetchDiscovery();

signals:
    void busyChanged();
    void errorMessageChanged();
    void inboxLoaded();
    void subscriptionsLoaded();
    void episodeLoaded();
    void commentsLoaded();
    void discoveryLoaded();
    void sessionExpired();

private slots:
    void onReplyFinished();
    void onTimeout();
    void onSslErrors(const QList<QSslError> &errors);

private:
    enum RequestType { NoneRequest, InboxRequest, SubscriptionsRequest,
                       EpisodeRequest, CommentsRequest, MoreCommentsRequest,
                       DiscoveryDefault, DiscoveryTopic, DiscoveryHot };

    void startPost(RequestType type, const QString &path, const QVariantMap &body);
    void startGet(RequestType type, const QString &path);
    void abortActiveRequest();
    void applyContentHeaders(QNetworkRequest &request);
    void setBusy(bool busy);
    void setErrorMessage(const QString &message);

    QVariantMap shapeInboxItem(const QVariantMap &item) const;
    QVariantMap shapeSubscription(const QVariantMap &item) const;
    QVariantMap shapeEpisode(const QVariantMap &item) const;
    QVariantMap shapeComment(const QVariantMap &item) const;
    void startDiscoveryPhase(int phase);
    void finishDiscoveryPhase(const QVariantList &sections, bool ok);
    QVariantList shapeDiscoverySections(const QVariant &root) const;
    QVariantMap shapeDiscoveryEpisode(const QVariantMap &episode) const;
    QString pickImageUrl(const QVariantMap &image) const;
    QString relativeTime(const QString &iso) const;

    StorageManager *m_storage;
    QNetworkAccessManager *m_nam;
    QNetworkReply *m_reply;
    QTimer m_timeout;
    bool m_busy;
    QString m_errorMessage;
    RequestType m_requestType;
    QVariantList m_inboxItems;
    QVariantList m_subscriptions;
    QVariantMap m_episode;
    QVariantList m_comments;
    // Comment pagination: eid of the current thread, the opaque loadMoreKey to
    // echo back for the next page (empty when there are no more), and the total.
    QString m_commentsEid;
    QVariantMap m_commentsLoadMoreKey;
    int m_commentsTotal;
    QVariantList m_discoverySections;
    QVariantList m_discBuckets[3];
    int m_discPhase;
    bool m_discAnyOk;
};

#endif // XYZAPICLIENT_H
