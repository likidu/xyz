# 小宇宙 (Xiaoyuzhou FM) Official API Notes

Learned from the ultrazg/xyz Go proxy source (github.com/ultrazg/xyz, v1.10.0; its docs run
at localhost:23020). We call the **official endpoints directly** — the proxy's request/response
shapes mirror them, so its docs double as a reference.

Two distinct official hosts:

| Host | Used for | Header style |
|---|---|---|
| `https://podcaster-api.xiaoyuzhoufm.com` | Auth (send-code, login) | Browser spoof (web podcaster portal) |
| `https://api.xiaoyuzhoufm.com` | Everything else + token refresh | iOS app spoof |

Auth runs through a native C++ client, **`AuthClient`** (`src/AuthClient.{h,cpp}`), exposed
to QML as the `auth` context property. It owns a `QNetworkAccessManager`, sets the browser-spoof
headers itself, reads HTTP status from `HttpStatusCodeAttribute`, reads tokens from the response
headers, parses the body with vendored **qjson** (`lib/qjson/`), and persists tokens/profile via
`StorageManager`. The endpoint base is overridable via the `XYZ_AUTH_BASE` env var (used to point
at a local mock for testing without sending SMS).

The QML engine's `SslIgnoringNam` (`src/main.cpp`) now only ignores SSL errors for QML `Image`
loads (cover art) over HTTPS — it no longer injects API headers (the native clients do that).
The earlier QML-XHR auth (`qml/js/Api.js`) was removed in the native migration; the Qt 4.7
QML-XHR status-0-on-error quirk it worked around no longer applies (see DEVICE_NOTES).

## Auth

### Send SMS code

```
POST https://podcaster-api.xiaoyuzhoufm.com/v1/auth/send-code
Content-Type: application/json;charset=UTF-8
{"mobilePhoneNumber":"13800138000","areaCode":"+86"}
```

Success: 2xx, empty-ish body. **Rate limited — do not call repeatedly while testing.**

### SMS login

```
POST https://podcaster-api.xiaoyuzhoufm.com/v1/auth/login-with-sms
Content-Type: application/json;charset=UTF-8
{"areaCode":"+86","verifyCode":"1234","mobilePhoneNumber":"13800138000"}
```

> `verifyCode` is **4 digits** (e.g. `1234`), not 6 — the design mockup's 6-box layout
> was an assumption; `VerifyCodePage` uses `codeLength: 4`.

- **Tokens come back in response HEADERS**: `x-jike-access-token`, `x-jike-refresh-token`.
- Body carries profile under `data.user`: `uid`, `nickname`, `avatar.picture.*`, `bio`,
  `phoneNumber`, etc.

Browser-spoof headers sent on both auth calls (set in C++):

```
accept: application/json, text/plain, */*
accept-language: zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6
origin: https://podcaster.xiaoyuzhoufm.com
referer: https://podcaster.xiaoyuzhoufm.com/
user-agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36 Edg/146.0.0.0
```

No device-id / app-version on auth calls.

## Token refresh (NOT implemented yet — for the next milestone)

```
POST https://api.xiaoyuzhoufm.com/app_auth_tokens.refresh
(empty body; both tokens go in request headers)
x-jike-access-token: <current>
x-jike-refresh-token: <current>
```

Fresh tokens come back in **response headers** (same names). Call when any API returns 401.

## Mobile-app headers (api.xiaoyuzhoufm.com — content endpoints + refresh)

Set in C++ for any request to that host:

```
User-Agent: Xiaoyuzhou/2.57.1 (build:1576; iOS 17.4.1)
Market: AppStore
App-BuildNo: 1576
OS: ios
Manufacturer: Apple
BundleID: app.podcast.cosmos
Model: iPhone14,2
app-permissions: 4
App-Version: 2.57.1
WifiConnected: true
OS-Version: 17.4.1
x-jike-device-id: 81ADBFD6-6921-482B-9AB9-A29E7CC7BB55   (fixed UUID, same as Go proxy)
```

Content endpoints additionally want (per Go source; add when implementing them):
`x-jike-access-token: <token>`, `abtest-info: {"old_user_discovery_feed":"enable"}`,
`Local-Time` (ISO timestamp), `Timezone: Asia/Shanghai`.

## Stored auth state (StorageManager kv table)

| Key | Value |
|---|---|
| `auth.accessToken` | x-jike-access-token |
| `auth.refreshToken` | x-jike-refresh-token |
| `auth.uid` | user id |
| `auth.nickname` | display name |
| `auth.areaCode` | e.g. `+86` |
| `auth.phone` | phone number used to sign in |

## Endpoint catalog

Full endpoint list (subscriptions, episodes, comments, discovery, playback progress...) is in
the proxy docs sidebar at localhost:23020/docs — fetch `http://localhost:23020/docs/<name>.md`
for each. Proxy endpoint names map ~1:1 onto official paths; check the Go handlers for the
exact official path before implementing a new one.

## Fallback

If device TLS can't handshake with the official hosts (Symbian-era stack), set
`XYZ_AUTH_BASE` to a LAN-hosted ultrazg/xyz proxy — note its response shape wraps tokens into
the JSON body (`data.x-jike-access-token`) instead of the response headers, so `AuthClient`
would need a small adjustment to read tokens from the body in that mode.
