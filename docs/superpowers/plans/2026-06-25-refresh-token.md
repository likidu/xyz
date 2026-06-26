# Refresh-Token Logic Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On a `401`, silently refresh the access token using the stored refresh token and retry the failed request, so the user is no longer logged out mid-session (e.g. while an episode plays).

**Architecture:** All logic lives in `XyzApiClient` (C++). When a content request returns `401`, the client POSTs to `/app_auth_tokens.refresh` (content host, both tokens in headers, empty body), stores the new tokens, and re-sends the original request. A one-shot guard (`m_refreshAttempted`) caps this to a single refresh per request to prevent loops. Only if the refresh itself fails does it emit the existing `sessionExpired` signal (which QML already turns into logout → login page). No QML, `AuthClient`, or `StorageManager` changes.

**Tech Stack:** Qt 4.7 / C++ (QtNetwork), QJson (bundled `parser.h`/`serializer.h`), SQLite via `StorageManager`. Build via MinGW + qmake (`scripts/build-simulator.ps1`). Verification via the PowerShell HTTP mock (`scripts/mock-content.ps1`) + Qt Simulator.

## Global Constraints

- **No C++ unit-test harness exists** in this project, and none is to be added. Per-task verification of C++ changes is **a clean compile** via `scripts/build-simulator.ps1`; behavioral correctness is proven by the mock-driven simulator run in Task 4.
- **Source of truth for the API** is the ultrazg/xyz Go proxy at `C:\Users\liya\Repos\xyz-go` (`handlers/token.go`, `doc/docs/refreshToken.md`). The refresh endpoint returns new tokens in the **response body** (`x-jike-access-token` / `x-jike-refresh-token` keys); parse body first, fall back to response headers.
- **Refresh endpoint:** `POST {content-base}/app_auth_tokens.refresh`, empty body, headers `x-jike-access-token` + `x-jike-refresh-token`. Content base is `https://api.xiaoyuzhoufm.com`, overridable via env `XYZ_API_BASE`.
- **Token storage keys** (already in use, do not rename): `auth.accessToken`, `auth.refreshToken`.
- **Match existing style:** `QString::fromLatin1(...)` literals, `QLatin1String` storage keys, raw-header spoofing via `applyContentHeaders`, tolerant parsing like `AuthClient`. Init-list order must match member declaration order (avoid `-Wreorder`).

---

## File Structure

- **Modify** `scripts/mock-content.ps1` — add a `/app_auth_tokens.refresh` handler and a one-shot `401` gate on content endpoints so the simulator exercises 401 → refresh → retry. Log each request line.
- **Modify** `src/XyzApiClient.h` — add `RefreshRequest` enum value, replay/guard members, and new private method declarations.
- **Modify** `src/XyzApiClient.cpp` — extract a shared `sendRequest` helper (pure refactor), then add refresh + retry logic, token parsing, and refresh-aware timeout handling.
- **Temporary, not committed** `qml/TestRefreshPage.qml` + a one-line `AppWindow.qml` `initialPage` swap — used only in Task 4 to drive the flow without the login UI, then reverted.

---

## Task 1: Extend the mock to drive 401 → refresh → retry

**Files:**
- Modify: `scripts/mock-content.ps1`

**Interfaces:**
- Produces: a mock that (a) returns HTTP `401` for content endpoints (`inbox`/`subscription`/`episode`/`comment`) until the first refresh, (b) answers `POST /app_auth_tokens.refresh` with `200` and new tokens in the body, then (c) returns normal `200` data for content. Each request is logged as `METHOD path -> status`.

- [ ] **Step 1: Add a refresh-state flag and request logging before the loop**

In `scripts/mock-content.ps1`, immediately after the `$wav = New-SilenceWav` line (line ~69) and before `while ($listener.IsListening) {`, add:

```powershell
# Refresh-flow test state: content endpoints answer 401 until the app has
# refreshed once via /app_auth_tokens.refresh, mimicking an expired access token.
$script:tokenRefreshed = $false
```

- [ ] **Step 2: Handle the refresh endpoint and the one-shot 401 gate inside the loop**

Inside `while ($listener.IsListening) { ... }`, right after `$path = $ctx.Request.Url.AbsolutePath`, insert:

```powershell
$method = $ctx.Request.HttpMethod

# Token refresh: return new tokens in the BODY (matches the real upstream, which
# the ultrazg/xyz proxy reads from the response body), and flip the gate open.
if ($path -like "*app_auth_tokens.refresh*") {
  $refresh = @{ "x-jike-access-token"="NEW-ACCESS-TOKEN";
                "x-jike-refresh-token"="NEW-REFRESH-TOKEN"; success=$true } | ConvertTo-Json
  $script:tokenRefreshed = $true
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($refresh)
  $ctx.Response.ContentType = "application/json; charset=utf-8"
  $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
  $ctx.Response.Close()
  Write-Host "$method $path -> 200 (refresh)"
  continue
}

# Simulate an expired access token: every content endpoint 401s until refreshed.
$isContent = ($path -like "*inbox*") -or ($path -like "*subscription*") -or
             ($path -like "*episode*") -or ($path -like "*comment*")
if ($isContent -and -not $script:tokenRefreshed) {
  $ctx.Response.StatusCode = 401
  $err = @{ code=401; msg="UNAUTHORIZED" } | ConvertTo-Json
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($err)
  $ctx.Response.ContentType = "application/json; charset=utf-8"
  $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
  $ctx.Response.Close()
  Write-Host "$method $path -> 401 (gated)"
  continue
}
```

- [ ] **Step 3: Log the served content responses**

At the very end of the loop body, replace the existing `$ctx.Response.Close()` (the one after the content JSON write, line ~87) so it also logs. Change:

```powershell
  $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
  $ctx.Response.Close()
}
```

to:

```powershell
  $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
  $ctx.Response.Close()
  Write-Host "$method $path -> 200"
}
```

- [ ] **Step 4: Smoke-test the mock by hand**

Run the mock in one shell:

```bash
pwsh -File scripts/mock-content.ps1
```

In another shell, verify the sequence with curl:

```bash
curl -s -o NUL -w "%{http_code}\n" -X POST http://localhost:8099/v1/inbox/list           # expect 401
curl -s -o NUL -w "%{http_code}\n" -X POST http://localhost:8099/app_auth_tokens.refresh  # expect 200
curl -s -o NUL -w "%{http_code}\n" -X POST http://localhost:8099/v1/inbox/list           # expect 200
```

Expected: `401`, then `200`, then `200`. Mock console shows the three logged lines. Stop the mock (Ctrl+C).

- [ ] **Step 5: Commit**

```bash
git add scripts/mock-content.ps1
git commit -m "test(mock): drive 401 -> refresh -> retry for refresh-token verification"
```

---

## Task 2: Extract a shared `sendRequest` helper (pure refactor)

**Files:**
- Modify: `src/XyzApiClient.h`
- Modify: `src/XyzApiClient.cpp:174-225` (`startPost`, `startGet`)

**Interfaces:**
- Produces: `void sendRequest(RequestType type, bool isPost, const QString &path, const QVariantMap &body, bool withRefreshHeader = false)` — issues the network request, wires `finished`/`sslErrors`, and starts the 15s timeout. The `withRefreshHeader` flag (unused until Task 3) adds the `x-jike-refresh-token` request header for the refresh call. `startPost`/`startGet` now delegate to it. **Behavior is unchanged** by this task.

- [ ] **Step 1: Declare `sendRequest` in the header**

In `src/XyzApiClient.h`, in the `private:` section just below the existing `void startGet(RequestType type, const QString &path);` (line 67), add:

```cpp
    // Shared issue-path for startPost/startGet/startRefresh/resendReplay.
    void sendRequest(RequestType type, bool isPost, const QString &path,
                     const QVariantMap &body, bool withRefreshHeader = false);
```

- [ ] **Step 2: Implement `sendRequest` and reduce `startPost`/`startGet` to delegations**

In `src/XyzApiClient.cpp`, replace the whole block from `void XyzApiClient::startPost(...)` through the end of `void XyzApiClient::startGet(...)` (lines 174-225) with:

```cpp
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
        QJson::Serializer serializer;
        const QByteArray payload = serializer.serialize(body);
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
    sendRequest(type, true, path, body);
}

void XyzApiClient::startGet(RequestType type, const QString &path)
{
    sendRequest(type, false, path, QVariantMap());
}
```

- [ ] **Step 3: Build and confirm a clean compile**

Run:

```bash
pwsh -File scripts/build-simulator.ps1 -Config Debug
```

Expected: ends with `[INFO] Build succeeded:` and a path to `Xyz.exe`, no compile errors.

- [ ] **Step 4: Commit**

```bash
git add src/XyzApiClient.h src/XyzApiClient.cpp
git commit -m "refactor(api): extract sendRequest helper from startPost/startGet"
```

---

## Task 3: Implement reactive refresh + silent retry

**Files:**
- Modify: `src/XyzApiClient.h`
- Modify: `src/XyzApiClient.cpp` (constructor, `startPost`/`startGet`, `onReplyFinished`, `onTimeout`; add `startRefresh`, `resendReplay`, `parseRefreshTokens`)

**Interfaces:**
- Consumes: `sendRequest(...)` from Task 2; the `RefreshRequest` enum value; storage keys `auth.accessToken` / `auth.refreshToken`; the existing `sessionExpired()` signal.
- Produces: internal refresh behavior. No new public/QML surface.

- [ ] **Step 1: Add enum value, members, and method declarations in the header**

In `src/XyzApiClient.h`, change the enum (line 63-64) from:

```cpp
    enum RequestType { NoneRequest, InboxRequest, SubscriptionsRequest,
                       EpisodeRequest, CommentsRequest, MoreCommentsRequest };
```

to:

```cpp
    enum RequestType { NoneRequest, InboxRequest, SubscriptionsRequest,
                       EpisodeRequest, CommentsRequest, MoreCommentsRequest,
                       RefreshRequest };
```

Add these declarations right below the new `sendRequest` declaration (added in Task 2) in the `private:` methods area:

```cpp
    // One-shot token refresh on 401, then re-send the request that failed.
    void startRefresh();
    void resendReplay();
    void parseRefreshTokens(const QByteArray &payload,
                            const QByteArray &hdrAccess, const QByteArray &hdrRefresh,
                            QString &outAccess, QString &outRefresh) const;
```

Add these members directly after `RequestType m_requestType;` (line 86):

```cpp
    // Replay state: remember the in-flight request so it can be re-sent after a
    // refresh; m_refreshAttempted caps the refresh to once per logical request.
    RequestType m_replayType;
    QString m_replayPath;
    QVariantMap m_replayBody;
    bool m_replayIsPost;
    bool m_refreshAttempted;
```

- [ ] **Step 2: Initialize the new members (declaration order)**

In `src/XyzApiClient.cpp`, change the constructor initializer list (lines 41-49) from:

```cpp
    , m_reply(0)
    , m_busy(false)
    , m_requestType(NoneRequest)
    , m_commentsTotal(0)
```

to:

```cpp
    , m_reply(0)
    , m_busy(false)
    , m_requestType(NoneRequest)
    , m_replayType(NoneRequest)
    , m_replayIsPost(false)
    , m_refreshAttempted(false)
    , m_commentsTotal(0)
```

- [ ] **Step 3: Record replay state and reset the guard when a user request starts**

In `src/XyzApiClient.cpp`, replace the two delegating bodies written in Task 2:

```cpp
void XyzApiClient::startPost(RequestType type, const QString &path, const QVariantMap &body)
{
    sendRequest(type, true, path, body);
}

void XyzApiClient::startGet(RequestType type, const QString &path)
{
    sendRequest(type, false, path, QVariantMap());
}
```

with:

```cpp
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
```

- [ ] **Step 4: Capture token headers and handle refresh/401 in `onReplyFinished`**

In `src/XyzApiClient.cpp` `onReplyFinished`, replace this block (lines 253-261):

```cpp
    const QByteArray payload = reply->readAll();
    const int statusCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    reply->deleteLater();

    if (statusCode == 401) {
        setBusy(false);
        emit sessionExpired();
        return;
    }
```

with:

```cpp
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
```

- [ ] **Step 5: Make refresh timeouts log out (spec-consistent)**

In `src/XyzApiClient.cpp`, replace `onTimeout` (lines 364-370):

```cpp
void XyzApiClient::onTimeout()
{
    abortActiveRequest();
    m_requestType = NoneRequest;
    setErrorMessage(QString::fromLatin1("Request timed out."));
    setBusy(false);
}
```

with:

```cpp
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
```

- [ ] **Step 6: Implement `parseRefreshTokens`**

In `src/XyzApiClient.cpp`, add this definition immediately after `onTimeout` (before `onSslErrors`):

```cpp
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
```

- [ ] **Step 7: Build and confirm a clean compile**

Run:

```bash
pwsh -File scripts/build-simulator.ps1 -Config Debug
```

Expected: ends with `[INFO] Build succeeded:` and the `Xyz.exe` path, no errors or `-Wreorder` warnings.

- [ ] **Step 8: Commit**

```bash
git add src/XyzApiClient.h src/XyzApiClient.cpp
git commit -m "feat(api): refresh access token on 401 and retry the failed request"
```

---

## Task 4: Integration verification on the simulator

**Files:**
- Temporary (do NOT commit): `qml/TestRefreshPage.qml`
- Temporary (revert before finishing): one-line `initialPage` swap in `qml/AppWindow.qml`

**Interfaces:**
- Consumes: the built `Xyz.exe`, the mock from Task 1, env `XYZ_API_BASE`.
- Produces: evidence (mock request log + on-screen result) that 401 → refresh → retry succeeds without logging out, and that a dead refresh token still logs out.

- [ ] **Step 1: Create a temporary test page that drives the flow without the login UI**

Create `qml/TestRefreshPage.qml`:

```qml
import QtQuick 1.1
import com.nokia.symbian 1.1

Page {
    id: testPage
    Component.onCompleted: {
        // Seed tokens so applyContentHeaders sends one and a refresh is possible.
        storage.setValue("auth.accessToken", "seed-access");
        storage.setValue("auth.refreshToken", "seed-refresh");
        xyzApi.fetchInbox();
    }
    Connections {
        target: xyzApi
        onInboxLoaded: status.text = "INBOX LOADED: " + xyzApi.inboxItems.length
                                     + " | token=" + storage.value("auth.accessToken", "")
        onSessionExpired: status.text = "SESSION EXPIRED (logged out)"
        onErrorMessageChanged: if (xyzApi.errorMessage.length)
                                   status.text = "ERROR: " + xyzApi.errorMessage
    }
    Text {
        id: status
        anchors.centerIn: parent
        width: parent.width - 40
        wrapMode: Text.WordWrap
        font.pixelSize: 18
        color: "white"
        text: "running..."
    }
}
```

- [ ] **Step 2: Point the app at the test page**

In `qml/AppWindow.qml`, find the `initialPage:` assignment and temporarily change it to the test page. Note the original value first so Step 7 can restore it. For example, if it reads `initialPage: loginPage`, change to:

```qml
    initialPage: Qt.resolvedUrl("TestRefreshPage.qml")
```

- [ ] **Step 3: Rebuild with the temporary page**

```bash
pwsh -File scripts/build-simulator.ps1 -Config Debug
```

Expected: `[INFO] Build succeeded:`.

- [ ] **Step 4: Start the mock, then launch the app against it**

Shell A:

```bash
pwsh -File scripts/mock-content.ps1
```

Shell B (set the base URL in the same process that launches the app):

```bash
pwsh -NoProfile -Command "$env:XYZ_API_BASE='http://localhost:8099'; & build-simulator/debug/Xyz.run.ps1"
```

- [ ] **Step 5: Confirm the happy path (no logout)**

Expected on screen: `INBOX LOADED: 2 | token=NEW-ACCESS-TOKEN` (the count comes from the mock's two inbox items; the token proves the stored access token was replaced).

Expected in the mock console (Shell A), in order:

```
POST /v1/inbox/list -> 401 (gated)
POST /app_auth_tokens.refresh -> 200 (refresh)
POST /v1/inbox/list -> 200
```

This proves: the 401 triggered a refresh, the new token was stored, and the original request was silently retried and succeeded — no `SESSION EXPIRED`.

- [ ] **Step 6: Confirm the negative path (dead refresh token still logs out)**

Stop the app. Edit `scripts/mock-content.ps1` temporarily so the refresh endpoint returns 401 instead of 200 — change the refresh handler's start to:

```powershell
if ($path -like "*app_auth_tokens.refresh*") {
  $ctx.Response.StatusCode = 401
  $ctx.Response.Close()
  Write-Host "$method $path -> 401 (refresh denied)"
  continue
}
```

Restart the mock and relaunch the app (Step 4). Expected on screen: `SESSION EXPIRED (logged out)`. Mock log shows `inbox -> 401`, `app_auth_tokens.refresh -> 401`. Then **revert this mock edit** (`git checkout scripts/mock-content.ps1` keeps the Task 1 version).

- [ ] **Step 7: Revert the temporary test scaffolding**

```bash
git checkout qml/AppWindow.qml
rm qml/TestRefreshPage.qml
```

Confirm `git status` shows no `TestRefreshPage.qml` and no `AppWindow.qml` change. Rebuild once more to confirm the real app still compiles:

```bash
pwsh -File scripts/build-simulator.ps1 -Config Debug
```

Expected: `[INFO] Build succeeded:`.

- [ ] **Step 8: Record the device/platform observation**

Append a dated entry to `docs/DEVICE_NOTES.md` (`## 2026-06-25 — Refresh-token 401 retry`) noting: the mock-verified 401 → refresh → retry path works on the simulator, new tokens are persisted to the `kv` table, and the negative path still logs out. Commit:

```bash
git add docs/DEVICE_NOTES.md
git commit -m "docs(notes): record refresh-token 401 retry simulator verification"
```

---

## Self-Review

**1. Spec coverage:**
- Reactive refresh on 401 → Task 3 Step 4. ✅
- Silent retry of the failed request → `resendReplay` (Task 3 Steps 3-4). ✅
- New tokens parsed body-first, header-fallback → `parseRefreshTokens` (Task 3 Step 6). ✅
- Both tokens in refresh request headers → `withRefreshHeader` in `sendRequest` (Task 2 Step 2) + `startRefresh` (Task 3 Step 3). ✅
- One-shot guard against 401→refresh loops → `m_refreshAttempted` (Task 3 Steps 1-4). ✅
- Continuous busy state → `setBusy(false)` only on terminal outcomes (Task 3 Step 4). ✅
- Refresh failure → existing `sessionExpired`/logout, no new UI → Task 3 Steps 4-5; no QML change. ✅
- Out of scope honored: no proactive refresh, no public `refreshToken()`. ✅
- Verification via `XYZ_API_BASE` mock incl. negative path → Task 1 + Task 4. ✅

**2. Placeholder scan:** No TBD/TODO; every code step shows complete code; commands have expected output. ✅

**3. Type consistency:** `sendRequest(RequestType, bool, const QString&, const QVariantMap&, bool=false)`, `startRefresh()`, `resendReplay()`, `parseRefreshTokens(const QByteArray&, const QByteArray&, const QByteArray&, QString&, QString&) const`, `RefreshRequest` enum, and members `m_replayType/m_replayPath/m_replayBody/m_replayIsPost/m_refreshAttempted` are used identically across the header (Task 3 Step 1) and the .cpp (Task 3 Steps 2-6). Init-list order (`m_requestType, m_replayType, m_replayIsPost, m_refreshAttempted, m_commentsTotal`) matches declaration order. ✅
