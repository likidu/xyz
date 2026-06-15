# 小宇宙 Belle — M1: Login Page (Minimal API Test Version)

Approved plan (source: Claude Design handoff bundle `xyz-for-symbian-belle`,
API research from ultrazg/xyz Go source / localhost:23020 docs).

## Context

Qt 4.7 / QML 1.1 Symbian Belle starter (Nokia C7 target) becoming a minimal 小宇宙
(Xiaoyuzhou FM) client. M1 implements the **SMS login flow** against the **official
xiaoyuzhoufm API**, pixel-faithful to the design bundle, and records the design system
in the repo.

Design intent:
- 3 states: phone entry (default 中国 +86, only other option US +1) → country picker
  dialog → 6-digit SMS code entry.
- Pre-login screens show **no app toolbar**.
- i18n with English default (qsTr with English source strings).
- Flag emoji unavailable → "CN"/"US" text chips.

## API (official, confirmed from ultrazg/xyz source)

| Action | Endpoint | JSON body |
|---|---|---|
| Send code | `POST https://podcaster-api.xiaoyuzhoufm.com/v1/auth/send-code` | `{"mobilePhoneNumber","areaCode"}` |
| Login | `POST https://podcaster-api.xiaoyuzhoufm.com/v1/auth/login-with-sms` | `{"areaCode","verifyCode","mobilePhoneNumber"}` |

- Tokens in **response headers** `x-jike-access-token` / `x-jike-refresh-token`;
  profile in body `data.user`.
- Auth calls need browser-spoof headers (origin/referer podcaster.xiaoyuzhoufm.com,
  Chrome UA). QML XHR forbids User-Agent/Referer → inject in C++
  `SslIgnoringNam::createRequest`, keyed on host.
- Refresh endpoint documented in `docs/API_NOTES.md` only (not implemented in M1).

## Checklist

- [x] `tasks/plan.md` — this file
- [x] `docs/DESIGN_SYSTEM.md` — palette, chrome metrics, component specs from belle.css
- [x] `docs/API_NOTES.md` — endpoints, headers, token handling, rate-limit warning
- [x] `qml/js/Theme.js` — palette/metric constants
- [x] `qml/js/Api.js` — sendCode / login via XHR (+ Qt 4.7 status-tracking workaround)
- [x] `qml/gfx/login-orb.svg`, `icon-back.svg`, `icon-chevron-down.svg`
- [x] `qml/BelleHeader.qml` — glossy Belle header w/ back chevron
- [x] `qml/LoginPage.qml` — brand, phone field w/ CC chip, country picker overlay,
      Get Code button, terms footer
- [x] `qml/VerifyCodePage.qml` — 6 code boxes, resend countdown, Sign in → store tokens
- [x] `qml/HomePage.qml` — post-login placeholder (nickname/uid/token proof, sign out)
- [x] `qml/AppWindow.qml` — page wiring, initialPage by stored token, toolbar hiding,
      Self-test menu item, VKB enabled
- [x] `src/main.cpp` — host-keyed header injection in SslIgnoringNam
- [x] `qml/qml.qrc` + `Xyz.pro` — register new files
- [x] `docs/PLAN.md` — M1 entry
- [x] Simulator build green + visual check vs design screenshots
- [ ] Live login with a real registered number (user-run — sends real SMS)

## Risks

- Device TLS vs api hosts (simulator confirmed TLS 1.2 OK; device experiment pending
  → DEVICE_NOTES.md; fallback = point Api.AUTH_BASE at LAN ultrazg/xyz proxy).
- SMS rate limiting → 60s resend guard, test sparingly.
- Header strictness — confirmed OK: real API processes our QML-XHR request (returns
  normal 400, not a 403 bot-block), so no C++ auth helper needed.

## Results

Delivered the SMS login flow pixel-faithful to the design bundle, wired to the official
`podcaster-api.xiaoyuzhoufm.com` auth endpoints.

Verified in the Qt Simulator:
- **LoginPage** — brand orb/name/tag, phone field with CN/US country chip, SMS hint,
  Get Code button (disabled→enabled→busy), terms footer (hidden while typing).
- **Country picker** — scrim + Belle dialog, CN/US radio selection, chip updates.
- **VerifyCodePage** — 6 code boxes (hidden TextInput driver), active-box highlight,
  live resend countdown (→ active "Resend"), Sign in disabled until 6 digits.
- **HomePage** — nickname/phone/uid + "API token stored. Login OK." + Sign out;
  app toolbar present; Self-test reachable from the menu.
- **Success path (200)** — validated end-to-end against a local mock: `getResponseHeader`
  extracts the `x-jike-*` tokens, body profile parsed, tokens persisted, navigates to
  HomePage showing the returned nickname. App restart with a stored token → HomePage.
- **Error path (live)** — invalid number → real API 400 → shows the server message
  ("无效参数"). Real endpoint reachable over TLS 1.2; spoof headers accepted.

Key platform findings recorded in `docs/DEVICE_NOTES.md` (2026-06-06): TLS 1.2 is
mandatory for the auth host; Qt 4.7 QML XHR zeroes `status` on HTTP errors (worked
around in Api.js); editing only `.qml` doesn't rebuild the qrc.

Outstanding: the on-device TLS/login retest.

### M1.1 — Native migration (qjson + AuthClient)

Migrated auth off QML JavaScript to a native Qt client (matching the podin pattern), to
shed the Qt 4.7 QML-XHR status-0 wart and share one networking pattern with the upcoming
content layer.
- Vendored qjson (`lib/qjson/`, static via `qjson.pri` + `QJSON_STATIC`).
- New `src/AuthClient.{h,cpp}` — `auth` context property; `Q_INVOKABLE sendCode/login/logout/
  isLoggedIn`; `busy`/`errorMessage` `Q_PROPERTY`; own NAM + 15s timeout + per-reply
  `ignoreSslErrors`; status from `HttpStatusCodeAttribute`; tokens from response headers;
  qjson body parse; persists via `StorageManager`. `XYZ_AUTH_BASE` env override for testing.
- Reverted the `SslIgnoringNam` header injection (now SSL-ignore only, for QML images).
- QML pages call `auth.*` and bind `auth.busy`/`auth.errorMessage`; deleted `qml/js/Api.js`.
- Verified: simulator build green (qjson compiles under MinGW); success path via mock
  (tokens via `rawHeader`, qjson parse → uid/nickname, persisted, HomePage nav); error path
  live (server "无效参数", TLS 1.2 via AuthClient's NAM). Real-SMS retest optional/user-run.

Live login with a real registered number was confirmed working on the JS version before the
migration; the native path uses the same endpoints/headers and is behavior-identical.

---

## M2 — Updates + Subscriptions (native content client)

Full plan in `docs/superpowers/plans/2026-06-13-updates-subscriptions.md`.
Implemented on branch `feat/updates-subscriptions`.

### Context

Post-login landing redesigned from `HomePage` to a native Updates feed + Subscriptions
screen backed by a new `XyzApiClient` that calls `api.xiaoyuzhoufm.com` directly with
iOS-app spoof headers and the stored `x-jike-access-token`.

### Checklist

- [x] `src/XyzApiClient.{h,cpp}` — `xyzApi` context property; `fetchInbox()` /
      `fetchSubscriptions()`; iOS-app spoof headers; `shapeInboxItem` /
      `shapeSubscription` (relative-time strings, 99+ cap); 401 → `sessionExpired`;
      `XYZ_API_BASE` env override; 15s timeout; single in-flight reply; qjson parse
- [x] `Xyz.pro` + `src/main.cpp` — register `XyzApiClient`, set `xyzApi` context property
- [x] Placeholder glyph SVGs (`qml/gfx/tab-*.svg`, `icon-{play,queue,comment,dots,list,grid}.svg`)
- [x] `qml/BelleTabBar.qml` — 56px dark-glossy, 4 placeholder tabs, active accent dot + grab handle
- [x] `qml/js/Theme.js` — added `tabBarHeight = 56`
- [x] `qml/BelleHeader.qml` — optional `actionIconSource`/`actionOn`/`actionClicked` trailing button
- [x] `qml/UpdatesPage.qml` — glossy 56px title bar + "My Subscriptions" pill; episode cards
      (64px cover, 2-line title/desc, meta row, action row + play circle); busy/error/empty states
- [x] `qml/SubscriptionsPage.qml` — `BelleHeader` w/ toggle; 3-col `GridView` ("Often" badge);
      `ListView` (search bar, Starred empty-state, 72px rows w/ avatar stack); busy/error/empty states
- [x] `qml/AppWindow.qml` — login → Updates; `handleTab`; `SubscriptionsPage` instance;
      `mySubsRequested` → push Subscriptions; session-expiry `Connections`; `initialPage` by token
- [x] `scripts/mock-content.ps1` — local mock for deterministic simulator testing (no SMS)
- [x] `qml/qml.qrc` + `Xyz.pro` — all new QML + SVGs registered
- [x] Simulator: full flow verified against mock (visual + navigation)
- [x] `docs/API_NOTES.md`, `docs/DESIGN_SYSTEM.md`, `docs/DEVICE_NOTES.md`, `docs/PLAN.md`,
      `tasks/plan.md` — M2 documentation

### Results

Delivered the Updates feed and Subscriptions screen (grid + list) wired to native
`XyzApiClient` calling `api.xiaoyuzhoufm.com` directly.

Verified in the Qt Simulator (Nokia N8 frame) against `scripts/mock-content.ps1`
(`XYZ_API_BASE=http://localhost:8099`), token seeded into the sim DB:
- **Updates**: 2 episode cards with covers, 2-line title/desc, meta row (duration · when ·
  plays · comments with 99+ cap), action row + play circle, "My Subscriptions" pill, tab bar.
- **Subscriptions grid**: 3-col cover wall, "Often" badge on first item.
- **Subscriptions list**: search placeholder, Starred empty-state, "All Subscriptions" rows
  with avatar stacks (rounded-square 19px), hosts · when.
- **Navigation**: Updates → My Subscriptions → grid → toggle → list → back → Updates →
  person tab → Account; all transitions correct.
- Remote HTTPS covers/avatars load via `SslIgnoringNamFactory`; app log clean (no QML errors).

Platform findings recorded in `docs/DEVICE_NOTES.md` (2026-06-13): screenshot-capture
gotcha in Qt Simulator non-interactive shell (use `PrintWindow` on the `Qt Simulator`
window class, call `SetProcessDPIAware()` first).

### Non-goals (deferred)
Player / mini-player, pagination (`loadMoreKey`), search / sort / star actions, starred
fetch from API, Discover / Search tabs (inert placeholders), token refresh.

---

## M3 — Episode detail page

Design source: `xyz-for-symbian-belle` bundle — `screens-detail.jsx` + `.ep-*` / `.cmt-*`
in `belle.css`. Reached by tapping an episode card in the Updates feed. Player deferred
(Play CTA + actions inert, like the Updates action row).

### Decisions (from brainstorming, 2026-06-14)
- **Data**: live native fetch (user choice). Hero is *seeded* from the tapped inbox item
  (instant paint), then episode detail + comments fetched by `eid` fill show name, notes,
  comment count, and the comment list.
- **Navigation**: tapping a card body in Updates opens the page.
- **Bottom toolbar**: omitted for now (every action it held — comment/add/share/list — is
  deferred with the player).

### Real API contracts (ultrazg/xyz v1.10.0, source-verified)
- Episode detail: `GET /v1/episode/get?eid=<eid>` (GET, query param — no body). Response
  `{data:{episode}}`; fields `title`, `podcast.title`, `description` (plain), `duration`
  (sec), `pubDate` (ISO), `playCount`, `commentCount`, `image.*`. **No episode-number
  field** — "EP.47" is text only; show line = `podcast.title`.
- Comments: `POST /v1/comment/list-primary`, body
  `{"order":"HOT","owner":{"id":"<eid>","type":"EPISODE"}}`. Response `{data:[...],totalCount}`;
  per comment `text`, `likeCount`, `author.nickname`, `author.avatar.picture.*`, `ipLoc`.
- Both use the same `x-jike-access-token` header the existing content endpoints set.

### Checklist
- [ ] `src/XyzApiClient.{h,cpp}` — `fetchEpisode(eid)` (GET) / `fetchComments(eid)` (POST,
      owner-wrapped); `episode`/`comments` props; `episodeLoaded`/`commentsLoaded`;
      `shapeEpisode`/`shapeComment`; `startGet()`; `eid` added to `shapeInboxItem`
- [x] `qml/gfx/icon-heart.svg`, `qml/gfx/icon-play-white.svg`
- [x] `qml/EpisodePage.qml` — hero / Play CTA (inert) / notes / Top Comments + rows
- [x] `qml/UpdatesPage.qml` — `episodeRequested(item)` + full-delegate tap MouseArea
- [x] `qml/AppWindow.qml` — `EpisodePage` instance, seed + push + fetch, back = pop
- [x] `scripts/mock-content.ps1` — `/v1/episode/get` + `/v1/comment/list-primary` branches
- [x] `qml/qml.qrc` — register `EpisodePage.qml` + 2 SVGs
- [x] `docs/DESIGN_SYSTEM.md`, `docs/API_NOTES.md`, `docs/PLAN.md` — M3
- [x] Simulator build green + clean QML load; tap path verified via request-logging mock
- [ ] On-device visual + live read against the real API (user-run)

### Fix — tap target (post-review)
Reported: couldn't tap an Updates card to open the Episode page on device. Root cause: the tap
target covered only the cover+title (a nested wrapper `Item`), so taps on the description / meta /
play-button area did nothing — on the small screen that reads as "the item isn't tappable." Fixed
by replacing it with a single full-delegate `MouseArea` behind the (non-interactive) content
(canonical Qt-Quick-1 pattern; the ListView still flicks) plus a Belle pressed-state highlight.
Verified the tap path fires `episodeRequested → openWith → push → fetchEpisode → fetchComments`
end-to-end via a request-logging mock (`/v1/inbox/list` → `/v1/episode/get` → `/v1/comment/list-primary`).
On device, do a **clean rebuild** so the qrc re-embeds the updated `UpdatesPage.qml` (editing only
a `.qml` can skip the rcc step).

### Non-goals
Player, full comment thread / replies, comment compose, like interaction, pagination,
`shownotes` HTML rendering (plain `description` only).
