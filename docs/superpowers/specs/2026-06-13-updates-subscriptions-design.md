# M2 — Updates + Subscriptions (native content client)

Status: approved 2026-06-13. Source: Claude Design handoff bundle `xyz-for-symbian-belle`
(`screens-updates.jsx`, `screens-subs.jsx`, `belle.css`, screenshots), official API via
ultrazg/xyz docs (`localhost:23020`) and Go source (`github.com/ultrazg/xyz`).

## Context

M1 shipped SMS login on a native Qt + qjson foundation (`AuthClient`, `auth` context
property; token persisted in `StorageManager`). M2 builds the first two content screens of
the 小宇宙 client — **Updates** (the 订阅-tab landing feed) and **Subscriptions** (我的订阅,
grid + list) — and the bottom tab bar that frames them. It introduces the reusable native
**content** client the rest of the app (episode/podcast detail, player, search) will build on.

Decisions locked during brainstorming:
- **Data source: direct official API** (`api.xiaoyuzhoufm.com`), consistent with M1 auth.
  `XYZ_API_BASE` env override for a local mock (override expects *official-shaped* endpoints,
  not the ultrazg proxy whose routes/bodies differ).
- **Cover art: real thumbnails** from the API, loaded by QML `Image` over the engine's
  existing `SslIgnoringNam` factory.
- **Landing: Updates.** Post-login and boot-with-token go to Updates; the existing account
  screen becomes the "person" tab.

## API (official, from ultrazg/xyz Go source)

Host `https://api.xiaoyuzhoufm.com`, all **POST**, JSON. Auth via `x-jike-access-token`
header (the value persisted at login). Content host needs the **iOS-app** header set — a
*different* set than the auth host's browser headers, so `AuthClient`'s headers are not reused.

| Screen | Endpoint | Body |
|---|---|---|
| Updates | `/v1/inbox/list` | `{"limit":"20"}` (+ optional `loadMoreKey:{pubDate,id}` — pagination deferred) |
| Subscriptions | `/v1/subscription/list` | `{"limit":"20","sortOrder":"desc","sortBy":"subscribedAt"}` |

iOS-app headers (from `handlers/inbox.go` / `handlers/subscription.go`):
`User-Agent: Xiaoyuzhou/2.57.1 (build:1576; iOS 17.4.1)`, `Market: AppStore`,
`App-BuildNo: 1576`, `OS: ios`, `Manufacturer: Apple`, `BundleID: app.podcast.cosmos`,
`Model: iPhone14,2`, `app-permissions: 4`, `Accept: */*`, `Content-Type: application/json`,
`App-Version: 2.57.1`, `OS-Version: 17.4.1`, `Accept-Language: zh-Hans-CN;q=1.0, zh-Hant-TW;q=0.9`,
`Local-Time: <ISO8601 now>`, `Timezone: Asia/Shanghai`, `x-jike-access-token: <token>`.

Response shape: `{ code, msg, data: { data: [ … ], loadMoreKey? } }`. Items carry `type`
("EPISODE"/"PODCAST"), `image.{thumbnailUrl,smallPicUrl,…}`, plus per-type fields below.

- HTTP **401** = unauthenticated / token expired → treat as session expiry.

## Architecture

### `src/XyzApiClient.{h,cpp}` (new) — `xyzApi` context property

Mirrors the `AuthClient` pattern: one `QNetworkAccessManager`, a single in-flight
`QNetworkReply`, a 15s `QTimer`, per-reply `ignoreSslErrors()`, HTTP status from
`QNetworkRequest::HttpStatusCodeAttribute`, body parsed with `QJson::Parser`. A new request
aborts the active one (navigation cancels a stale fetch) — single shared `busy`/`errorMessage`
is fine because only one page is active at a time. Holds `StorageManager*` to read the token.

```cpp
class XyzApiClient : public QObject {
  Q_OBJECT
  Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
  Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY errorMessageChanged)
  Q_PROPERTY(QVariantList inboxItems READ inboxItems NOTIFY inboxLoaded)
  Q_PROPERTY(QVariantList subscriptions READ subscriptions NOTIFY subscriptionsLoaded)
public:
  explicit XyzApiClient(StorageManager *storage, QObject *parent = 0);
  Q_INVOKABLE void fetchInbox();
  Q_INVOKABLE void fetchSubscriptions();
signals:
  void busyChanged(); void errorMessageChanged();
  void inboxLoaded(); void subscriptionsLoaded(); void sessionExpired();
private slots:
  void onReplyFinished(); void onTimeout(); void onSslErrors(const QList<QSslError> &);
private:
  enum RequestType { NoneRequest, InboxRequest, SubscriptionsRequest };
  // contentBase(), applyContentHeaders(req), startPost(type, path, body),
  // abortActiveRequest(), shapeInboxItem(map), shapeSubscription(map),
  // relativeTime(isoString), m_storage, m_nam, m_reply, m_timeout, m_busy,
  // m_errorMessage, m_requestType, m_inboxItems, m_subscriptions
};
```

- `contentBase()` → `qgetenv("XYZ_API_BASE")` else `https://api.xiaoyuzhoufm.com`.
- `onReplyFinished`: 401 → `sessionExpired` (no errorMessage); other non-2xx → `errorMessage`
  (from body `toast`/`msg`/`message`, else `Request failed (<status>)`); 2xx → parse,
  shape items, set the matching property, emit the matching `*Loaded`.

### Data shaping (C++ → flat `QVariantMap` per item)

QML 1.1 can't do date/number formatting in bindings, so the client emits delegate-ready maps.
Lists are exposed as `QVariantList`; QML reads `modelData.<field>`.

- **Inbox item** (episode):
  - `coverUrl` ← episode `image.thumbnailUrl` || `image.smallPicUrl` || podcast image
  - `title` ← `title`
  - `desc` ← `description`
  - `durationText` ← `duration` (sec) → round to minutes → `"<n> min"`
  - `whenText` ← `pubDate` (ISO) → relative ("1h ago" / "16h ago" / "2d ago")
  - `playCount` ← `playCount` (string)
  - `commentCount` ← `commentCount`, capped to `"99+"` when > 99
- **Subscription** (podcast):
  - `coverUrl` ← `image.smallPicUrl` || `image.thumbnailUrl`
  - `name` ← `title`
  - `hostsText` ← join `podcasters[].nickname` (max 2) with ", "
  - `whenText` ← `latestEpisodePubDate` → relative
  - `often` ← `subscriptionOftenPlayed` (bool; absent → false)
  - `avatarUrls` ← `podcasters[].avatar.picture.smallPicUrl` (max 2)

### `src/main.cpp` (modified)

Instantiate `XyzApiClient xyzApi(&storage);` and `setContextProperty("xyzApi", &xyzApi)`
alongside the existing properties. No change to `SslIgnoringNam`/factory — QML `Image` loads
already route through it, so remote HTTPS covers load and tolerate the stale CA store.

## QML

### `qml/BelleTabBar.qml` (new)
Custom 56px glossy bottom bar (`belle.css .toolbar`): gradient `#2a2a30→#1d1d22→#141417`, 1px
black top border, inset top highlight. Four equal tab slots with 1px dividers; **placeholder**
glyphs (compass / search / headphones / person); active tab tinted `accentBright` with a 5px
accent dot; the "expand options" handle nub centered on the top edge.
`property int activeIndex`, `signal tabSelected(int index)`. Throwaway placeholder SVGs in
`qml/gfx/` (per the user: don't invest in real icons yet).

### `qml/UpdatesPage.qml` (new)
`hidesToolBar: true` (draws its own `BelleTabBar`). Layout top→bottom:
- **Title bar** (`belle.css .up-titlebar`): glossy chrome gradient, 24px/800 "Updates" left,
  "My Subscriptions" violet pill (`.mysubs-btn`) right → `signal mySubsRequested`.
- **`ListView`** `model: xyzApi.inboxItems`, delegate (`belle.css .up-item`): 64px cover
  `Image`, body with 2-line title (`.up-title2`) + 2-line desc (`.up-desc`); meta row
  (`durationText · whenText · ⌾playCount · ⌾commentCount`); action row with placeholder
  glyphs (queue / comment+count / dots) + 48px play circle (`.up-play`) — all non-functional
  placeholders (no player yet).
- **`BelleTabBar`** `activeIndex: 2`.
- States: `BusyIndicator` while `xyzApi.busy`; error label bound to `xyzApi.errorMessage`;
  empty hint when loaded with 0 items.
- Fetches `xyzApi.fetchInbox()` on first activation.

### `qml/SubscriptionsPage.qml` (new)
`hidesToolBar: true`. `BelleHeader` (back + "Subscriptions" + grid/list toggle action).
`property string viewMode: "grid"`, toggled by the header action (icon = list when in grid,
grid when in list). Content swaps:
- **Grid** (`.subs-grid`): 3-col `GridView` of square cover `Image`s (3px gap); "Often" badge
  (`.subs-badge`) on items where `often`.
- **List**: static search field (`.subs-search`, placeholder, non-functional); static
  **Starred empty-state** (`.starred`: cluster + hint + "Add" placeholder — matches the
  screenshot); "All Subscriptions" subhead (+ sort placeholder); rows (`.subs-row`): 52px
  cover, `name`, avatar stack (up to 2 round `Image`s) + `hostsText · whenText`, more-dots
  placeholder.
- **`BelleTabBar`** `activeIndex: 2`. Back → Updates.
- States: busy / error / empty as above. Fetches `xyzApi.fetchSubscriptions()` on first
  activation.

### `qml/BelleHeader.qml` (modified, additive)
Optional trailing action, rendered only when set: `property string actionIconSource: ""`,
`property bool actionOn: false` (accent tint when true), `signal actionClicked`. Existing
title/back behavior unchanged.

### `qml/AppWindow.qml` (modified)
- Add `UpdatesPage`, `SubscriptionsPage` instances.
- `initialPage: isLoggedIn() ? updatesPage : loginPage`.
- `VerifyCodePage.onLoggedIn` → `pageStack.clear(); push(updatesPage)`.
- `UpdatesPage.onMySubsRequested` → `push(subscriptionsPage)`.
- Centralized tab routing (`window.handleTab(index)`), wired from each page's
  `BelleTabBar.tabSelected`: 0/1 (compass/search) → no-op; 2 (headphones) → ensure Updates is
  current (pop back to it); 3 (person) → push `homePage` (the account screen, keeps sign-out).
- `HomePage` stays as the account page; its `onSignedOut` → `clear(); push(loginPage)`.
- `XyzApiClient.onSessionExpired` (via a `Connections` on `xyzApi`) → `auth.logout()` →
  `clear(); push(loginPage)`.

### `qml/qml.qrc`, `Xyz.pro` (modified)
Register `UpdatesPage.qml`, `SubscriptionsPage.qml`, `BelleTabBar.qml`, the placeholder tab
SVGs (qrc); add `src/XyzApiClient.{h,cpp}` to `Xyz.pro` SOURCES/HEADERS.

## Error handling
- Network / timeout / non-2xx → centered `errorMessage`.
- **401 → `sessionExpired` → `auth.logout()` → login page.**
- Empty list → friendly hint.
- SSL errors ignored (stale CA), same stance as the rest of the app.
- Cover/avatar `Image`s set a `sourceSize` cap; `ListView`/`GridView` lazy-instantiate
  delegates, so memory stays bounded on the C7 even with 20+ covers.

## Files
- **New**: `src/XyzApiClient.h`, `src/XyzApiClient.cpp`, `qml/UpdatesPage.qml`,
  `qml/SubscriptionsPage.qml`, `qml/BelleTabBar.qml`, placeholder tab SVGs under `qml/gfx/`.
- **Modified**: `src/main.cpp`, `qml/AppWindow.qml`, `qml/BelleHeader.qml`, `qml/qml.qrc`,
  `Xyz.pro`, `qml/js/Theme.js` (any new metric constants), `docs/API_NOTES.md` (content
  endpoints + headers + `XYZ_API_BASE`), `docs/DESIGN_SYSTEM.md` (Updates/Subs/tab-bar
  promoted from "later"), `tasks/plan.md`, `docs/PLAN.md`, `docs/DEVICE_NOTES.md` (remote
  image / api-host TLS findings).

## Non-goals (first cut)
No audio/player → action buttons (play/queue/comment) and the **mini-player are omitted**
(no faked "now playing"). No pagination (first 20 inbox / first subscriptions page). No real
search, sort, star/manage/add. Starred section = static empty-state (no
`/v1/subscription-star/list` fetch yet). Episode/podcast detail, comments, Discover/Search
tabs — later milestones (Discover/Search tab buttons are inert no-ops).

## Verification
1. `scripts/build-simulator.ps1 -Config Debug` green (force qrc rebuild: delete
   `build-simulator/debug/rcc/qrc_qml.cpp` + `obj/qrc_qml.o` first).
2. **Live read (safe — no SMS)**: with the real stored token, launch and confirm login →
   Updates renders real cards with covers; "My Subscriptions" → grid renders covers; toggle →
   list renders rows + avatars; back → Updates; person tab → Account → sign out.
   `inbox/list` & `subscription/list` are read-only, so live calls are safe to run in the sim.
3. **Fallback (no token / offline)**: local mock returning official-shaped JSON via
   `XYZ_API_BASE`; same drive-through.
4. **Error path**: simulate non-2xx / 401 (mock) → error label / forced re-login.
5. Record remote-image loading + api-host TLS findings in `docs/DEVICE_NOTES.md` (dated).

## Risks
- **iOS header strictness** — proven by ultrazg/xyz (same headers) and by M1 reaching the
  sibling host over TLS 1.2; if a call 403s, the `XYZ_API_BASE` mock unblocks UI work.
- **Remote image memory on the C7** — bounded by lazy delegates + `sourceSize`; watch
  `memoryMonitor` during the live test; fall back to smaller `thumbnailUrl` if needed.
- **Token expiry (401)** mid-session — handled by `sessionExpired` re-login; refresh-token
  flow stays deferred (documented in `API_NOTES.md`).
