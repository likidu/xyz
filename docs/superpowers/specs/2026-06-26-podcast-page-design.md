# Podcast (Show) Page — Design Spec

**Date:** 2026-06-26
**Status:** Approved (design); pending implementation plan
**Source design:** Claude Design project `小宇宙 Belle` — `screens-podcast.jsx` + `.pod-*` / `.up-*` rules in `belle.css`.

## 1. Goal & Scope

Add a **podcast (show) detail page** — the show behind an episode: hero (name,
description, author, cover), subscriber count + subscribe control, episode-count
line with All/Popular chips, and a paginated list of the show's episodes. Tapping
a row opens the existing Episode page (download → play); there are no per-row play
buttons.

**This pass (approved): real reads.**
- Live podcast detail + paginated episode list via new `XyzApiClient` methods.
- Subscribe pill reflects the real subscribed state but is **display-only**.
- Entry points wired from **both** Subscriptions and the Episode page.

**Deferred (explicitly out of scope):**
- Subscribe/unsubscribe write (`POST /v1/subscription/update`).
- Popular filter (`POST /v1/episode/list-by-filter`, `label:"POPULAR"`) — chip
  shown but inert.
- Show-notes / podcaster-bio expansion.

## 2. Verified API (source of truth: `xyz-go` proxy, not the mock)

The proxy double-wraps responses (ReturnJson). The client already strips the
outer level before `onReplyFinished`, so inside dispatch `top.value("data")` is
the real upstream payload, with siblings (`loadMoreKey`, `total`) at `top` —
identical to the existing comments handling.

- **Podcast detail:** `GET /v1/podcast/get?pid=<pid>` → `data` is a **map**:
  `title`, `author`, `brief`, `description`, `image{picUrl,…}`, `subscriptionCount`,
  `episodeCount`, `subscriptionStatus` ("ON"/"OFF"), `podcasters[]{nickname,
  avatar.picture{…}}`, `pid`.
- **Episode list:** `POST /v1/episode/list` body `{pid, order:"desc", limit:"20",
  loadMoreKey?}` → `data` is an **array** of episodes; `loadMoreKey`
  `{pubDate,id,direction:"NEXT"}` and `total` are siblings at `top`. Each episode:
  `eid`, `pid`, `title`, `description`, `duration` (sec), `pubDate`, `playCount`,
  `commentCount`, `image{…}`, `media{…}`. First page omits `loadMoreKey`; absent
  on last page → empty map → `hasMorePodcastEpisodes` false.

## 3. Architecture

A new pushed **detail page** `PodcastPage.qml`, sibling to `EpisodePage` — seeded
from the tapped item for instant paint, then fetches live data. Standard page
shape: `Page { hidesToolBar: true }` → `BelleHeader` (back) → `Flickable`/`Column`
→ `MiniPlayer`. **No bottom tab bar**, matching `EpisodePage` (the real app drops
the mock's persistent toolbar on pushed detail pages).

The client serves one request at a time, so on activation `fetchPodcast` runs
first and `fetchPodcastEpisodes` is chained after the podcast lands (same pattern
as Episode detail → comments).

## 4. C++ — `XyzApiClient` additions

Mirror the existing inbox/episode/comments code paths exactly.

**Properties (READ + NOTIFY):**
- `QVariantMap podcast` → `podcastLoaded`
- `QVariantList podcastEpisodes` → `podcastEpisodesLoaded`
- `bool hasMorePodcastEpisodes` (≡ `!m_podcastEpisodesLoadMoreKey.isEmpty()`) → `podcastEpisodesLoaded`

**Invokable methods:**
- `fetchPodcast(const QString &pid)` → `startGet(PodcastRequest, "/v1/podcast/get?pid="+pid)`
- `fetchPodcastEpisodes(const QString &pid)` → resets `m_podcastEid`/key/total,
  `startPost(PodcastEpisodesRequest, "/v1/episode/list", {pid, order:"desc", limit:"20"})`
- `loadMorePodcastEpisodes()` → guards (`busy`, pid set, key non-empty), echoes
  `loadMoreKey`, `startPost(MorePodcastEpisodesRequest, …)` — append results.

**Dispatch branches** (alongside line ~468):
- `PodcastRequest`: `raw = top.value("data").toMap()` (fallback `top`) →
  `m_podcast = shapePodcast(raw)` → emit `podcastLoaded`.
- `PodcastEpisodesRequest` / `MorePodcastEpisodesRequest`: shape `top.value("data").toList()`;
  first page replaces, more appends; `m_podcastEpisodesLoadMoreKey = top.value("loadMoreKey").toMap()`;
  read `total`; emit `podcastEpisodesLoaded`.

**One-line pid surfacing (for entry points):**
- `shapeSubscription` (line 644): `out.insert("pid", item.value("pid").toString())`.
- `shapeEpisode` (line 676): `out.insert("pid", item.value("pid").toString())`.

**New shapers:**
- `shapePodcast`: `name` (title), `desc` (description), `author` (podcasters[0]
  nickname), `authorAvatarUrl` (podcasters[0] avatar via `pickImageUrl`), `coverUrl`
  (`pickImageUrl(image)`), `subscriberText` (subscriptionCount, grouped thousands),
  `episodeCountText` (episodeCount), `isSubscribed` (`subscriptionStatus == "ON"`),
  `pid`.
- `shapePodcastEpisode`: `eid`, `coverUrl`, `title`, `desc` (description),
  `durationText` (`"%1 min"`, round like shapeEpisode), `whenText` (`relativeTime(pubDate)`),
  `plays` (playCount), `cmt` (commentCount). The `eid`/`coverUrl`/`title`/
  `durationText`/`whenText` fields are exactly what `EpisodePage.openWith` reads.

Reuses existing helpers: `pickImageUrl`, `relativeTime`, request/refresh/replay
machinery. (A small grouped-thousands formatter for `subscriberText`.)

## 5. QML — `PodcastPage.qml`

Properties: `pid`, plus seed fields (`name`, `coverUrl`, …), `loaded` flags
mirroring `EpisodePage`. `openWith(pid, seed)` seeds the hero, clears stale state,
sets `pid`. `onStatusChanged` Active + not loaded → `fetchPodcast(pid)`.
`Connections` on `xyzApi`: `onPodcastLoaded` → fill hero, then `fetchPodcastEpisodes(pid)`;
`onPodcastEpisodesLoaded` → set list model.

Layout (Flickable/Column, `.pod-*` styling from belle.css):
- **Hero** (`.pod-hero`): real cover Image (112px), `name` (27px/800), `desc`
  (3-line clamp), author chip (avatar Image + name, initial fallback like comments).
- **Subscriber row** (`.pod-subrow`): count (24px/800) + label, bell icon,
  display-only Subscribe/Subscribed pill from `isSubscribed`.
- **Filter line** (`.pod-filter` + `.pod-chips`): episode-count text; `All` chip
  active, `Popular` chip inert.
- **Episode list**: `Repeater` over `xyzApi.podcastEpisodes`; `up-item` row (cover
  + title + 2-line desc + meta `dur · when · 🎧plays · 💬cmt`); one full-row
  `MouseArea` behind content (list-row tap-target rule) → `episodeRequested(item)`.
- **Load-more footer**: idle ("Load more" + showing-count) / spinner / "All
  episodes loaded" — copied from `EpisodePage`, driven by `hasMorePodcastEpisodes`.
- **States**: BusyIndicator while loading first page; error text; same as siblings.

`PodcastPage` signals: `episodeRequested(variant item)`, `openPlayerRequested`.

## 6. Navigation (both entry points)

`AppWindow.qml`:
```qml
PodcastPage {
    id: podcastPage
    onEpisodeRequested: { episodePage.openWith(item); pageStack.push(episodePage); }
    onOpenPlayerRequested: window.openNowPlaying()
}
```

- **Subscriptions** (`SubscriptionsPage.qml`): add a full-cell `MouseArea` to the
  grid delegate and the list `rowDelegate` → `page.podcastRequested(modelData.pid, modelData)`;
  page gains `signal podcastRequested(string pid, variant seed)`; AppWindow:
  `onPodcastRequested: { podcastPage.openWith(pid, seed); pageStack.push(podcastPage); }`.
- **Episode page** (`EpisodePage.qml`): make show name/cover tappable (small
  `icon-chevron` affordance) → `page.podcastRequested(<episode pid>)` using the
  now-surfaced `xyzApi.episode.pid`; AppWindow pushes `podcastPage`.

`openWith(pid, seed)` paints immediately from the seed (subscription cover/name
when available), then fetches fresh.

## 7. Assets & registration

- Add `qml/gfx/icon-bell.svg`, `qml/gfx/icon-headphone.svg` (Remix line icons,
  recolored `currentColor` → concrete, per the remixicon practice). Reuse existing
  `icon-comment.svg` (comment count) and `icon-chevron.svg` (show-link affordance).
- Register `PodcastPage.qml` + both new icons in `qml/qml.qrc` (qrc-entry rule —
  unregistered files silently fail to load).
- Wire `PodcastPage` element + navigation in `AppWindow.qml`.

## 8. Verification

- Build for the simulator (clean log).
- Replay `podcast/get` and `episode/list` with the sim's live `auth.accessToken`
  from PowerShell to confirm real response shapes before/after parser work
  (replay-with-sim-token practice; mocks have diverged from the real API before).
- Run the flow in-sim: Subscriptions → show; Episode → show; load-more pagination;
  row → Episode → download/play. Confirm no empty lists and correct hero/meta.
- No DEVICE_NOTES entry needed unless an audio/MMF surprise appears (this is
  networking + UI, not media).

## 9. Components & boundaries

| Unit | Does | Depends on |
|------|------|-----------|
| `XyzApiClient` podcast methods | Fetch + shape podcast detail and paginated episodes; expose as `podcast`/`podcastEpisodes` | upstream API, existing request machinery |
| `PodcastPage.qml` | Render hero + subscribe row + episode list; emit `episodeRequested` | `xyzApi`, `BelleHeader`, `MiniPlayer`, `Theme.js` |
| Navigation wiring | Route Subscriptions/Episode taps → `PodcastPage`; route its rows → `EpisodePage` | `AppWindow.qml`, `pageStack` |
| Assets/qrc | New icons + page registered so they load | `qml.qrc` |
