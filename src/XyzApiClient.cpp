#include "XyzApiClient.h"
#include "StorageManager.h"

#include <QtCore/QByteArray>
#include <QtCore/QDateTime>
#include <QtCore/QStringList>
#include <QtCore/QTextStream>
#include <QtCore/QUrl>
#include <QtCore/QVariant>
#include <QtNetwork/QNetworkRequest>
#include <QtNetwork/QSslSocket>

#include "parser.h"
#include "serializer.h"

namespace {

QString formatBytesShort(qint64 bytes) {
    if (bytes <= 0) return QString();
    const double mb = double(bytes) / (1024.0 * 1024.0);
    if (mb >= 1.0) return QString::fromLatin1("%1 MB").arg(mb, 0, 'f', 1);
    return QString::fromLatin1("%1 KB").arg(double(bytes) / 1024.0, 0, 'f', 0);
}

QByteArray contentBase()
{
    const QByteArray override = qgetenv("XYZ_API_BASE");
    if (!override.isEmpty()) {
        return override;
    }
    return QByteArray("https://api.xiaoyuzhoufm.com");
}

QString isoNow()
{
    return QDateTime::currentDateTime().toUTC().toString(Qt::ISODate) + QLatin1String("Z");
}

} // namespace

XyzApiClient::XyzApiClient(StorageManager *storage, QObject *parent)
    : QObject(parent)
    , m_storage(storage)
    , m_nam(new QNetworkAccessManager(this))
    , m_reply(0)
    , m_busy(false)
    , m_requestType(NoneRequest)
    , m_replayType(NoneRequest)
    , m_replayIsPost(false)
    , m_refreshAttempted(false)
    , m_commentsTotal(0)
    , m_discPageCount(0)
    , m_discAnyOk(false)
{
    m_timeout.setSingleShot(true);
    connect(&m_timeout, SIGNAL(timeout()), this, SLOT(onTimeout()));
}

bool XyzApiClient::busy() const { return m_busy; }
QString XyzApiClient::errorMessage() const { return m_errorMessage; }
QVariantList XyzApiClient::inboxItems() const { return m_inboxItems; }
QVariantList XyzApiClient::subscriptions() const { return m_subscriptions; }
QVariantMap XyzApiClient::episode() const { return m_episode; }
QVariantList XyzApiClient::comments() const { return m_comments; }
int XyzApiClient::commentsTotal() const { return m_commentsTotal; }
bool XyzApiClient::hasMoreComments() const { return !m_commentsLoadMoreKey.isEmpty(); }
QVariantList XyzApiClient::discoverySections() const { return m_discoverySections; }
QVariantList XyzApiClient::searchResults() const { return m_searchResults; }

void XyzApiClient::fetchInbox()
{
    QVariantMap body;
    body.insert(QString::fromLatin1("limit"), QString::fromLatin1("20"));
    startPost(InboxRequest, QString::fromLatin1("/v1/inbox/list"), body);
}

void XyzApiClient::fetchSubscriptions()
{
    QVariantMap body;
    body.insert(QString::fromLatin1("limit"), QString::fromLatin1("20"));
    body.insert(QString::fromLatin1("sortOrder"), QString::fromLatin1("desc"));
    body.insert(QString::fromLatin1("sortBy"), QString::fromLatin1("subscribedAt"));
    startPost(SubscriptionsRequest, QString::fromLatin1("/v1/subscription/list"), body);
}

// Episode detail is a GET with the eid as a query param (no body) — confirmed from
// the ultrazg/xyz Go source (handlers/episode.go).
void XyzApiClient::fetchEpisode(const QString &eid)
{
    if (eid.isEmpty()) {
        return;
    }
    startGet(EpisodeRequest,
             QString::fromLatin1("/v1/episode/get?eid=") + QString(QUrl::toPercentEncoding(eid)));
}

// Top comments (first page). The official body wraps the eid in an owner object —
// a flat {"id":...} is the proxy's facing shape, NOT what the real API expects.
void XyzApiClient::fetchComments(const QString &eid)
{
    if (eid.isEmpty()) {
        return;
    }
    // Reset pagination for the new thread so a previous episode's key can't leak.
    m_commentsEid = eid;
    m_commentsLoadMoreKey.clear();
    m_commentsTotal = 0;

    QVariantMap owner;
    owner.insert(QString::fromLatin1("id"), eid);
    owner.insert(QString::fromLatin1("type"), QString::fromLatin1("EPISODE"));
    QVariantMap body;
    body.insert(QString::fromLatin1("order"), QString::fromLatin1("HOT"));
    body.insert(QString::fromLatin1("owner"), owner);
    startPost(CommentsRequest, QString::fromLatin1("/v1/comment/list-primary"), body);
}

// Next page of the same thread. The API returns an opaque loadMoreKey object that
// we echo back verbatim to fetch the following page; results are appended.
void XyzApiClient::loadMoreComments()
{
    if (m_busy || m_commentsEid.isEmpty() || m_commentsLoadMoreKey.isEmpty()) {
        return;
    }
    QVariantMap owner;
    owner.insert(QString::fromLatin1("id"), m_commentsEid);
    owner.insert(QString::fromLatin1("type"), QString::fromLatin1("EPISODE"));
    QVariantMap body;
    body.insert(QString::fromLatin1("order"), QString::fromLatin1("HOT"));
    body.insert(QString::fromLatin1("owner"), owner);
    body.insert(QString::fromLatin1("loadMoreKey"), m_commentsLoadMoreKey);
    startPost(MoreCommentsRequest, QString::fromLatin1("/v1/comment/list-primary"), body);
}

// Discovery feed: a paginated walk. Start with no loadMoreKey, then follow the
// loadMoreKey each response returns (page 0 → topList → discoveryTopic → pick → end),
// accumulating EPISODE sections until the key is empty. Sequential (the client is
// single-reply); capped so a misbehaving cursor can't loop forever.
void XyzApiClient::fetchDiscovery()
{
    m_discoverySections.clear();
    m_discPageCount = 0;
    m_discAnyOk = false;
    startDiscoveryPage(QString());
}

void XyzApiClient::startDiscoveryPage(const QString &loadMoreKey)
{
    QVariantMap body;
    body.insert(QString::fromLatin1("returnAll"), QString::fromLatin1("false"));
    if (!loadMoreKey.isEmpty()) {
        body.insert(QString::fromLatin1("loadMoreKey"), loadMoreKey);
    }
    startPost(DiscoveryRequest, QString::fromLatin1("/v1/discovery-feed/list"), body);
}

// Episode search (first page only). Body mirrors the ultrazg/xyz proxy's Search
// handler (handlers/search.go): type=EPISODE plus the limit/sourcePageName/
// currentPageName the upstream /v1/search/create expects. loadMoreKey is omitted
// (no pagination); a previous search's results stay until this one replaces them.
void XyzApiClient::search(const QString &keyword)
{
    const QString kw = keyword.trimmed();
    if (kw.isEmpty()) {
        return;
    }
    QVariantMap body;
    body.insert(QString::fromLatin1("keyword"), kw);
    body.insert(QString::fromLatin1("type"), QString::fromLatin1("EPISODE"));
    body.insert(QString::fromLatin1("limit"), QString::fromLatin1("20"));
    body.insert(QString::fromLatin1("sourcePageName"), QString::fromLatin1("4"));
    body.insert(QString::fromLatin1("currentPageName"), QString::fromLatin1("4"));
    startPost(SearchRequest, QString::fromLatin1("/v1/search/create"), body);
}

// Accumulate this page's sections, then either fetch the next page (if the response
// gave a loadMoreKey and we're under the cap) or finalize + emit.
void XyzApiClient::finishDiscoveryPage(const QVariantList &sections, const QString &nextKey, bool ok)
{
    m_discoverySections += sections;
    if (ok) {
        m_discAnyOk = true;
    }
    ++m_discPageCount;
    if (ok && !nextKey.isEmpty() && m_discPageCount < 6) {
        startDiscoveryPage(nextKey);   // keeps busy == true across the walk
        return;
    }
    setBusy(false);
    if (!m_discAnyOk) {
        // The first page failed at the HTTP/parse level. Surface an error and do NOT
        // emit discoveryLoaded, so the page's loadedOnce stays false and a transient
        // failure retries on the next activation (mirrors fetchInbox on error).
        if (m_errorMessage.isEmpty()) {
            setErrorMessage(QString::fromLatin1("Couldn't load discovery."));
        }
        return;
    }
    emit discoveryLoaded();
}

void XyzApiClient::setBusy(bool busy)
{
    if (m_busy == busy) {
        return;
    }
    m_busy = busy;
    emit busyChanged();
}

void XyzApiClient::setErrorMessage(const QString &message)
{
    if (m_errorMessage == message) {
        return;
    }
    m_errorMessage = message;
    emit errorMessageChanged();
}

// iOS-app spoof headers the content host expects (from ultrazg/xyz handlers).
void XyzApiClient::applyContentHeaders(QNetworkRequest &request)
{
    request.setRawHeader("User-Agent", "Xiaoyuzhou/2.57.1 (build:1576; iOS 17.4.1)");
    request.setRawHeader("Market", "AppStore");
    request.setRawHeader("App-BuildNo", "1576");
    request.setRawHeader("OS", "ios");
    request.setRawHeader("Manufacturer", "Apple");
    request.setRawHeader("BundleID", "app.podcast.cosmos");
    request.setRawHeader("Model", "iPhone14,2");
    // Required for routing: the jike gateway returns {"code":1,"message":"rpc_error"}
    // (HTTP 400) without it. Fixed UUID, same as the ultrazg/xyz Go proxy.
    request.setRawHeader("x-jike-device-id", "81ADBFD6-6921-482B-9AB9-A29E7CC7BB55");
    request.setRawHeader("app-permissions", "4");
    request.setRawHeader("Accept", "*/*");
    request.setRawHeader("Content-Type", "application/json");
    request.setRawHeader("App-Version", "2.57.1");
    request.setRawHeader("OS-Version", "17.4.1");
    request.setRawHeader("Accept-Language", "zh-Hans-CN;q=1.0, zh-Hant-TW;q=0.9");
    request.setRawHeader("Timezone", "Asia/Shanghai");
    request.setRawHeader("Local-Time", isoNow().toLatin1());

    const QString token = m_storage
        ? m_storage->value(QLatin1String("auth.accessToken"))
        : QString();
    request.setRawHeader("x-jike-access-token", token.toUtf8());

    // The discovery feed and search both send the abtest opt-in header (per
    // ultrazg/xyz handlers/discovery.go + handlers/search.go); other content
    // endpoints work without it.
    if (m_requestType == DiscoveryRequest || m_requestType == SearchRequest) {
        request.setRawHeader("abtest-info", "{\"old_user_discovery_feed\":\"enable\"}");
    }
}

void XyzApiClient::sendRequest(RequestType type, bool isPost, const QString &path,
                               const QVariantMap &body, bool withRefreshHeader)
{
    abortActiveRequest();
    setErrorMessage(QString());
    setBusy(true);
    m_requestType = type;

    if (!QSslSocket::supportsSsl()) {
        setErrorMessage(QString::fromLatin1("SSL not supported at runtime."));
        setBusy(false);
        m_requestType = NoneRequest;
        return;
    }

    const QUrl url(QString::fromLatin1(contentBase()) + path);
    QNetworkRequest request(url);
    applyContentHeaders(request);

    // The refresh endpoint authenticates with BOTH tokens in headers.
    if (withRefreshHeader) {
        const QString refresh = m_storage
            ? m_storage->value(QLatin1String("auth.refreshToken"))
            : QString();
        request.setRawHeader("x-jike-refresh-token", refresh.toUtf8());
    }

    if (isPost) {
        // An empty body map posts a genuinely empty payload (the refresh endpoint
        // expects no body); non-empty maps serialize as before.
        QByteArray payload;
        if (!body.isEmpty()) {
            QJson::Serializer serializer;
            payload = serializer.serialize(body);
        }
        m_reply = m_nam->post(request, payload);
    } else {
        m_reply = m_nam->get(request);
    }
    connect(m_reply, SIGNAL(finished()), this, SLOT(onReplyFinished()));
    connect(m_reply, SIGNAL(sslErrors(const QList<QSslError> &)),
            this, SLOT(onSslErrors(const QList<QSslError> &)));
    m_timeout.start(15000);
}

void XyzApiClient::startPost(RequestType type, const QString &path, const QVariantMap &body)
{
    m_refreshAttempted = false;
    m_replayType = type;
    m_replayPath = path;
    m_replayBody = body;
    m_replayIsPost = true;
    sendRequest(type, true, path, body);
}

void XyzApiClient::startGet(RequestType type, const QString &path)
{
    m_refreshAttempted = false;
    m_replayType = type;
    m_replayPath = path;
    m_replayBody = QVariantMap();
    m_replayIsPost = false;
    sendRequest(type, false, path, QVariantMap());
}

// Refresh uses the content host + content headers, with both tokens in headers
// and an empty body. Does NOT touch replay state or m_refreshAttempted.
void XyzApiClient::startRefresh()
{
    sendRequest(RefreshRequest, true,
                QString::fromLatin1("/app_auth_tokens.refresh"),
                QVariantMap(), /*withRefreshHeader=*/true);
}

// Re-issue the request that hit 401, now that storage holds a fresh access
// token. m_refreshAttempted stays true so a second 401 ends in sessionExpired.
void XyzApiClient::resendReplay()
{
    sendRequest(m_replayType, m_replayIsPost, m_replayPath, m_replayBody);
}

void XyzApiClient::abortActiveRequest()
{
    if (!m_reply) {
        return;
    }
    disconnect(m_reply, 0, this, 0);
    m_reply->abort();
    m_reply->deleteLater();
    m_reply = 0;
    m_timeout.stop();
}

void XyzApiClient::onReplyFinished()
{
    m_timeout.stop();

    if (!m_reply) {
        setBusy(false);
        return;
    }

    QNetworkReply *reply = m_reply;
    m_reply = 0;
    const RequestType type = m_requestType;
    m_requestType = NoneRequest;
    const bool isDiscovery = (type == DiscoveryRequest);

    const QByteArray payload = reply->readAll();
    const int statusCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    // Captured for the refresh response's header fallback (see parseRefreshTokens).
    const QByteArray hdrAccess = reply->rawHeader("x-jike-access-token");
    const QByteArray hdrRefresh = reply->rawHeader("x-jike-refresh-token");
    reply->deleteLater();

    // Outcome of a refresh attempt: on success store new tokens and replay the
    // original request; on any failure (bad status / no token / 401) log out.
    if (type == RefreshRequest) {
        if (statusCode >= 200 && statusCode < 300) {
            QString newAccess, newRefresh;
            parseRefreshTokens(payload, hdrAccess, hdrRefresh, newAccess, newRefresh);
            if (!newAccess.isEmpty()) {
                if (m_storage) {
                    m_storage->setValue(QLatin1String("auth.accessToken"), newAccess);
                    if (!newRefresh.isEmpty()) {
                        m_storage->setValue(QLatin1String("auth.refreshToken"), newRefresh);
                    }
                }
                resendReplay();          // stays busy; retries the original request
                return;
            }
        }
        m_refreshAttempted = false;
        setBusy(false);
        emit sessionExpired();
        return;
    }

    if (statusCode == 401) {
        // First 401 on a normal request: try a one-shot refresh, then replay it.
        const QString refreshToken = m_storage
            ? m_storage->value(QLatin1String("auth.refreshToken"))
            : QString();
        if (!m_refreshAttempted && !refreshToken.isEmpty()) {
            m_refreshAttempted = true;
            startRefresh();              // stays busy; replay state already saved
            return;
        }
        // Already refreshed once, or no refresh token available → give up.
        m_refreshAttempted = false;
        setBusy(false);
        emit sessionExpired();
        return;
    }

    if (statusCode < 200 || statusCode >= 300) {
        if (isDiscovery) { finishDiscoveryPage(QVariantList(), QString(), false); return; }
        QString detail;
        QJson::Parser parser;
        bool ok = false;
        const QVariant root = parser.parse(payload, &ok);
        if (ok) {
            const QVariantMap map = root.toMap();
            QStringList keys;
            keys << QString::fromLatin1("toast") << QString::fromLatin1("msg")
                 << QString::fromLatin1("message");
            for (int i = 0; i < keys.size(); ++i) {
                const QString v = map.value(keys.at(i)).toString();
                if (!v.isEmpty()) {
                    detail = v;
                    break;
                }
            }
        }
        if (detail.isEmpty()) {
            detail = (statusCode == 0)
                ? QString::fromLatin1("Network error")
                : QString::fromLatin1("Request failed (%1)").arg(statusCode);
        }
        setErrorMessage(detail);
        setBusy(false);
        return;
    }

    QJson::Parser parser;
    bool ok = false;
    const QVariant root = parser.parse(payload, &ok);
    if (!ok) {
        if (isDiscovery) { finishDiscoveryPage(QVariantList(), QString(), false); return; }
        setErrorMessage(QString::fromLatin1("Failed to parse response."));
        setBusy(false);
        return;
    }
    // Both inbox/list and subscription/list return the array directly under the
    // top-level "data" key ({"data":[...]}), alongside extras like userStats /
    // loadMoreKey. (The earlier double-nested data.data shape was a mock artifact.)
    const QVariantMap top = root.toMap();
    const QVariantList rawItems = top.value(QString::fromLatin1("data")).toList();

    if (type == InboxRequest) {
        QVariantList shaped;
        for (int i = 0; i < rawItems.size(); ++i) {
            shaped.append(shapeInboxItem(rawItems.at(i).toMap()));
        }
        m_inboxItems = shaped;
        setBusy(false);
        emit inboxLoaded();
        return;
    }

    if (type == SubscriptionsRequest) {
        QVariantList shaped;
        for (int i = 0; i < rawItems.size(); ++i) {
            shaped.append(shapeSubscription(rawItems.at(i).toMap()));
        }
        m_subscriptions = shaped;
        setBusy(false);
        emit subscriptionsLoaded();
        return;
    }

    if (type == EpisodeRequest) {
        // episode/get returns the episode object under "data" (a map, not a list);
        // fall back to the top level if the wrapper is ever absent.
        QVariantMap raw = top.value(QString::fromLatin1("data")).toMap();
        if (raw.isEmpty()) {
            raw = top;
        }
        m_episode = shapeEpisode(raw);
        setBusy(false);
        emit episodeLoaded();
        return;
    }

    if (type == CommentsRequest || type == MoreCommentsRequest) {
        QVariantList shaped;
        for (int i = 0; i < rawItems.size(); ++i) {
            shaped.append(shapeComment(rawItems.at(i).toMap()));
        }
        if (type == MoreCommentsRequest) {
            m_comments += shaped;          // append the next page
        } else {
            m_comments = shaped;           // first page replaces
        }
        // totalCount is echoed on every page; loadMoreKey is absent on the last
        // page, which leaves the map empty and flips hasMoreComments to false.
        if (top.contains(QString::fromLatin1("totalCount"))) {
            m_commentsTotal = top.value(QString::fromLatin1("totalCount")).toInt();
        }
        m_commentsLoadMoreKey = top.value(QString::fromLatin1("loadMoreKey")).toMap();
        setBusy(false);
        emit commentsLoaded();
        return;
    }

    if (type == SearchRequest) {
        m_searchResults = shapeSearchEpisodes(root);
        setBusy(false);
        emit searchLoaded();
        return;
    }

    if (isDiscovery) {
        const QString nextKey = top.value(QString::fromLatin1("loadMoreKey")).toString();
        finishDiscoveryPage(shapeDiscoverySections(root), nextKey, true);
        return;
    }

    setBusy(false);
}

void XyzApiClient::onTimeout()
{
    const RequestType type = m_requestType;
    abortActiveRequest();
    m_requestType = NoneRequest;
    // A refresh that times out cannot recover the session → log out, matching the
    // spec's "any refresh failure → sessionExpired" rule.
    if (type == RefreshRequest) {
        m_refreshAttempted = false;
        setBusy(false);
        emit sessionExpired();
        return;
    }
    setErrorMessage(QString::fromLatin1("Request timed out."));
    setBusy(false);
}

// New tokens arrive as response BODY keys (the ultrazg/xyz proxy reads
// /app_auth_tokens.refresh's body); some shapes wrap them under "data". Fall
// back to response headers, mirroring AuthClient's tolerant login parsing.
void XyzApiClient::parseRefreshTokens(const QByteArray &payload,
                                      const QByteArray &hdrAccess,
                                      const QByteArray &hdrRefresh,
                                      QString &outAccess, QString &outRefresh) const
{
    outAccess.clear();
    outRefresh.clear();

    QJson::Parser parser;
    bool ok = false;
    const QVariant root = parser.parse(payload, &ok);
    if (ok) {
        QVariantMap map = root.toMap();
        const QVariantMap data = map.value(QString::fromLatin1("data")).toMap();
        if (!data.isEmpty()) {
            map = data;
        }
        outAccess = map.value(QString::fromLatin1("x-jike-access-token")).toString();
        outRefresh = map.value(QString::fromLatin1("x-jike-refresh-token")).toString();
    }
    if (outAccess.isEmpty() && !hdrAccess.isEmpty()) {
        outAccess = QString::fromUtf8(hdrAccess);
    }
    if (outRefresh.isEmpty() && !hdrRefresh.isEmpty()) {
        outRefresh = QString::fromUtf8(hdrRefresh);
    }
}

void XyzApiClient::onSslErrors(const QList<QSslError> &errors)
{
    if (!m_reply) {
        return;
    }
    QStringList messages;
    for (int i = 0; i < errors.size(); ++i) {
        messages.append(errors.at(i).errorString());
    }
    QTextStream ts(stdout);
    ts << "XyzApiClient SSL errors: " << messages.join(QString::fromLatin1("; ")) << '\n';
    ts.flush();
    m_reply->ignoreSslErrors();
}

QString XyzApiClient::pickImageUrl(const QVariantMap &image) const
{
    if (image.isEmpty()) {
        return QString();
    }
    static const char *keys[] = { "thumbnailUrl", "smallPicUrl", "middlePicUrl", "picUrl" };
    for (int i = 0; i < 4; ++i) {
        const QString v = image.value(QString::fromLatin1(keys[i])).toString();
        if (!v.isEmpty()) {
            return v;
        }
    }
    return QString();
}

QString XyzApiClient::relativeTime(const QString &iso) const
{
    // pubDate looks like "2024-05-24T16:00:00.000Z"; take the first 19 chars
    // ("yyyy-MM-ddThh:mm:ss") which Qt 4.7 parses reliably as ISODate.
    if (iso.size() < 19) {
        return QString();
    }
    QDateTime t = QDateTime::fromString(iso.left(19), Qt::ISODate);
    if (!t.isValid()) {
        return QString();
    }
    t.setTimeSpec(Qt::UTC);
    const QDateTime now = QDateTime::currentDateTime().toUTC();
    const int secs = t.secsTo(now);
    if (secs < 60) {
        return QString::fromLatin1("just now");
    }
    if (secs < 3600) {
        return QString::fromLatin1("%1m ago").arg(secs / 60);
    }
    if (secs < 86400) {
        return QString::fromLatin1("%1h ago").arg(secs / 3600);
    }
    const int days = secs / 86400;
    if (days < 7) {
        return QString::fromLatin1("%1d ago").arg(days);
    }
    if (days < 35) {
        return QString::fromLatin1("%1w ago").arg(days / 7);
    }
    if (days < 365) {
        return QString::fromLatin1("%1mo ago").arg(days / 30);
    }
    return QString::fromLatin1("%1y ago").arg(days / 365);
}

QVariantMap XyzApiClient::shapeInboxItem(const QVariantMap &item) const
{
    QVariantMap out;

    // eid lets the Episode page fetch detail/comments for the tapped card.
    out.insert(QString::fromLatin1("eid"), item.value(QString::fromLatin1("eid")).toString());

    QString cover = pickImageUrl(item.value(QString::fromLatin1("image")).toMap());
    if (cover.isEmpty()) {
        const QVariantMap podcast = item.value(QString::fromLatin1("podcast")).toMap();
        cover = pickImageUrl(podcast.value(QString::fromLatin1("image")).toMap());
    }
    out.insert(QString::fromLatin1("coverUrl"), cover);
    out.insert(QString::fromLatin1("title"), item.value(QString::fromLatin1("title")).toString());
    out.insert(QString::fromLatin1("desc"), item.value(QString::fromLatin1("description")).toString());

    const int durationSec = item.value(QString::fromLatin1("duration")).toInt();
    out.insert(QString::fromLatin1("durationText"),
               QString::fromLatin1("%1 min").arg((durationSec + 30) / 60));

    out.insert(QString::fromLatin1("whenText"),
               relativeTime(item.value(QString::fromLatin1("pubDate")).toString()));
    out.insert(QString::fromLatin1("playCount"),
               QString::number(item.value(QString::fromLatin1("playCount")).toInt()));

    const int comments = item.value(QString::fromLatin1("commentCount")).toInt();
    out.insert(QString::fromLatin1("commentCount"),
               comments > 99 ? QString::fromLatin1("99+") : QString::number(comments));

    return out;
}

QVariantMap XyzApiClient::shapeSubscription(const QVariantMap &item) const
{
    QVariantMap out;
    out.insert(QString::fromLatin1("coverUrl"),
               pickImageUrl(item.value(QString::fromLatin1("image")).toMap()));
    out.insert(QString::fromLatin1("name"), item.value(QString::fromLatin1("title")).toString());

    const QVariantList podcasters = item.value(QString::fromLatin1("podcasters")).toList();
    QStringList names;
    QVariantList avatars;
    for (int i = 0; i < podcasters.size() && i < 2; ++i) {
        const QVariantMap p = podcasters.at(i).toMap();
        const QString nick = p.value(QString::fromLatin1("nickname")).toString();
        if (!nick.isEmpty()) {
            names.append(nick);
        }
        const QVariantMap picture = p.value(QString::fromLatin1("avatar")).toMap()
                                     .value(QString::fromLatin1("picture")).toMap();
        const QString a = pickImageUrl(picture);
        if (!a.isEmpty()) {
            avatars.append(a);
        }
    }
    out.insert(QString::fromLatin1("hostsText"), names.join(QString::fromLatin1(", ")));
    out.insert(QString::fromLatin1("avatarUrls"), avatars);
    out.insert(QString::fromLatin1("whenText"),
               relativeTime(item.value(QString::fromLatin1("latestEpisodePubDate")).toString()));
    out.insert(QString::fromLatin1("often"),
               item.value(QString::fromLatin1("subscriptionOftenPlayed")).toBool());
    return out;
}

QVariantMap XyzApiClient::shapeEpisode(const QVariantMap &item) const
{
    QVariantMap out;

    QString cover = pickImageUrl(item.value(QString::fromLatin1("image")).toMap());
    const QVariantMap podcast = item.value(QString::fromLatin1("podcast")).toMap();
    if (cover.isEmpty()) {
        cover = pickImageUrl(podcast.value(QString::fromLatin1("image")).toMap());
    }
    out.insert(QString::fromLatin1("coverUrl"), cover);
    out.insert(QString::fromLatin1("title"), item.value(QString::fromLatin1("title")).toString());
    // No episode-number field exists in the API — the show line is just the podcast title.
    out.insert(QString::fromLatin1("showTitle"), podcast.value(QString::fromLatin1("title")).toString());
    // Plain-text show notes (the API also has an HTML "shownotes" field — deferred).
    out.insert(QString::fromLatin1("notes"), item.value(QString::fromLatin1("description")).toString());

    const int durationSec = item.value(QString::fromLatin1("duration")).toInt();
    out.insert(QString::fromLatin1("durationText"),
               QString::fromLatin1("%1 min").arg((durationSec + 30) / 60));
    out.insert(QString::fromLatin1("whenText"),
               relativeTime(item.value(QString::fromLatin1("pubDate")).toString()));
    out.insert(QString::fromLatin1("commentCount"),
               QString::number(item.value(QString::fromLatin1("commentCount")).toInt()));

    // Audio enclosure URL (+ reliable byte size from media) for the download/play CTA.
    const QVariantMap media = item.value(QString::fromLatin1("media")).toMap();
    QString audioUrl = item.value(QString::fromLatin1("enclosure")).toMap()
                           .value(QString::fromLatin1("url")).toString();
    if (audioUrl.isEmpty())
        audioUrl = media.value(QString::fromLatin1("source")).toMap()
                       .value(QString::fromLatin1("url")).toString();
    out.insert(QString::fromLatin1("audioUrl"), audioUrl);
    out.insert(QString::fromLatin1("audioSizeText"),
               formatBytesShort(media.value(QString::fromLatin1("size")).toLongLong()));

    return out;
}

QVariantMap XyzApiClient::shapeComment(const QVariantMap &item) const
{
    QVariantMap out;

    const QVariantMap author = item.value(QString::fromLatin1("author")).toMap();
    out.insert(QString::fromLatin1("name"), author.value(QString::fromLatin1("nickname")).toString());

    const QVariantMap picture = author.value(QString::fromLatin1("avatar")).toMap()
                                 .value(QString::fromLatin1("picture")).toMap();
    out.insert(QString::fromLatin1("avatarUrl"), pickImageUrl(picture));

    // ipLoc (e.g. "上海") sits on the comment and is mirrored inside author; prefer the
    // comment-level one, fall back to the author's.
    QString loc = item.value(QString::fromLatin1("ipLoc")).toString();
    if (loc.isEmpty()) {
        loc = author.value(QString::fromLatin1("ipLoc")).toString();
    }
    out.insert(QString::fromLatin1("loc"), loc);

    out.insert(QString::fromLatin1("text"), item.value(QString::fromLatin1("text")).toString());
    out.insert(QString::fromLatin1("likes"),
               QString::number(item.value(QString::fromLatin1("likeCount")).toInt()));

    return out;
}

// Pull the episode from each wrapper (under episodeKey) and append a {title, subtitle,
// items} section. The wrapper key differs by feed type: "episode" for target/picks rows,
// "item" for top-list rows. Skips a section with no shaped episodes.
void XyzApiClient::appendEpisodeSection(QVariantList &sections, const QString &title,
                                        const QString &subtitle, const QVariantList &targets,
                                        const QString &episodeKey) const
{
    QVariantList items;
    for (int k = 0; k < targets.size(); ++k) {
        const QVariantMap episode = targets.at(k).toMap().value(episodeKey).toMap();
        if (!episode.isEmpty()) {
            items.append(shapeDiscoveryEpisode(episode));
        }
    }
    if (items.isEmpty()) {
        return;
    }
    QVariantMap section;
    section.insert(QString::fromLatin1("title"), title);
    section.insert(QString::fromLatin1("subtitle"), subtitle);
    section.insert(QString::fromLatin1("items"), items);
    sections.append(section);
}

// The real upstream returns feed entries directly under the top-level "data" key
// ({"data":[...],"loadMoreKey":...}), like inbox/subscription -- NOT data.data[] (the
// proxy DOC's extra "data" is a ReturnJson artifact; we fall back to it just in case).
// Each entry is {type, data}; the EPISODE-bearing types and where the episodes live
// (confirmed against the live feed, 2026-06-26):
//   DISCOVERY_EPISODE_RECOMMEND  data{title, targetType, target[].episode}
//   EDITOR_PICK                  data{picks[].episode}   (no title -> hardcoded label)
//   TOP_LIST                     data[]{title, items[].item}   (hot / rising / new-star)
//   DISCOVERY_COLLECTION         data[]{title, targetType, target[].episode}
// Everything else (headers, pictorials, PODCAST modules, NEW_POWER, banners...) is skipped.
QVariantList XyzApiClient::shapeDiscoverySections(const QVariant &root) const
{
    static const QString kEpisode = QString::fromLatin1("EPISODE");
    QVariantList sections;
    const QVariantMap top = root.toMap();
    const QVariant dataNode = top.value(QString::fromLatin1("data"));
    QVariantList entries = dataNode.toList();
    if (entries.isEmpty()) {
        entries = dataNode.toMap().value(QString::fromLatin1("data")).toList();
    }
    for (int i = 0; i < entries.size(); ++i) {
        const QVariantMap entry = entries.at(i).toMap();
        const QString type = entry.value(QString::fromLatin1("type")).toString();
        const QVariant data = entry.value(QString::fromLatin1("data"));

        if (type == QString::fromLatin1("DISCOVERY_EPISODE_RECOMMEND")) {
            const QVariantMap m = data.toMap();
            if (m.value(QString::fromLatin1("targetType")).toString() == kEpisode) {
                appendEpisodeSection(sections, m.value(QString::fromLatin1("title")).toString(),
                                     QString(), m.value(QString::fromLatin1("target")).toList(),
                                     QString::fromLatin1("episode"));
            }
        } else if (type == QString::fromLatin1("EDITOR_PICK")) {
            // No title field on this entry -- label it "编辑精选" (UTF-8 escaped).
            const QVariantMap m = data.toMap();
            appendEpisodeSection(sections,
                                 QString::fromUtf8("\xE7\xBC\x96\xE8\xBE\x91\xE7\xB2\xBE\xE9\x80\x89"),
                                 QString(), m.value(QString::fromLatin1("picks")).toList(),
                                 QString::fromLatin1("episode"));
        } else if (type == QString::fromLatin1("TOP_LIST")) {
            // Hidden per user preference: the new-star board "新星榜" (UTF-8 escaped).
            static const QString kHiddenBoard =
                QString::fromUtf8("\xE6\x96\xB0\xE6\x98\x9F\xE6\xA6\x9C");
            const QVariantList boards = data.toList();
            for (int b = 0; b < boards.size(); ++b) {
                const QVariantMap board = boards.at(b).toMap();
                const QString boardTitle = board.value(QString::fromLatin1("title")).toString();
                if (boardTitle == kHiddenBoard) {
                    continue;
                }
                if (board.value(QString::fromLatin1("targetType")).toString() == kEpisode) {
                    appendEpisodeSection(sections, boardTitle, QString(),
                                         board.value(QString::fromLatin1("items")).toList(),
                                         QString::fromLatin1("item"));
                }
            }
        } else if (type == QString::fromLatin1("DISCOVERY_COLLECTION")) {
            const QVariantList modules = data.toList();
            for (int j = 0; j < modules.size(); ++j) {
                const QVariantMap mod = modules.at(j).toMap();
                if (mod.value(QString::fromLatin1("targetType")).toString() == kEpisode) {
                    appendEpisodeSection(sections, mod.value(QString::fromLatin1("title")).toString(),
                                         mod.value(QString::fromLatin1("description")).toString(),
                                         mod.value(QString::fromLatin1("target")).toList(),
                                         QString::fromLatin1("episode"));
                }
            }
        }
    }
    return sections;
}

// One episode → the card/tap map. Superset of EpisodePage.openWith's seed; showName
// and commentCount drive the card foot.
QVariantMap XyzApiClient::shapeDiscoveryEpisode(const QVariantMap &episode) const
{
    QVariantMap out;
    out.insert(QString::fromLatin1("eid"), episode.value(QString::fromLatin1("eid")).toString());

    QString cover = pickImageUrl(episode.value(QString::fromLatin1("image")).toMap());
    const QVariantMap podcast = episode.value(QString::fromLatin1("podcast")).toMap();
    if (cover.isEmpty()) {
        cover = pickImageUrl(podcast.value(QString::fromLatin1("image")).toMap());
    }
    out.insert(QString::fromLatin1("coverUrl"), cover);
    out.insert(QString::fromLatin1("title"), episode.value(QString::fromLatin1("title")).toString());
    out.insert(QString::fromLatin1("showName"), podcast.value(QString::fromLatin1("title")).toString());

    const int durationSec = episode.value(QString::fromLatin1("duration")).toInt();
    out.insert(QString::fromLatin1("durationText"),
               QString::fromLatin1("%1 min").arg((durationSec + 30) / 60));
    out.insert(QString::fromLatin1("whenText"),
               relativeTime(episode.value(QString::fromLatin1("pubDate")).toString()));

    const int comments = episode.value(QString::fromLatin1("commentCount")).toInt();
    out.insert(QString::fromLatin1("commentCount"),
               comments > 99 ? QString::fromLatin1("99+") : QString::number(comments));
    return out;
}

// Search returns a mixed feed (HEADER / PODCAST / EPISODE / FOOTER /
// SEARCHED_USERS) under the top-level "data" array (same envelope as discovery /
// inbox; we keep the data.data fallback in case the upstream ever double-wraps).
// We keep only EPISODE entries; unlike the discovery feed, a search EPISODE entry
// carries the episode fields at its own top level (type + eid + title + podcast{})
// rather than under a target[].episode wrapper, so shape each entry directly.
QVariantList XyzApiClient::shapeSearchEpisodes(const QVariant &root) const
{
    static const QString kEpisode = QString::fromLatin1("EPISODE");
    QVariantList out;
    const QVariantMap top = root.toMap();
    const QVariant dataNode = top.value(QString::fromLatin1("data"));
    QVariantList entries = dataNode.toList();
    if (entries.isEmpty()) {
        entries = dataNode.toMap().value(QString::fromLatin1("data")).toList();
    }
    for (int i = 0; i < entries.size(); ++i) {
        const QVariantMap entry = entries.at(i).toMap();
        if (entry.value(QString::fromLatin1("type")).toString() == kEpisode) {
            out.append(shapeDiscoveryEpisode(entry));
        }
    }
    return out;
}
