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

// Top comments. The official body wraps the eid in an owner object — a flat
// {"id":...} is the proxy's facing shape, NOT what the real API expects.
void XyzApiClient::fetchComments(const QString &eid)
{
    if (eid.isEmpty()) {
        return;
    }
    QVariantMap owner;
    owner.insert(QString::fromLatin1("id"), eid);
    owner.insert(QString::fromLatin1("type"), QString::fromLatin1("EPISODE"));
    QVariantMap body;
    body.insert(QString::fromLatin1("order"), QString::fromLatin1("HOT"));
    body.insert(QString::fromLatin1("owner"), owner);
    startPost(CommentsRequest, QString::fromLatin1("/v1/comment/list-primary"), body);
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
}

void XyzApiClient::startPost(RequestType type, const QString &path, const QVariantMap &body)
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

    QJson::Serializer serializer;
    const QByteArray payload = serializer.serialize(body);

    m_reply = m_nam->post(request, payload);
    connect(m_reply, SIGNAL(finished()), this, SLOT(onReplyFinished()));
    connect(m_reply, SIGNAL(sslErrors(const QList<QSslError> &)),
            this, SLOT(onSslErrors(const QList<QSslError> &)));
    m_timeout.start(15000);
}

void XyzApiClient::startGet(RequestType type, const QString &path)
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

    m_reply = m_nam->get(request);
    connect(m_reply, SIGNAL(finished()), this, SLOT(onReplyFinished()));
    connect(m_reply, SIGNAL(sslErrors(const QList<QSslError> &)),
            this, SLOT(onSslErrors(const QList<QSslError> &)));
    m_timeout.start(15000);
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

    const QByteArray payload = reply->readAll();
    const int statusCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    reply->deleteLater();

    if (statusCode == 401) {
        setBusy(false);
        emit sessionExpired();
        return;
    }

    if (statusCode < 200 || statusCode >= 300) {
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

    if (type == CommentsRequest) {
        QVariantList shaped;
        for (int i = 0; i < rawItems.size(); ++i) {
            shaped.append(shapeComment(rawItems.at(i).toMap()));
        }
        m_comments = shaped;
        setBusy(false);
        emit commentsLoaded();
        return;
    }

    setBusy(false);
}

void XyzApiClient::onTimeout()
{
    abortActiveRequest();
    m_requestType = NoneRequest;
    setErrorMessage(QString::fromLatin1("Request timed out."));
    setBusy(false);
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
