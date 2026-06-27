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
    Q_PROPERTY(QVariantMap podcast READ podcast NOTIFY podcastLoaded)
    Q_PROPERTY(QVariantList podcastEpisodes READ podcastEpisodes NOTIFY podcastEpisodesLoaded)
    Q_PROPERTY(bool hasMorePodcastEpisodes READ hasMorePodcastEpisodes NOTIFY podcastEpisodesLoaded)
    Q_PROPERTY(QVariantList comments READ comments NOTIFY commentsLoaded)
    Q_PROPERTY(int commentsTotal READ commentsTotal NOTIFY commentsLoaded)
    Q_PROPERTY(bool hasMoreComments READ hasMoreComments NOTIFY commentsLoaded)
    Q_PROPERTY(QVariantList discoverySections READ discoverySections NOTIFY discoveryLoaded)
    Q_PROPERTY(QVariantList searchResults READ searchResults NOTIFY searchLoaded)

public:
    explicit XyzApiClient(StorageManager *storage, QObject *parent = 0);

    bool busy() const;
    QString errorMessage() const;
    QVariantList inboxItems() const;
    QVariantList subscriptions() const;
    QVariantMap episode() const;
    QVariantMap podcast() const;
    QVariantList podcastEpisodes() const;
    bool hasMorePodcastEpisodes() const;
    QVariantList comments() const;
    int commentsTotal() const;
    bool hasMoreComments() const;
    QVariantList discoverySections() const;
    QVariantList searchResults() const;

    Q_INVOKABLE void fetchInbox();
    Q_INVOKABLE void fetchSubscriptions();
    Q_INVOKABLE void fetchEpisode(const QString &eid);
    Q_INVOKABLE void fetchPodcast(const QString &pid);
    Q_INVOKABLE void fetchPodcastEpisodes(const QString &pid);
    // Append the next page using the loadMoreKey from the last episode-list fetch.
    Q_INVOKABLE void loadMorePodcastEpisodes();
    Q_INVOKABLE void fetchComments(const QString &eid);
    // Append the next page using the loadMoreKey returned by the last comments fetch.
    Q_INVOKABLE void loadMoreComments();
    Q_INVOKABLE void fetchDiscovery();
    // Episode search (first page only, type=EPISODE). Empty keyword is a no-op.
    Q_INVOKABLE void search(const QString &keyword);

signals:
    void busyChanged();
    void errorMessageChanged();
    void inboxLoaded();
    void subscriptionsLoaded();
    void episodeLoaded();
    void podcastLoaded();
    void podcastEpisodesLoaded();
    void commentsLoaded();
    void discoveryLoaded();
    void searchLoaded();
    void sessionExpired();

private slots:
    void onReplyFinished();
    void onTimeout();
    void onSslErrors(const QList<QSslError> &errors);

private:
    enum RequestType { NoneRequest, InboxRequest, SubscriptionsRequest,
                       EpisodeRequest, CommentsRequest, MoreCommentsRequest,
                       DiscoveryRequest, SearchRequest, RefreshRequest, PodcastRequest,
                       PodcastEpisodesRequest, MorePodcastEpisodesRequest };

    void startPost(RequestType type, const QString &path, const QVariantMap &body);
    void startGet(RequestType type, const QString &path);
    // Shared issue-path for startPost/startGet/startRefresh/resendReplay.
    void sendRequest(RequestType type, bool isPost, const QString &path,
                     const QVariantMap &body, bool withRefreshHeader = false);
    // One-shot token refresh on 401, then re-send the request that failed.
    void startRefresh();
    void resendReplay();
    void parseRefreshTokens(const QByteArray &payload,
                            const QByteArray &hdrAccess, const QByteArray &hdrRefresh,
                            QString &outAccess, QString &outRefresh) const;
    void abortActiveRequest();
    void applyContentHeaders(QNetworkRequest &request);
    void setBusy(bool busy);
    void setErrorMessage(const QString &message);

    QVariantMap shapeInboxItem(const QVariantMap &item) const;
    QVariantMap shapeSubscription(const QVariantMap &item) const;
    QVariantMap shapeEpisode(const QVariantMap &item) const;
    QVariantMap shapePodcast(const QVariantMap &item) const;
    QVariantMap shapePodcastEpisode(const QVariantMap &item) const;
    QVariantMap shapeComment(const QVariantMap &item) const;
    void startDiscoveryPage(const QString &loadMoreKey);
    void finishDiscoveryPage(const QVariantList &sections, const QString &nextKey, bool ok);
    QVariantList shapeDiscoverySections(const QVariant &root) const;
    // Pull EPISODE entries out of a /v1/search/create response (mixed feed).
    QVariantList shapeSearchEpisodes(const QVariant &root) const;
    // Build a {title, subtitle, items} section from a list of target wrappers, pulling the
    // episode out of each wrapper under episodeKey ("episode" for target/picks, "item" for
    // top-list rows). Appends only if at least one episode shaped.
    void appendEpisodeSection(QVariantList &sections, const QString &title,
                              const QString &subtitle, const QVariantList &targets,
                              const QString &episodeKey) const;
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
    // Replay state: remember the in-flight request so it can be re-sent after a
    // refresh; m_refreshAttempted caps the refresh to once per logical request.
    RequestType m_replayType;
    QString m_replayPath;
    QVariantMap m_replayBody;
    bool m_replayIsPost;
    bool m_refreshAttempted;
    QVariantList m_inboxItems;
    QVariantList m_subscriptions;
    QVariantMap m_episode;
    QVariantMap m_podcast;
    QVariantList m_podcastEpisodes;
    // Episode-list pagination: the pid of the current show and the opaque loadMoreKey
    // to echo back for the next page (empty when there are no more).
    QString m_podcastEpisodesPid;
    QVariantMap m_podcastEpisodesKey;
    QVariantList m_comments;
    // Comment pagination: eid of the current thread, the opaque loadMoreKey to
    // echo back for the next page (empty when there are no more), and the total.
    QString m_commentsEid;
    QVariantMap m_commentsLoadMoreKey;
    int m_commentsTotal;
    QVariantList m_discoverySections;
    int m_discPageCount;   // pages walked this fetch (loadMoreKey pagination, capped)
    bool m_discAnyOk;
    QVariantList m_searchResults;
};

#endif // XYZAPICLIENT_H
