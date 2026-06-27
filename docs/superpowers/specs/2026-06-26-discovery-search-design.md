# Discovery search → Search page (design spec)

Date: 2026-06-26
Status: approved (pending spec review)

## Goal

Add a search affordance to the Discovery page. Tapping it opens a dedicated
Search page whose search bar sits at the top. Typing a keyword runs a live
**episode** search; results render as the existing episode cards and tapping one
opens the existing Episode detail page (→ download-then-play).

This realizes the search action the design's `screens-feed.jsx` header already
specifies (`<Header actions={[{ icon: "search" }]} />`) but the QML never built.

## Scope (decided)

- **Episodes only**, functional. No podcast/user results (the app has no
  Podcast/show page to open a podcast into; out of scope).
- **First 20 results only.** No "load more" / pagination state.
- Reuse via a **shared `EpisodeCard.qml`** component (extracted from
  DiscoveryPage), used by both Discovery and Search.

## Components & changes

### 1. `EpisodeCard.qml` (new, extracted)

Pull DiscoveryPage's inline episode-card markup into one reusable component:
cover (76²) + show name + title (3-line) + foot row (duration · comments ·
when), with the press-wash rectangle and the single whole-card `MouseArea` on
top (per the Symbian list-row tap-target rule — one full-delegate MouseArea
behind content, content never grabs the mouse).

- Inputs: `property variant item` (the shaped episode map: `coverUrl`,
  `showName`, `title`, `durationText`, `commentCount`, `whenText`).
- Output: `signal clicked` (host decides what to open).
- Styling unchanged from today's Discovery card (Theme gradient panel, radius 8,
  hairline border). Verify Discovery renders byte-identical after extraction.

### 2. `DiscoveryPage.qml`

- Replace the inline card body with `EpisodeCard { item: modelData; onClicked:
  page.episodeRequested(modelData) }`.
- Add a 44×44 search button at the right edge of the existing `titleBar`,
  reusing `gfx/tab-search.svg` (already in qrc; matches the design glyph), with
  the standard accent press-wash (mirror BelleHeader's action button).
- Add `signal searchRequested`; the button's `onClicked: page.searchRequested()`.

### 3. `SearchPage.qml` (new)

`Page { hidesToolBar: true }`, dark `Theme.bg`.

- **Search bar header** (glossy, like the Discovery titleBar / BelleHeader
  gradient):
  - Back button (left, `gfx/icon-back.svg`) → emits `backRequested`; the host
    wires `onBackRequested: pageStack.pop()`. Required because `hidesToolBar:
    true` hides the system toolbar's back button. 44×44 with press-wash.
  - Search field filling the rest: dark gradient `#0c0c0e→#161619`, radius
    `Theme.cornerRadius`, `hairlineStrong` border; inline magnifier glyph
    (`gfx/tab-search.svg`) on the left; `TextInput` with accent `cursorDelegate`;
    placeholder `qsTr("Search episodes")` shown when empty & unfocused (overlay
    Text, like LoginPage).
  - `onAccepted: page.runSearch()` → `xyzApi.search(text)`.
  - On `PageStatus.Active`: `searchInput.forceActiveFocus()` +
    `searchInput.openSoftwareInputPanel()` so the keyboard opens immediately.
- **Body** below the header (above tab/mini-player is N/A — this is a pushed
  detail page, no tab bar):
  - `BusyIndicator` while `xyzApi.busy && searchRequest in flight`.
  - Results: `Flickable` + `Column` of `EpisodeCard`s from
    `xyzApi.searchResults`; `onClicked` → `page.episodeRequested(item)`.
  - Empty states (mutually exclusive, centered):
    - idle (no query run yet): hint `qsTr("Search episodes by keyword")`.
    - no results: `qsTr("No episodes found")`.
    - error: `xyzApi.errorMessage`.
- Signals: `episodeRequested(variant item)`, `backRequested`.

### 4. `XyzApiClient` (C++)

Mirror the existing request/parse/shape patterns; **no pagination**.

Header (`XyzApiClient.h`):
- Property `QVariantList searchResults READ searchResults NOTIFY searchLoaded`.
- `Q_INVOKABLE void search(const QString &keyword);`
- `signals: void searchLoaded();`
- `enum RequestType { ..., SearchRequest };`
- members: `QVariantList m_searchResults;` `QString m_searchKeyword;`

Impl (`XyzApiClient.cpp`):
- `search(keyword)`: ignore empty keyword. Build body:
  `{keyword, type:"EPISODE", limit:"20", sourcePageName:"4", currentPageName:"4"}`
  and `startPost(SearchRequest, "/v1/search/create", body)`.
- `applyContentHeaders`: extend the `abtest-info` opt-in to also fire for
  `SearchRequest` (the proxy's Search handler sends it; discovery already does).
- `onReplyFinished`, `SearchRequest` branch: take top-level `data` as a list
  (with the same tolerant `data.data` fallback discovery uses), iterate, keep
  entries whose `type == "EPISODE"`, shape each entry **directly** via
  `shapeDiscoveryEpisode(entry)` — in search results the episode fields
  (`eid`, `title`, `duration`, `pubDate`, `commentCount`, `podcast{...}`) sit at
  the entry's top level (unlike the discovery feed's `entry.data...episode`
  nesting). Assign `m_searchResults`, `setBusy(false)`, `emit searchLoaded()`.

`shapeDiscoveryEpisode` already emits exactly the card/tap map both EpisodeCard
and `episodePage.openWith` need (`eid`, `coverUrl`, `title`, `showName`,
`durationText`, `whenText`, `commentCount`).

### 5. `AppWindow.qml` + `qml.qrc`

- Add a `SearchPage { id: searchPage; onEpisodeRequested: { episodePage.openWith(item); pageStack.push(episodePage); } }`.
- `DiscoveryPage { ... onSearchRequested: pageStack.push(searchPage) }`.
- Add `<file>SearchPage.qml</file>` and `<file>EpisodeCard.qml</file>` to
  `qml/qml.qrc` (new .qml files silently fail to load without a qrc entry).

## Data flow

```
Discovery search button → searchRequested → AppWindow pushes SearchPage
SearchPage active → field focuses, VKB opens
type + accept → xyzApi.search(kw) → POST /v1/search/create (type=EPISODE)
reply → keep type=="EPISODE" entries → shapeDiscoveryEpisode → searchResults → searchLoaded
EpisodeCard tap → episodeRequested(item) → AppWindow: episodePage.openWith(item) + push
```

## Verification (per project lessons)

1. **Live API shape first.** Before trusting the doc, replay the real call with
   the simulator's `auth.accessToken` (read from xyz.db) from PowerShell:
   `POST https://api.xiaoyuzhoufm.com/v1/search/create` with the body above and
   the iOS spoof headers. Confirm: response is `{data:[...]}` (one level, not
   `data.data`), and EPISODE entries carry episode fields at entry level. Adjust
   the parser to the real shape (the proxy doc double-wraps `data`).
2. Build the SIS / simulator binary cleanly.
3. Run the flow in the simulator: tap search → keyboard opens → type a known
   keyword (e.g. a popular show) → results appear as cards → tap a result →
   Episode page opens. Screenshot.
4. Confirm Discovery still renders identically after the EpisodeCard extraction.

## Out of scope

- Podcast and user search results; a Podcast/show page.
- Pagination / "load more" beyond the first 20.
- Search-preset suggestions (`/search_preset`), search history, debounced
  type-ahead. (Could be a follow-up.)

## Risks

- Real search response shape may differ from the proxy doc — mitigated by step 1
  (live replay) before wiring the parser.
- EpisodeCard extraction could regress Discovery layout — mitigated by visual
  diff (step 4).
