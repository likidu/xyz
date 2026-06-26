# Refresh-Token Logic — Design

**Date:** 2026-06-25
**Status:** Approved (design); pending implementation plan

## Problem

The app logs the user out mid-session — including while an episode is playing —
when a background API request's access token quietly expires. Today, *any* `401`
from a content request immediately tears down the session and bounces the user to
the login page.

Current behavior (`XyzApiClient::onReplyFinished`, `src/XyzApiClient.cpp:257`):

```cpp
if (statusCode == 401) {
    setBusy(false);
    emit sessionExpired();   // → AppWindow.qml: auth.logout(); push(loginPage)
    return;
}
```

`AppWindow.qml` (`qml/AppWindow.qml:96`) reacts to `sessionExpired` by calling
`auth.logout()` (which clears all stored tokens) and pushing the login page.

The login response already stores **both** an access token and a refresh token
(`auth.accessToken`, `auth.refreshToken` in the `kv` table via `StorageManager`),
but the refresh token is never used.

## Goal

On `401`, attempt to refresh the access token using the stored refresh token and
**silently retry** the failed request. Only log the user out if the refresh
itself fails (i.e. the refresh token is also dead).

## Scope

- **In scope:** reactive refresh on `401`, with silent retry of the single failed
  request. Implemented entirely in `XyzApiClient` (C++). No QML changes.
- **Out of scope (explicitly):**
  - Proactive / on-startup refresh — reactive-only fully solves the bug (YAGNI).
  - A public `refreshToken()` method exposed to QML — refresh is internal.
  - Any new "session expired" toast/UI — failure UX is identical to today.
  - Keeping playback alive across a *real* logout — already fine, since episodes
    play from a downloaded local file, independent of auth.

## Reference: the refresh endpoint

Source of truth: the **ultrazg/xyz** Go proxy (`C:\Users\liya\Repos\xyz-go`).

- **URL:** `https://api.xiaoyuzhoufm.com/app_auth_tokens.refresh` (the **content**
  host — same host and iOS-spoof header family `XyzApiClient` already uses, NOT
  the podcaster web-portal host `AuthClient` uses).
- **Method:** `POST`, **empty body**.
- **Auth:** both tokens sent as request **headers**:
  - `x-jike-access-token: <current access token>`
  - `x-jike-refresh-token: <current refresh token>`
- **Response:** the upstream returns the new tokens. Per the Go proxy
  (`handlers/token.go` → `utils.ReturnJson` reads the response **body** as JSON),
  the new tokens arrive as **body keys**:

  ```json
  { "x-jike-access-token": "NEW-ACCESS", "x-jike-refresh-token": "NEW-REFRESH", "success": true }
  ```

  Note: this differs from *login* (podcaster host), where the tokens come back in
  response **headers**. To stay robust (cf. memory "mock diverges from real API"),
  the parser reads the **body keys first, then falls back to response headers**.

## Architecture

All changes are in `XyzApiClient`. `AuthClient` is untouched. `StorageManager`
is untouched (refresh reuses the existing `auth.accessToken` / `auth.refreshToken`
keys). `AppWindow.qml`'s `onSessionExpired` handler is unchanged; it now fires
only when refresh fails.

### New flow on `401`

```
request → 401
   ├─ this was the refresh request itself?      ── yes ─→ emit sessionExpired
   ├─ already refreshed once for this request?  ── yes ─→ emit sessionExpired
   ├─ no refresh token stored?                  ── yes ─→ emit sessionExpired
   └─ otherwise (first 401, refresh token present):
        save the failed request (type, path, body, GET/POST)
        mark m_refreshAttempted = true
        POST /app_auth_tokens.refresh  (both tokens in headers, empty body)
           ├─ 2xx → parse + store new access & refresh tokens
           │        → silently re-send the saved request (new token via storage)
           │             ├─ 2xx → deliver data normally (user sees nothing)
           │             └─ 401 → emit sessionExpired
           └─ non-2xx / timeout / network error → emit sessionExpired
```

Because requests are **serialized** (every `start*` calls `abortActiveRequest`
first), there is at most one in-flight request, so no queue is required.

### State and helpers

New members on `XyzApiClient`:

- `RequestType` enum gains `RefreshRequest`.
- Replay state, set when a **user** request starts:
  `m_replayType`, `m_replayPath`, `m_replayBody` (`QVariantMap`),
  `m_replayIsPost` (`bool`).
- `m_refreshAttempted` (`bool`) — guards against an infinite
  `401 → refresh → 401` loop by allowing at most one refresh per logical request.
  Reset to `false` only when a fresh user request starts; left `true` across the
  refresh and the replay.

Refactor the network-issuing tail of `startPost` / `startGet` into a shared
helper (e.g. `sendRequest(type, isPost, path, body)`) used by:

- `startPost` / `startGet` (user requests) — also reset `m_refreshAttempted` and
  record replay state.
- `startRefresh()` (new) — issues the refresh POST; does **not** touch replay
  state or `m_refreshAttempted` (caller already set it).
- `resendReplay()` (new) — re-issues the saved request from replay state; does
  **not** reset `m_refreshAttempted`, so a second 401 ends in `sessionExpired`.

Add a private parse helper for the refresh response (body keys first, header
fallback) and a `storeTokens(access, refresh)` step that writes both keys via
`m_storage`.

### Busy / loading semantics

Stay `busy == true` continuously through `401 → refresh → retry` so the UI shows
one uninterrupted loading state. `setBusy(false)` only on a terminal outcome
(final success delivering data, or `sessionExpired`).

### Timeout / error handling

- Refresh request uses the same 15s timeout as other requests.
- Any refresh failure (non-2xx, `0`/network, timeout) → `emit sessionExpired`.
  This matches today's logout behavior; a transient failure logging the user out
  is acceptable because the original request genuinely needs a valid token.

## Affected files

- `src/XyzApiClient.h` — enum value, new members, new private method decls.
- `src/XyzApiClient.cpp` — refresh + retry logic, shared send helper, token parse.
- (No changes to `AuthClient.*`, `StorageManager.*`, or any QML.)

## Verification

- **Primary:** point the app at a local mock via the existing `XYZ_API_BASE`
  env override. The mock serves `401` for the first content request, a valid
  token payload for `POST /app_auth_tokens.refresh`, then `200` for the retried
  request. Run on the simulator and confirm: no bounce to login, data loads, and
  the stored `auth.accessToken` changes to the new value.
- **Negative path:** mock returns `401` for the refresh too → confirm the app
  falls back to `sessionExpired` → login page (unchanged behavior).
- **Live/device:** deferred to after the mock-verified pass, per the device-notes
  discipline (record any audio/platform observations in `docs/DEVICE_NOTES.md`).
```
