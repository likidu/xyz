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
