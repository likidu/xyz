# Updates + Subscriptions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Updates feed (订阅 landing) and Subscriptions screen (grid + list) on a new native content client, with a custom bottom tab bar; post-login lands on Updates.

**Architecture:** A new C++ `XyzApiClient` (mirrors `AuthClient`: one `QNetworkAccessManager`, single in-flight reply, 15s timeout, qjson parse) calls `api.xiaoyuzhoufm.com/v1/{inbox,subscription}/list` directly with iOS-app spoof headers + the stored `x-jike-access-token`, and shapes each item into a flat `QVariantMap` (cover/title/desc/duration/relative-time) that QML delegates read via `modelData.*`. New QML pages (`UpdatesPage`, `SubscriptionsPage`, `BelleTabBar`) render the design; `AppWindow` routes login → Updates and wires the tab bar + session-expiry.

**Tech Stack:** Qt 4.7 / QML 1.1, Symbian Components 1.1, vendored qjson (already in `lib/qjson/`), MinGW Qt Simulator build via `scripts/build-simulator.ps1`.

**Verification note:** This project has **no unit-test runner** — verification is *build green* + *observe in the Qt Simulator* (the codebase's established idiom; see `SelfTestPage.qml`). The data path is exercised deterministically with a local mock server (`XYZ_API_BASE` override, script in Task 5) so no SMS/live token is required. After editing only `.qml`/`.qrc`/assets, force the qrc to rebuild by deleting `build-simulator/debug/rcc/qrc_qml.cpp` + `build-simulator/debug/obj/qrc_qml.o` first (see `docs/DEVICE_NOTES.md`).

**Branch:** `feat/updates-subscriptions` (already created).

---

## File structure

| File | Responsibility |
|---|---|
| `src/XyzApiClient.h` / `.cpp` (new) | Content client: fetch inbox/subscriptions, iOS headers, shape items, expose `QVariantList` + busy/error/sessionExpired |
| `src/main.cpp` (modify) | Instantiate `XyzApiClient`, set `xyzApi` context property |
| `Xyz.pro` (modify) | Register `XyzApiClient.{cpp,h}`; add new QML to `OTHER_FILES` |
| `qml/gfx/tab-*.svg`, `qml/gfx/icon-{play,queue,comment,dots,list,grid}.svg` (new) | Throwaway placeholder glyphs |
| `qml/BelleTabBar.qml` (new) | Custom glossy 4-tab bottom bar (placeholder icons) |
| `qml/UpdatesPage.qml` (new) | Updates feed screen |
| `qml/SubscriptionsPage.qml` (new) | Subscriptions grid + list screen |
| `qml/BelleHeader.qml` (modify) | Add optional trailing action (grid/list toggle) |
| `qml/AppWindow.qml` (modify) | Add pages, route login → Updates, tab routing, session-expiry |
| `qml/qml.qrc` (modify) | Register new QML + svgs |
| `qml/js/Theme.js` (modify) | One new constant (`tabBarHeight`) |
| `docs/*` , `tasks/plan.md` (modify) | API/design/device notes + milestone log |

---

## Task 1: `XyzApiClient` native content client

**Files:**
- Create: `src/XyzApiClient.h`, `src/XyzApiClient.cpp`
- Modify: `Xyz.pro:46-60`, `src/main.cpp`

- [ ] **Step 1: Write the header**

Create `src/XyzApiClient.h`:

```cpp
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

public:
    explicit XyzApiClient(StorageManager *storage, QObject *parent = 0);

    bool busy() const;
    QString errorMessage() const;
    QVariantList inboxItems() const;
    QVariantList subscriptions() const;

    Q_INVOKABLE void fetchInbox();
    Q_INVOKABLE void fetchSubscriptions();

signals:
    void busyChanged();
    void errorMessageChanged();
    void inboxLoaded();
    void subscriptionsLoaded();
    void sessionExpired();

private slots:
    void onReplyFinished();
    void onTimeout();
    void onSslErrors(const QList<QSslError> &errors);

private:
    enum RequestType { NoneRequest, InboxRequest, SubscriptionsRequest };

    void startPost(RequestType type, const QString &path, const QVariantMap &body);
    void abortActiveRequest();
    void applyContentHeaders(QNetworkRequest &request);
    void setBusy(bool busy);
    void setErrorMessage(const QString &message);

    QVariantMap shapeInboxItem(const QVariantMap &item) const;
    QVariantMap shapeSubscription(const QVariantMap &item) const;
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
};

#endif // XYZAPICLIENT_H
```

- [ ] **Step 2: Write the implementation**

Create `src/XyzApiClient.cpp`:

```cpp
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
    QVariantList rawItems;
    if (ok) {
        const QVariantMap top = root.toMap();
        const QVariantMap data = top.value(QString::fromLatin1("data")).toMap();
        rawItems = data.value(QString::fromLatin1("data")).toList();
    }

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
```

- [ ] **Step 3: Register in `Xyz.pro`**

In `Xyz.pro`, add `XyzApiClient` to SOURCES and HEADERS (after the `AuthClient` lines):

```
SOURCES += \
    src/main.cpp \
    src/MemoryMonitor.cpp \
    src/TlsChecker.cpp \
    src/StorageManager.cpp \
    src/AudioEngine.cpp \
    src/AuthClient.cpp \
    src/XyzApiClient.cpp

HEADERS += \
    src/MemoryMonitor.h \
    src/TlsChecker.h \
    src/AppConfig.h \
    src/StorageManager.h \
    src/AudioEngine.h \
    src/AuthClient.h \
    src/XyzApiClient.h
```

- [ ] **Step 4: Register the context property in `src/main.cpp`**

Add the include near the other client include (`src/main.cpp:31`):

```cpp
#include "AuthClient.h"
#include "XyzApiClient.h"
```

Instantiate it next to `AuthClient` (`src/main.cpp:412`):

```cpp
    AuthClient authClient(&storage);
    XyzApiClient xyzApiClient(&storage);
```

Set the context property next to `auth` (`src/main.cpp:425`):

```cpp
    view.rootContext()->setContextProperty("auth", &authClient);
    view.rootContext()->setContextProperty("xyzApi", &xyzApiClient);
```

- [ ] **Step 5: Build**

Run: `pwsh -File scripts/build-simulator.ps1 -Config Debug`
Expected: build succeeds, `XyzApiClient.cpp` compiles and links (qjson already vendored). App still launches to the existing flow (no behavior change yet).

- [ ] **Step 6: Commit**

```bash
git add src/XyzApiClient.h src/XyzApiClient.cpp Xyz.pro src/main.cpp
git commit -m "Add native XyzApiClient (inbox + subscriptions, iOS headers)"
```

---

## Task 2: Placeholder glyph SVGs

Throwaway placeholder icons (per the user: don't invest in real icons yet). All use `viewBox="0 0 24 24"` so they render at the QML `width`/`height` on both simulator and device (per the Symbian SVG sizing rule in CLAUDE.md). Stroke `#c4c4cc`, no fill.

**Files:** Create all under `qml/gfx/`; Modify `qml/qml.qrc`.

- [ ] **Step 1: Create the four tab glyphs**

`qml/gfx/tab-compass.svg`:
```svg
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#c4c4cc" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><path d="M15.5 8.5l-2 5-5 2 2-5z"/></svg>
```

`qml/gfx/tab-search.svg`:
```svg
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#c4c4cc" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="6.5"/><path d="M16 16l4 4"/></svg>
```

`qml/gfx/tab-headphones.svg`:
```svg
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#c4c4cc" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 13v-1a8 8 0 0116 0v1"/><rect x="3" y="13" width="4" height="7" rx="1.5"/><rect x="17" y="13" width="4" height="7" rx="1.5"/></svg>
```

`qml/gfx/tab-person.svg`:
```svg
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#c4c4cc" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="8" r="4"/><path d="M4.5 20a7.5 7.5 0 0115 0"/></svg>
```

- [ ] **Step 2: Create the content glyphs**

`qml/gfx/icon-play.svg` (filled triangle, accent):
```svg
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="#a98cff"><path d="M8 5.5v13l11-6.5z"/></svg>
```

`qml/gfx/icon-queue.svg`:
```svg
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#8b8b95" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7h11M4 12h11M4 17h7"/><path d="M18 13.5v7M14.5 17h7"/></svg>
```

`qml/gfx/icon-comment.svg`:
```svg
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#a98cff" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 5h16v11H9l-5 4z"/></svg>
```

`qml/gfx/icon-dots.svg`:
```svg
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="#8b8b95"><circle cx="12" cy="5" r="1.7"/><circle cx="12" cy="12" r="1.7"/><circle cx="12" cy="19" r="1.7"/></svg>
```

`qml/gfx/icon-list.svg` (header toggle → switch to list):
```svg
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#c4c4cc" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M8 7h12M8 12h12M8 17h12"/><circle cx="4" cy="7" r="1" fill="#c4c4cc" stroke="none"/><circle cx="4" cy="12" r="1" fill="#c4c4cc" stroke="none"/><circle cx="4" cy="17" r="1" fill="#c4c4cc" stroke="none"/></svg>
```

`qml/gfx/icon-grid.svg` (header toggle → switch to grid):
```svg
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#c4c4cc" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><rect x="4" y="4" width="6.5" height="6.5" rx="1.2"/><rect x="13.5" y="4" width="6.5" height="6.5" rx="1.2"/><rect x="4" y="13.5" width="6.5" height="6.5" rx="1.2"/><rect x="13.5" y="13.5" width="6.5" height="6.5" rx="1.2"/></svg>
```

- [ ] **Step 3: Register the svgs in `qml/qml.qrc`**

Add inside `<qresource prefix="/qml">` (after the existing `gfx/*.svg` lines):

```xml
        <file>gfx/tab-compass.svg</file>
        <file>gfx/tab-search.svg</file>
        <file>gfx/tab-headphones.svg</file>
        <file>gfx/tab-person.svg</file>
        <file>gfx/icon-play.svg</file>
        <file>gfx/icon-queue.svg</file>
        <file>gfx/icon-comment.svg</file>
        <file>gfx/icon-dots.svg</file>
        <file>gfx/icon-list.svg</file>
        <file>gfx/icon-grid.svg</file>
```

- [ ] **Step 4: Force qrc rebuild + build**

Run:
```bash
rm -f build-simulator/debug/rcc/qrc_qml.cpp build-simulator/debug/obj/qrc_qml.o
pwsh -File scripts/build-simulator.ps1 -Config Debug
```
Expected: build succeeds (svgs bundled into the qrc). No visible change yet.

- [ ] **Step 5: Commit**

```bash
git add qml/gfx/tab-*.svg qml/gfx/icon-play.svg qml/gfx/icon-queue.svg qml/gfx/icon-comment.svg qml/gfx/icon-dots.svg qml/gfx/icon-list.svg qml/gfx/icon-grid.svg qml/qml.qrc
git commit -m "Add placeholder tab + content glyph SVGs"
```

---

## Task 3: `BelleTabBar` component

**Files:** Create `qml/BelleTabBar.qml`; Modify `qml/qml.qrc`, `qml/js/Theme.js`, `Xyz.pro`.

- [ ] **Step 1: Add `tabBarHeight` to `qml/js/Theme.js`**

Append after `var pagePadding = 22;`:

```javascript
var tabBarHeight = 56;
```

- [ ] **Step 2: Create `qml/BelleTabBar.qml`**

```qml
import QtQuick 1.1
import "js/Theme.js" as Theme

// Custom Belle bottom tab bar (icon-only, glossy) — design: belle.css .toolbar.
// Placeholder glyphs; active tab marked by full opacity + an accent dot.
Rectangle {
    id: tabBar

    property int activeIndex: 2
    signal tabSelected(int index)

    height: Theme.tabBarHeight
    gradient: Gradient {
        GradientStop { position: 0.0; color: "#2a2a30" }
        GradientStop { position: 0.08; color: "#1d1d22" }
        GradientStop { position: 1.0; color: "#141417" }
    }

    // 1px black top border
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: "#000000"
    }

    // Belle 'expand options' grab handle (decorative)
    Rectangle {
        width: 46
        height: 4
        radius: 2
        color: "#3a3a42"
        anchors.top: parent.top
        anchors.topMargin: 4
        anchors.horizontalCenter: parent.horizontalCenter
    }

    Row {
        anchors.fill: parent

        Repeater {
            model: ["gfx/tab-compass.svg", "gfx/tab-search.svg",
                    "gfx/tab-headphones.svg", "gfx/tab-person.svg"]

            Item {
                width: tabBar.width / 4
                height: tabBar.height

                Rectangle {
                    width: 1
                    height: 28
                    color: "#12FFFFFF"
                    visible: index > 0
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                }

                Image {
                    source: modelData
                    width: 24
                    height: 24
                    smooth: true
                    anchors.centerIn: parent
                    opacity: index === tabBar.activeIndex ? 1.0 : 0.65
                }

                Rectangle {
                    width: 5
                    height: 5
                    radius: 2.5
                    color: Theme.accentBright
                    visible: index === tabBar.activeIndex
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 6
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: tabBar.tabSelected(index)
                }
            }
        }
    }
}
```

- [ ] **Step 3: Register in `qml/qml.qrc` and `Xyz.pro`**

`qml/qml.qrc` — add after `<file>BelleHeader.qml</file>`:
```xml
        <file>BelleTabBar.qml</file>
```
`Xyz.pro` — add to `OTHER_FILES` (after `qml/BelleHeader.qml`):
```
    qml/BelleTabBar.qml \
```

- [ ] **Step 4: Force qrc rebuild + build**

Run:
```bash
rm -f build-simulator/debug/rcc/qrc_qml.cpp build-simulator/debug/obj/qrc_qml.o
pwsh -File scripts/build-simulator.ps1 -Config Debug
```
Expected: build succeeds (component is registered but not yet placed on a page).

- [ ] **Step 5: Commit**

```bash
git add qml/BelleTabBar.qml qml/qml.qrc qml/js/Theme.js Xyz.pro
git commit -m "Add BelleTabBar component"
```

---

## Task 4: `BelleHeader` optional trailing action

**Files:** Modify `qml/BelleHeader.qml`.

- [ ] **Step 1: Add the trailing action properties + signal**

In `qml/BelleHeader.qml`, after the existing `property bool showBack: true` / `signal backClicked` lines, add:

```qml
    property bool showBack: true
    property string actionIconSource: ""
    property bool actionOn: false
    signal backClicked
    signal actionClicked
```

- [ ] **Step 2: Render the action button and keep the title clear of it**

Change the title's right anchor so it never overlaps the action, and add the action button. Replace the `titleText` right anchor line:

```qml
        anchors.right: actionButton.visible ? actionButton.left : parent.right
        anchors.rightMargin: 6
```

Then add, just before the bottom 1px border `Rectangle` (the last child):

```qml
    Item {
        id: actionButton
        visible: header.actionIconSource !== ""
        width: 44
        height: 44
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter

        Rectangle {
            anchors.fill: parent
            radius: 4
            color: Theme.accentDeep
            opacity: actionMouse.pressed ? 0.4 : 0
        }
        Image {
            source: header.actionIconSource
            width: 24
            height: 24
            smooth: true
            anchors.centerIn: parent
            opacity: header.actionOn ? 1.0 : 0.8
        }
        MouseArea {
            id: actionMouse
            anchors.fill: parent
            onClicked: header.actionClicked()
        }
    }
```

- [ ] **Step 3: Force qrc rebuild + build**

Run:
```bash
rm -f build-simulator/debug/rcc/qrc_qml.cpp build-simulator/debug/obj/qrc_qml.o
pwsh -File scripts/build-simulator.ps1 -Config Debug
```
Expected: build succeeds. Existing headers (LoginPage/VerifyCodePage/HomePage) are unaffected — `actionIconSource` defaults to `""` so no action renders and the title keeps its full width.

- [ ] **Step 4: Commit**

```bash
git add qml/BelleHeader.qml
git commit -m "BelleHeader: optional trailing action button"
```

---

## Task 5: `UpdatesPage` + route login → Updates

**Files:** Create `qml/UpdatesPage.qml`; Modify `qml/AppWindow.qml`, `qml/qml.qrc`, `Xyz.pro`.

- [ ] **Step 1: Create `qml/UpdatesPage.qml`**

```qml
import QtQuick 1.1
import com.nokia.symbian 1.1
import "js/Theme.js" as Theme

// Updates — subscription tab landing feed (design: screens-updates.jsx).
// Episode cards from /v1/inbox/list via the native xyzApi client.
Page {
    id: page
    objectName: "UpdatesPage"

    property bool hidesToolBar: true
    property bool loadedOnce: false

    signal mySubsRequested
    signal tabSelected(int index)

    function load() {
        if (page.loadedOnce) {
            return;
        }
        page.loadedOnce = true;
        xyzApi.fetchInbox();
    }

    onStatusChanged: {
        if (status === PageStatus.Active) {
            page.load();
        }
    }

    Rectangle { anchors.fill: parent; color: Theme.bg }

    // ---- glossy title bar (design .up-titlebar) ----
    Rectangle {
        id: titleBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 56
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.chromeHi }
            GradientStop { position: 0.06; color: "#232328" }
            GradientStop { position: 0.6; color: "#1a1a1e" }
            GradientStop { position: 1.0; color: Theme.chromeLo }
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("Updates")
            font.pixelSize: 24
            font.bold: true
            color: Theme.text
        }

        Rectangle {
            id: mySubsBtn
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            height: 34
            width: mySubsRow.width + 26
            radius: 8
            color: "#248b6dff"
            border.width: 1
            border.color: "#618b6dff"
            opacity: mySubsMouse.pressed ? 0.7 : 1.0

            Row {
                id: mySubsRow
                anchors.centerIn: parent
                spacing: 7
                Image {
                    source: "gfx/tab-headphones.svg"
                    width: 16
                    height: 16
                    smooth: true
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: qsTr("My Subscriptions")
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: Theme.accentBright
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            MouseArea {
                id: mySubsMouse
                anchors.fill: parent
                onClicked: page.mySubsRequested()
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: "#000000"
        }
    }

    // ---- feed ----
    ListView {
        id: list
        anchors.top: titleBar.bottom
        anchors.bottom: tabBar.top
        anchors.left: parent.left
        anchors.right: parent.right
        clip: true
        model: xyzApi.inboxItems
        delegate: updateDelegate
    }

    Component {
        id: updateDelegate
        Item {
            width: list.width
            height: col.height + 28

            Column {
                id: col
                anchors.top: parent.top
                anchors.topMargin: 14
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 11

                Row {
                    width: parent.width
                    spacing: 12

                    Image {
                        width: 64
                        height: 64
                        fillMode: Image.PreserveAspectCrop
                        clip: true
                        smooth: true
                        sourceSize.width: 64
                        sourceSize.height: 64
                        source: modelData.coverUrl
                    }

                    Column {
                        width: parent.width - 76
                        spacing: 6

                        Text {
                            width: parent.width
                            text: modelData.title
                            font.pixelSize: 15
                            font.bold: true
                            color: Theme.text
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: modelData.desc
                            font.pixelSize: 12
                            color: Theme.textDim
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                    }
                }

                // meta row (dot separators avoid unicode tofu on Symbian)
                Row {
                    width: parent.width
                    spacing: 9

                    Text { text: modelData.durationText; font.pixelSize: 11; color: Theme.textFaint; anchors.verticalCenter: parent.verticalCenter }
                    Rectangle { width: 3; height: 3; radius: 1.5; color: Theme.textFaint; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: modelData.whenText; font.pixelSize: 11; color: Theme.textFaint; anchors.verticalCenter: parent.verticalCenter }
                    Rectangle { width: 3; height: 3; radius: 1.5; color: Theme.textFaint; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: modelData.playCount + " " + qsTr("plays"); font.pixelSize: 11; color: Theme.textFaint; anchors.verticalCenter: parent.verticalCenter }
                    Rectangle { width: 3; height: 3; radius: 1.5; color: Theme.textFaint; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: modelData.commentCount + " " + qsTr("comments"); font.pixelSize: 11; color: Theme.textFaint; anchors.verticalCenter: parent.verticalCenter }
                }

                // action row (placeholders — player deferred; controls inert)
                Item {
                    width: parent.width
                    height: 48

                    Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 18

                        Image { source: "gfx/icon-queue.svg"; width: 26; height: 26; smooth: true; opacity: 0.7; anchors.verticalCenter: parent.verticalCenter }
                        Row {
                            spacing: 6
                            anchors.verticalCenter: parent.verticalCenter
                            Image { source: "gfx/icon-comment.svg"; width: 26; height: 26; smooth: true; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: modelData.commentCount; font.pixelSize: 13; font.weight: Font.DemiBold; color: Theme.accentBright; anchors.verticalCenter: parent.verticalCenter }
                        }
                        Image { source: "gfx/icon-dots.svg"; width: 26; height: 26; smooth: true; opacity: 0.7; anchors.verticalCenter: parent.verticalCenter }
                    }

                    Rectangle {
                        width: 48
                        height: 48
                        radius: 24
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        color: "#248b6dff"
                        border.width: 1
                        border.color: Theme.accent
                        Image { source: "gfx/icon-play.svg"; width: 24; height: 24; smooth: true; anchors.centerIn: parent }
                    }
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: Theme.hairline
            }
        }
    }

    // ---- states ----
    BusyIndicator {
        running: xyzApi.busy && list.count === 0
        visible: running
        width: 48
        height: 48
        anchors.centerIn: list
    }
    Text {
        visible: !xyzApi.busy && xyzApi.errorMessage.length > 0 && list.count === 0
        anchors.centerIn: list
        width: list.width - 48
        text: xyzApi.errorMessage
        color: Theme.errorColor
        font.pixelSize: 13
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
    }
    Text {
        visible: !xyzApi.busy && xyzApi.errorMessage.length === 0 && list.count === 0 && page.loadedOnce
        anchors.centerIn: list
        text: qsTr("No updates yet")
        color: Theme.textDim
        font.pixelSize: 14
    }

    BelleTabBar {
        id: tabBar
        activeIndex: 2
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        onTabSelected: page.tabSelected(index)
    }
}
```

- [ ] **Step 2: Register in `qml/qml.qrc` and `Xyz.pro`**

`qml/qml.qrc` — add after `<file>HomePage.qml</file>`:
```xml
        <file>UpdatesPage.qml</file>
```
`Xyz.pro` — add to `OTHER_FILES` (after `qml/HomePage.qml`):
```
    qml/UpdatesPage.qml \
```

- [ ] **Step 3: Wire `AppWindow.qml` — add the page, route login → Updates, tab routing, session-expiry**

In `qml/AppWindow.qml`:

(a) Add a `handleTab` function next to the others (after `isLoggedIn()`):
```qml
    function handleTab(index) {
        if (index === 2) {
            if (pageStack.currentPage !== updatesPage) {
                pageStack.pop(updatesPage);
            }
        } else if (index === 3) {
            if (pageStack.currentPage !== homePage) {
                pageStack.push(homePage);
            }
        }
        // index 0 (Discover) / 1 (Search) are inert placeholders for now.
    }
```

(b) Change `VerifyCodePage.onLoggedIn` to land on Updates:
```qml
    VerifyCodePage {
        id: verifyCodePage
        onLoggedIn: {
            pageStack.clear();
            pageStack.push(updatesPage);
        }
    }
```

(c) Add the `UpdatesPage` instance (after the `HomePage` block). `subscriptionsPage` is added in Task 6 — the `onMySubsRequested` body is filled in then; leave it as a no-op stub for now:
```qml
    UpdatesPage {
        id: updatesPage
        onMySubsRequested: { /* wired to SubscriptionsPage in Task 6 */ }
        onTabSelected: window.handleTab(index)
    }
```

(d) Add a `Connections` for session expiry (anywhere at window scope, e.g. after the `Menu` block):
```qml
    Connections {
        target: xyzApi
        onSessionExpired: {
            auth.logout();
            pageStack.clear();
            pageStack.push(loginPage);
        }
    }
```

(e) Change `initialPage` to land on Updates when logged in:
```qml
    initialPage: isLoggedIn() ? updatesPage : loginPage
```

- [ ] **Step 4: Force qrc rebuild + build**

Run:
```bash
rm -f build-simulator/debug/rcc/qrc_qml.cpp build-simulator/debug/obj/qrc_qml.o
pwsh -File scripts/build-simulator.ps1 -Config Debug
```
Expected: build succeeds.

- [ ] **Step 5: Write the local mock server (deterministic, no SMS)**

Create `scripts/mock-content.ps1` (returns official-shaped inbox + subscription JSON; reused in Task 6):

```powershell
# Minimal mock of api.xiaoyuzhoufm.com content endpoints for simulator testing.
# Run:  pwsh -File scripts/mock-content.ps1   (listens on http://localhost:8099)
# Then: $env:XYZ_API_BASE = "http://localhost:8099"  before launching the app.
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:8099/")
$listener.Start()
Write-Host "mock-content on http://localhost:8099 (Ctrl+C to stop)"

$img = "https://picsum.photos/seed/xyz/120"
$inbox = @{ code=200; msg="OK"; data=@{ data=@(
  @{ type="EPISODE"; eid="e1"; title="Summit: The Weekly Orbit 6.6";
     description="Hosts: Luma / Vega / Pico / Radish. Headlines: State of Play drops a wave of new titles.";
     duration=7800; pubDate="2026-06-13T09:00:00.000Z"; playCount=143; commentCount=1;
     image=@{ thumbnailUrl=$img; smallPicUrl=$img } },
  @{ type="EPISODE"; eid="e2"; title="183. Reading the Stars: Poems at the Edge of Night";
     description="Did the poets really turn away from the cold light of dusk? This episode makes the case.";
     duration=6900; pubDate="2026-06-12T18:00:00.000Z"; playCount=7941; commentCount=120;
     image=@{ thumbnailUrl=$img; smallPicUrl=$img } }
) } } | ConvertTo-Json -Depth 8

$subs = @{ code=200; msg="OK"; data=@{ data=@(
  @{ type="PODCAST"; pid="p1"; title="Cosmic Drift"; subscriptionOftenPlayed=$true;
     latestEpisodePubDate="2026-06-11T10:00:00.000Z"; image=@{ smallPicUrl=$img; thumbnailUrl=$img };
     podcasters=@(@{ nickname="Luma"; avatar=@{ picture=@{ smallPicUrl=$img; thumbnailUrl=$img } } },
                  @{ nickname="Vega"; avatar=@{ picture=@{ smallPicUrl=$img; thumbnailUrl=$img } } }) },
  @{ type="PODCAST"; pid="p2"; title="Code & Coffee";
     latestEpisodePubDate="2026-06-12T22:00:00.000Z"; image=@{ smallPicUrl=$img; thumbnailUrl=$img };
     podcasters=@(@{ nickname="Sol"; avatar=@{ picture=@{ smallPicUrl=$img; thumbnailUrl=$img } } }) }
) } } | ConvertTo-Json -Depth 8

while ($listener.IsListening) {
  $ctx = $listener.GetContext()
  $path = $ctx.Request.Url.AbsolutePath
  $body = if ($path -like "*subscription*") { $subs } else { $inbox }
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
  $ctx.Response.ContentType = "application/json; charset=utf-8"
  $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
  $ctx.Response.Close()
}
```

- [ ] **Step 6: Run the simulator against the mock and observe Updates**

Run (two terminals):
```bash
pwsh -File scripts/mock-content.ps1   # terminal A
```
```bash
XYZ_API_BASE=http://localhost:8099 ./build-simulator/debug/Xyz.exe   # terminal B
```
(If no token is stored in the sim DB, also temporarily seed one so the headers are non-empty — any string works against the mock — or log in once.)

Expected: after login the app lands on **UpdatesPage** — glossy "Updates" title + "My Subscriptions" pill, two cards with covers, 2-line titles/descriptions, the meta row ("130 min · 17h ago · 143 plays · 1 comments"; second card shows "99+" comments), the action row, and the bottom tab bar with the headphones tab marked active. Tapping the **person** tab pushes the Account screen; back returns to Updates.

- [ ] **Step 7: Commit**

```bash
git add qml/UpdatesPage.qml qml/AppWindow.qml qml/qml.qrc Xyz.pro scripts/mock-content.ps1
git commit -m "Add UpdatesPage; land on Updates after login"
```

---

## Task 6: `SubscriptionsPage` (grid + list)

**Files:** Create `qml/SubscriptionsPage.qml`; Modify `qml/AppWindow.qml`, `qml/qml.qrc`, `Xyz.pro`.

- [ ] **Step 1: Create `qml/SubscriptionsPage.qml`**

```qml
import QtQuick 1.1
import com.nokia.symbian 1.1
import "js/Theme.js" as Theme

// Subscriptions — 我的订阅 grid + list (design: screens-subs.jsx).
// Data from /v1/subscription/list via the native xyzApi client.
Page {
    id: page
    objectName: "SubscriptionsPage"

    property bool hidesToolBar: true
    property bool loadedOnce: false
    property string viewMode: "grid"

    signal tabSelected(int index)

    function load() {
        if (page.loadedOnce) {
            return;
        }
        page.loadedOnce = true;
        xyzApi.fetchSubscriptions();
    }

    function toggleView() {
        page.viewMode = (page.viewMode === "grid") ? "list" : "grid";
    }

    onStatusChanged: {
        if (status === PageStatus.Active) {
            page.load();
        }
    }

    Rectangle { anchors.fill: parent; color: Theme.bg }

    BelleHeader {
        id: header
        title: qsTr("Subscriptions")
        actionIconSource: page.viewMode === "grid" ? "gfx/icon-list.svg" : "gfx/icon-grid.svg"
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        onBackClicked: pageStack.pop()
        onActionClicked: page.toggleView()
    }

    Item {
        id: content
        anchors.top: header.bottom
        anchors.bottom: tabBar.top
        anchors.left: parent.left
        anchors.right: parent.right
        clip: true

        // ---- GRID ----
        GridView {
            id: grid
            anchors.fill: parent
            visible: page.viewMode === "grid"
            model: xyzApi.subscriptions
            cellWidth: Math.floor(width / 3)
            cellHeight: cellWidth
            clip: true
            delegate: Item {
                width: grid.cellWidth
                height: grid.cellHeight

                Image {
                    anchors.fill: parent
                    anchors.margins: 1
                    fillMode: Image.PreserveAspectCrop
                    clip: true
                    smooth: true
                    sourceSize.width: 120
                    sourceSize.height: 120
                    source: modelData.coverUrl
                }
                Rectangle {
                    visible: modelData.often
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: 6
                    height: 18
                    width: oftenText.width + 12
                    radius: 4
                    color: "#C7080612"
                    border.width: 1
                    border.color: "#808b6dff"
                    Text {
                        id: oftenText
                        anchors.centerIn: parent
                        text: qsTr("Often")
                        font.pixelSize: 10
                        font.bold: true
                        color: Theme.accentBright
                    }
                }
            }
        }

        // ---- LIST ----
        ListView {
            id: subsList
            anchors.fill: parent
            visible: page.viewMode === "list"
            model: xyzApi.subscriptions
            clip: true
            header: listHeader
            delegate: rowDelegate
        }
    }

    // list header: search + starred empty-state + "All Subscriptions" subhead
    Component {
        id: listHeader
        Column {
            width: subsList.width

            Item {
                width: parent.width
                height: 56
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    anchors.top: parent.top
                    anchors.topMargin: 10
                    height: 42
                    radius: 7
                    color: "#161619"
                    border.width: 1
                    border.color: Theme.hairline
                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 13
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 9
                        Image { source: "gfx/tab-search.svg"; width: 17; height: 17; smooth: true; opacity: 0.6; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: qsTr("Search your subscriptions"); font.pixelSize: 14; color: Theme.textFaint; anchors.verticalCenter: parent.verticalCenter }
                    }
                }
            }

            Item {
                width: parent.width
                height: 32
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 8
                    text: qsTr("Starred")
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: Theme.accentBright
                }
            }

            Item {
                width: parent.width
                height: 118
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    anchors.top: parent.top
                    height: 108
                    radius: 9
                    border.width: 1
                    border.color: Theme.hairline
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Theme.panel2 }
                        GradientStop { position: 1.0; color: Theme.panel }
                    }
                    Column {
                        anchors.centerIn: parent
                        spacing: 8
                        Text {
                            width: 220
                            text: qsTr("Star shows you love for a shortcut on the Updates page")
                            font.pixelSize: 12
                            color: Theme.textDim
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        Text {
                            text: "+ " + qsTr("Add")
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            color: Theme.accentBright
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }
            }

            Item {
                width: parent.width
                height: 32
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 8
                    text: qsTr("All Subscriptions")
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: Theme.accentBright
                }
            }
        }
    }

    // list row: cover + name + avatar stack + hosts·when + dots
    Component {
        id: rowDelegate
        Item {
            width: subsList.width
            height: 72

            Row {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12

                Image {
                    width: 52
                    height: 52
                    fillMode: Image.PreserveAspectCrop
                    clip: true
                    smooth: true
                    sourceSize.width: 52
                    sourceSize.height: 52
                    source: modelData.coverUrl
                    anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                    width: subsList.width - 24 - 52 - 12 - 28
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5

                    Text {
                        width: parent.width
                        text: modelData.name
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        color: Theme.text
                        elide: Text.ElideRight
                    }
                    Row {
                        width: parent.width
                        spacing: 7

                        Row {
                            spacing: 3
                            anchors.verticalCenter: parent.verticalCenter
                            Repeater {
                                model: modelData.avatarUrls
                                Rectangle {
                                    width: 19
                                    height: 19
                                    radius: 4
                                    clip: true
                                    color: "#232030"
                                    Image {
                                        anchors.fill: parent
                                        fillMode: Image.PreserveAspectCrop
                                        smooth: true
                                        sourceSize.width: 19
                                        sourceSize.height: 19
                                        source: modelData
                                    }
                                }
                            }
                        }
                        Text {
                            text: modelData.hostsText + "  ·  " + modelData.whenText
                            font.pixelSize: 12
                            color: Theme.textDim
                            elide: Text.ElideRight
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                Image {
                    source: "gfx/icon-dots.svg"
                    width: 18
                    height: 18
                    smooth: true
                    opacity: 0.8
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: Theme.hairline
            }
        }
    }

    // ---- states ----
    BusyIndicator {
        running: xyzApi.busy && xyzApi.subscriptions.length === 0
        visible: running
        width: 48
        height: 48
        anchors.centerIn: content
    }
    Text {
        visible: !xyzApi.busy && xyzApi.errorMessage.length > 0 && xyzApi.subscriptions.length === 0
        anchors.centerIn: content
        width: content.width - 48
        text: xyzApi.errorMessage
        color: Theme.errorColor
        font.pixelSize: 13
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
    }
    Text {
        visible: !xyzApi.busy && xyzApi.errorMessage.length === 0 && xyzApi.subscriptions.length === 0 && page.loadedOnce
        anchors.centerIn: content
        text: qsTr("No subscriptions yet")
        color: Theme.textDim
        font.pixelSize: 14
    }

    BelleTabBar {
        id: tabBar
        activeIndex: 2
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        onTabSelected: page.tabSelected(index)
    }
}
```

- [ ] **Step 2: Register in `qml/qml.qrc` and `Xyz.pro`**

`qml/qml.qrc` — add after `<file>UpdatesPage.qml</file>`:
```xml
        <file>SubscriptionsPage.qml</file>
```
`Xyz.pro` — add to `OTHER_FILES` (after `qml/UpdatesPage.qml`):
```
    qml/SubscriptionsPage.qml \
```

- [ ] **Step 3: Wire `AppWindow.qml` — add the page + fill the `mySubsRequested` stub**

Add the `SubscriptionsPage` instance (after the `UpdatesPage` block):
```qml
    SubscriptionsPage {
        id: subscriptionsPage
        onTabSelected: window.handleTab(index)
    }
```
Fill the previously-stubbed `UpdatesPage.onMySubsRequested`:
```qml
    UpdatesPage {
        id: updatesPage
        onMySubsRequested: pageStack.push(subscriptionsPage)
        onTabSelected: window.handleTab(index)
    }
```

- [ ] **Step 4: Force qrc rebuild + build**

Run:
```bash
rm -f build-simulator/debug/rcc/qrc_qml.cpp build-simulator/debug/obj/qrc_qml.o
pwsh -File scripts/build-simulator.ps1 -Config Debug
```
Expected: build succeeds.

- [ ] **Step 5: Run against the mock and observe Subscriptions**

With `scripts/mock-content.ps1` running and `XYZ_API_BASE=http://localhost:8099`, launch and from Updates tap **My Subscriptions**.

Expected:
- **Grid** (default): 3-column cover wall; the first cell ("Cosmic Drift") shows the "Often" badge.
- Tap the header **toggle** → **List**: search field, "Starred" empty-state card (hint + Add), "All Subscriptions" subhead, then rows — 52px cover, name, avatar stack + "Luma, Vega · Nd ago", overflow dots. Toggle back → grid.
- **Back** chevron → returns to Updates.

- [ ] **Step 6: Commit**

```bash
git add qml/SubscriptionsPage.qml qml/AppWindow.qml qml/qml.qrc Xyz.pro
git commit -m "Add SubscriptionsPage (grid + list); wire My Subscriptions"
```

---

## Task 7: Docs + final verification

**Files:** Modify `docs/API_NOTES.md`, `docs/DESIGN_SYSTEM.md`, `docs/DEVICE_NOTES.md`, `docs/PLAN.md`, `tasks/plan.md`.

- [ ] **Step 1: `docs/API_NOTES.md` — add the content endpoints**

Append a section:
```markdown
## Content endpoints (M2)

Direct to `https://api.xiaoyuzhoufm.com`, POST + JSON, with **iOS-app spoof headers**
(different from the auth host's browser headers): `User-Agent: Xiaoyuzhou/2.57.1
(build:1576; iOS 17.4.1)`, `OS: ios`, `BundleID: app.podcast.cosmos`, `App-Version: 2.57.1`,
`App-BuildNo: 1576`, `Model: iPhone14,2`, `Manufacturer: Apple`, `app-permissions: 4`,
`Accept: */*`, `Accept-Language: zh-Hans-CN;q=1.0, zh-Hant-TW;q=0.9`, `Timezone: Asia/Shanghai`,
`Local-Time: <ISO8601>`, and `x-jike-access-token: <stored token>`.

| Action | Endpoint | Body |
|---|---|---|
| Updates feed | `POST /v1/inbox/list` | `{"limit":"20"}` (+ `loadMoreKey:{pubDate,id}` for paging — deferred) |
| Subscriptions | `POST /v1/subscription/list` | `{"limit":"20","sortOrder":"desc","sortBy":"subscribedAt"}` |

- Tokens are read from `StorageManager` (`auth.accessToken`). HTTP **401** → `sessionExpired`
  → re-login (refresh-token flow still deferred).
- `XYZ_API_BASE` env var overrides the host for testing; it expects **official-shaped**
  endpoints (e.g. `scripts/mock-content.ps1`), NOT the ultrazg proxy whose routes/bodies differ.
- Implemented natively in `src/XyzApiClient.{h,cpp}` (`xyzApi` context property).
```

- [ ] **Step 2: `docs/DESIGN_SYSTEM.md` — promote Updates/Subs/tab-bar from "later"**

Replace the "Other screens (recorded for later milestones)" paragraph's mention of the toolbar/lists with a short note that the **bottom tab bar** (`BelleTabBar`, 56px, 4 placeholder tabs + active accent dot + grab handle), **Updates** title bar (24px/800 + "My Subscriptions" pill, 64px episode covers), and **Subscriptions** grid (3-col, "Often" badge) / list (search + starred empty-state + 52px rows with avatar stack) are implemented in M2 (placeholder glyphs pending real icons).

- [ ] **Step 3: `docs/DEVICE_NOTES.md` — add a dated entry**

```markdown
## 2026-06-13 — M2 content screens (remote images, content API)

- Content API is `api.xiaoyuzhoufm.com` (iOS-app headers), separate from the auth host.
  `XyzApiClient` reuses the AuthClient pattern (single in-flight reply, qjson, ignore SSL).
- Remote cover/avatar `Image`s load through the QML engine's `SslIgnoringNamFactory`
  (stale CA tolerated). Memory bounded via `sourceSize` caps + ListView/GridView lazy
  delegates — watch `memoryMonitor` on-device with 20+ covers.
- QML 1.1 limits: no circular Image clipping (avatars are rounded squares); avatar stack
  uses positive spacing (no negative-margin overlap). Date/number formatting done in C++
  (`shapeInboxItem`/`shapeSubscription`), not QML bindings.
- Reminder: editing only `.qml`/`.qrc`/svgs does not retrigger rcc — delete
  `build-simulator/debug/rcc/qrc_qml.cpp` + `obj/qrc_qml.o` before rebuilding.
```

- [ ] **Step 4: `docs/PLAN.md` + `tasks/plan.md` — log M2**

Add an M2 entry summarizing: native `XyzApiClient`, Updates + Subscriptions screens,
`BelleTabBar`, land-on-Updates, placeholder icons; non-goals (player/mini-player, pagination,
search/sort/star actions, starred fetch) deferred.

- [ ] **Step 5: Final drive-through (mock) + optional live read**

With the mock running, confirm the full flow end to end:
`login → Updates (cards, covers, meta, tab bar) → My Subscriptions → grid (Often badge) →
toggle list (search/starred/rows+avatars) → back → Updates → person tab → Account → sign out`.

Optional live read (safe — `inbox/list` & `subscription/list` are read-only, no SMS): unset
`XYZ_API_BASE`, log in with the real number once, confirm real podcasts/episodes render with
real covers. Capture a screenshot of Updates + Subscriptions.

- [ ] **Step 6: Commit**

```bash
git add docs/API_NOTES.md docs/DESIGN_SYSTEM.md docs/DEVICE_NOTES.md docs/PLAN.md tasks/plan.md
git commit -m "Docs: M2 Updates + Subscriptions"
```

---

## Self-review notes (author)

- **Spec coverage:** XyzApiClient (Task 1) ✓; iOS headers (Task 1) ✓; data shaping + relative
  time (Task 1) ✓; `XYZ_API_BASE` (Task 1) ✓; BelleTabBar placeholder icons (Tasks 2–3) ✓;
  BelleHeader trailing action (Task 4) ✓; UpdatesPage + land-on-Updates + session-expiry
  (Task 5) ✓; SubscriptionsPage grid+list + starred empty-state + toggle (Task 6) ✓;
  busy/error/empty states (Tasks 5–6) ✓; docs (Task 7) ✓. Non-goals (player/mini-player,
  pagination, real search/sort/star, starred fetch, Discover/Search tabs) intentionally absent.
- **Type consistency:** property/signal names match across tasks — `xyzApi.{busy,errorMessage,
  inboxItems,subscriptions}`, signals `{inboxLoaded,subscriptionsLoaded,sessionExpired}`,
  invokables `fetchInbox()`/`fetchSubscriptions()`; pages expose `mySubsRequested` /
  `tabSelected(int)`; `BelleTabBar` exposes `activeIndex` + `tabSelected(int)`; `BelleHeader`
  adds `actionIconSource`/`actionOn`/`actionClicked`. Shaped map keys (`coverUrl`, `title`,
  `desc`, `durationText`, `whenText`, `playCount`, `commentCount`, `name`, `hostsText`,
  `avatarUrls`, `often`) are consistent between C++ producers and QML consumers.
```
