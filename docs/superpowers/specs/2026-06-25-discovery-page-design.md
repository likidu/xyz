# Discovery Page — Design Spec

**Date:** 2026-06-25
**Branch:** `worktree-discovery`
**Status:** Approved (design), pending implementation plan

## Goal

Add a **Discovery** page (发现) to the Symbian Belle Xiaoyuzhou FM client, reachable
from the existing compass tab (toolbar index 0, currently an inert placeholder). The
page presents multiple recommendation sections sourced from the official discovery
feed, rendered as the design's multi-section card layout (`FeedCards` in the Claude
Design project `screens-feed.jsx`).

Required sections (at least):
- **Recommendation** (大家都在听 / 为你推荐)
- **Editor Picks** (编辑精选)
- **Special Topics** (themed episode collections)
- **Hottest** (最热榜)

## Decisions (locked)

- **All 4 sections**, sourced from **3 aggregated API calls**.
- **Episode-only**: render only `targetType=="EPISODE"` modules; PODCAST-type modules
  and non-collection entries (e.g. `NEW_POWER`) are skipped. Every card is an episode
  that taps through to the existing `EpisodePage`. No podcast/show detail page is built.
- **Section titles come live from the API** (大家都在听, 编辑精选, 最热榜…), not the
  design's hard-coded bilingual labels. (Alternative, not chosen: force the design's
  fixed labels by mapping positionally.)
- **Real cover images** (`Image { source: coverUrl }`) replace the design's gradient
  placeholders, consistent with every other page.

## API

Endpoint: `POST https://api.xiaoyuzhoufm.com/v1/discovery-feed/list`
(proxy reference: `ultrazg/xyz` `handlers/discovery.go`, doc `doc/docs/discovery.md`).

Headers: the standard iOS-app spoof set already used by `XyzApiClient` content calls,
plus `x-jike-access-token: <stored>` and `abtest-info: {"old_user_discovery_feed":"enable"}`,
`Local-Time` (ISO8601), `Timezone: Asia/Shanghai`.

Three calls, each in its own result bucket for deterministic final ordering:

| Bucket | Body | Sections returned |
|---|---|---|
| `DiscoveryDefault` | `{"returnAll":"false"}` | 大家都在听 (Recommendation) + 编辑精选 (Editor Picks) |
| `DiscoveryTopic` | `{"returnAll":"false","loadMoreKey":"discoveryTopic"}` | special-topic episode modules |
| `DiscoveryHot` | `{"returnAll":"false","loadMoreKey":"mediumDiscoveryPictorial"}` | 最热榜 (Hottest) + (podcast-type lists, skipped) |

### Response shape (relevant subset)

```
data.data[]                       // array of feed entries
  └─ { type: "DISCOVERY_COLLECTION",
       data: [                    // array of MODULES
         { title, moduleType, targetType: "EPISODE"|"PODCAST",
           description?,           // → section subtitle when present
           target: [ { episode: {...}, recommendation } , ... ] }
       ] }
  └─ { type: "NEW_POWER", data: {...} }   // skipped (episode-only)
```

Per-episode fields used: `eid`, `title`, `duration` (sec), `pubDate` (ISO),
`commentCount`, `image.{picUrl…thumbnailUrl}`, parent `podcast.title` (show name).

## Native client changes — `src/XyzApiClient.{h,cpp}`

- Add `Q_INVOKABLE void fetchDiscovery();` — fires the three POSTs above.
- Add request enum values `DiscoveryDefault`, `DiscoveryTopic`, `DiscoveryHot`.
- Three member buckets (`m_discDefault`, `m_discTopic`, `m_discHot` as `QVariantList`)
  + a pending counter. On each reply: shape into its bucket, decrement counter; when
  the counter hits zero, concatenate buckets in fixed order (default → topic → hot)
  into `m_discoverySections` and emit `discoveryLoaded()`.
- `Q_PROPERTY(QVariantList discoverySections READ discoverySections NOTIFY discoveryLoaded)`.
- `busy` is true while any of the three is in flight (reuse existing busy mechanism).
- `shapeDiscoverySections(response)`: walk `data.data[]`; for each
  `DISCOVERY_COLLECTION`, walk nested `data[]` modules; keep only
  `targetType=="EPISODE"`. Each kept module →
  `{ title: module.title, subtitle: module.description||"", items: [ episodeMap, ... ] }`.
- `shapeDiscoveryEpisode(target)` → `{ eid, coverUrl, title, showName, durationText,
  whenText, commentCount }`, reusing the existing duration / relative-time / count
  formatters (those used by `shapeInboxItem`). `showName` and `commentCount` drive the
  **card foot**; the remaining fields are a **superset of what `EpisodePage.openWith`
  seeds** (`eid, coverUrl, title, durationText, whenText` — verified in
  `qml/EpisodePage.qml:43`). `openWith` ignores the extra keys and fetches the show
  title / comment count itself from the episode-detail call, so the same map can be
  passed straight through on tap.

### Error / empty handling

- If a call fails, its bucket stays empty; the page still renders whatever returned.
- `errorMessage` is set only if **all three** calls fail.
- 401 on any call → existing `sessionExpired` path (re-login).

## QML page — `qml/DiscoveryPage.qml`

Follows the `UpdatesPage` pattern:
- `load()` with a `loadedOnce` guard, fired on `onStatusChanged` when
  `status === PageStatus.Active`; re-fetch only if the prior attempt failed/aborted.
- `signal episodeRequested(variant item)` bubbled to `AppWindow`.

Layout: a single outer `ListView` (or `Flickable` + `Repeater`) over
`xyzApi.discoverySections`. Per section:
- **Section header** — `sec-title` (accent-bright), optional `sec-sub` subtitle.
- A vertical stack of **episode cards**, porting the design's `.card`:
  cover thumbnail (real `Image`, `PreserveAspectCrop`, `sourceSize` hint) + show name +
  2–3-line episode title; foot row: headphones · duration, comment · count, and
  right-aligned relative time.
- Whole-card `MouseArea` (single full-delegate tap target per the list-row-tap-target
  memory) → `page.episodeRequested(modelData)`.

Styling ported from `belle.css`: accent `#8b6dff` / `#a98cff`, panel gradient
`#1b1b20`→`#131316`, hairline `rgba(255,255,255,0.08)`. Font sizes kept at the
device-readable scale (titles ~16–17, meta ~13) per the Belle type-scale memory —
**not** the smaller mock CSS values; all `pixelSize` values are integers (per the
pixelSize-must-be-int memory).

States:
- `BusyIndicator` visible while `xyzApi.busy && sections.length === 0`.
- Error text visible only if `!busy && sections.length === 0 && errorMessage.length > 0`.
- Empty text if loaded once with zero sections.

QML 1.1 constraints observed: no block expressions in bindings (use helpers/ternaries),
no named function declarations inside non-root elements, no negative anchor margins.

## Navigation wiring — `qml/AppWindow.qml`, `qml/BelleTabBar.qml`

- Instantiate `DiscoveryPage { id: discoveryPage; onEpisodeRequested: { episodePage.openWith(item); pageStack.push(episodePage) } }`.
- `handleTab(0)`: push `discoveryPage` if not current and stack not busy (mirroring the
  index-2 Account push). Index 0 stops being inert.
- Toolbar icon unchanged (`gfx/tab-compass.svg`).

## Verification

Per the mock-diverges-from-real-API and verify-QML-flow-interactively memories — a clean
build + static review is **not** sufficient:
1. Build the SIS / desktop sim build.
2. Run the actual flow in the simulator (temp `initialPage` to skip login if needed),
   with a real token **or** a mock shaped to the **official nested response** (not the
   proxy's flattened facing shape).
3. Confirm: all sections render in order, cover images load over HTTPS, section
   subtitles appear where the API supplies `description`, and a card taps into
   `EpisodePage` with a correctly seeded hero.
4. Record any audio/media/platform-API findings (and any API-shape surprises) in
   `docs/DEVICE_NOTES.md` with a dated heading.

## Out of scope

- Podcast/show detail page (PODCAST-type modules are skipped).
- Pagination / "explore more" / "see all" affordances (the design's `sec-more` link is
  rendered but inert for now).
- Pull-to-refresh / the `refresh-episode-recommend` endpoint.
- The design's flat `FeedList` variant (we implement `FeedCards` only).
