# Xyz (小宇宙 Belle) — Milestone Plan

## M0 — Scaffold verified
- [ ] Simulator build runs, self-test page all green
- [ ] Device build + self-signed SIS installs
- [ ] On-device self-test all green

## M1 — SMS login (official API)
See `tasks/plan.md` for the detailed plan; design refs in `docs/DESIGN_SYSTEM.md`,
API details in `docs/API_NOTES.md`.
- [x] LoginPage / country picker / VerifyCodePage per design bundle
- [x] sendCode + login against podcaster-api.xiaoyuzhoufm.com, tokens persisted
- [x] Simulator: UI + success path (mock) + error path (live) verified
- [ ] Live login with a real registered number (sends real SMS — user-run)
- [ ] Device: TLS handshake experiment vs official hosts → DEVICE_NOTES.md

## M2 — Updates + Subscriptions (native content client)
See `tasks/plan.md` for the detailed plan; design refs in `docs/DESIGN_SYSTEM.md`,
API details in `docs/API_NOTES.md`.
- [x] Native `XyzApiClient` — `xyzApi` context property; `fetchInbox` / `fetchSubscriptions`;
      iOS-app spoof headers; `shapeInboxItem` / `shapeSubscription` (relative time, 99+ cap);
      401 → `sessionExpired`; `XYZ_API_BASE` env override; 15s timeout; qjson parse
- [x] Placeholder glyph SVGs — 4 tab icons + 6 content icons (`qml/gfx/`)
- [x] `BelleTabBar` — 56px, 4-tab, active-dot, grab handle
- [x] `BelleHeader` optional trailing action (grid/list toggle)
- [x] `UpdatesPage` — glossy title bar, My Subscriptions pill, episode cards, tab bar
- [x] `SubscriptionsPage` — grid (3-col + Often badge) + list (search/starred/rows)
- [x] `AppWindow` wiring — login → Updates, tab routing, session-expiry handler
- [x] Local mock server (`scripts/mock-content.ps1`)
- [x] Simulator: full flow verified (mock), visual check vs design screenshots
- [ ] Live read against real API with a stored token (read-only; user-run)
- [ ] Device: content-API TLS experiment → DEVICE_NOTES.md

Non-goals (deferred): player/mini-player, pagination, search/sort/star actions,
starred fetch, Discover/Search tabs, token refresh.

## M3 — Episode detail page

See `tasks/plan.md` for the detailed plan; design ref `screens-detail.jsx`,
API details in `docs/API_NOTES.md`, component spec in `docs/DESIGN_SYSTEM.md`.
- [x] Native `fetchEpisode`/`fetchComments` (`episode`/`comments` props, `episodeLoaded`/
      `commentsLoaded`, `shapeEpisode`/`shapeComment`, GET `startGet`, `eid` on inbox items)
- [x] `EpisodePage.qml` — hero (seeded from card) + inert Play CTA + show notes + top-comments preview
- [x] Tap an Updates card → push EpisodePage; back = pop. No bottom toolbar (actions deferred)
- [x] `gfx/icon-heart.svg` + `gfx/icon-play-white.svg`; mock `/v1/episode/get` + `/v1/comment/list-primary`
- [x] Simulator: clean build + clean QML load (logged-in Updates render error-free; mock shapes verified)
- [ ] Live read against the real API with a stored token (read-only; user-run)

Non-goals (deferred): player, full comment thread/replies, comment compose, like interaction,
pagination (`loadMoreKey`), HTML `shownotes` rendering.

## Device experiments
See `docs/DEVICE_NOTES.md` (append-only log, dated entries).

