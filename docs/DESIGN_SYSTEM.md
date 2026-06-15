# 小宇宙 Belle — Design System

Source of truth: Claude Design handoff bundle `xyz-for-symbian-belle` (`project/belle.css`,
360×640 nHD portrait, dark Belle theme, cosmic-violet accent). This file records the
palette/metrics for QML implementation; reference screenshots live in the bundle's
`project/screenshots/`.

QML constants mirror this file in `qml/js/Theme.js` — keep the two in sync.

## Palette

| Token | Hex | Use |
|---|---|---|
| `bg` | `#000000` | Page background (true black) |
| `panel` | `#131316` | Card/dialog body bottom |
| `panel2` | `#1b1b20` | Card/dialog body top |
| `chromeHi` | `#3b3b42` | Header gradient top |
| `chromeLo` | `#161619` | Header gradient bottom |
| `hairline` | `rgba(255,255,255,0.08)` → `#14FFFFFF` | Row separators |
| `hairlineStrong` | `rgba(255,255,255,0.14)` → `#24FFFFFF` | Field/dialog borders |
| `text` | `#f3f3f6` | Primary text |
| `textBody` | `#b3b3bd` | Softened body copy (episode description) — brighter than `textDim` for readability |
| `textDim` | `#8b8b95` | Secondary text |
| `textFaint` | `#5d5d66` | Tertiary/disabled text |
| `accent` | `#8b6dff` | Cosmic violet — active borders |
| `accentBright` | `#a98cff` | Highlights, links, button gradient top |
| `accentDeep` | `#5b3fd6` | Button gradient bottom |
| `accentGlow` | `rgba(139,109,255,0.45)` | Glows (approximate/skip in QML 1.1) |

Error color (not in design; matches SelfTestPage convention): `#c62828`.

## Typography

Design: Noto Sans / Noto Sans SC ≈ device Nokia Pure — use default device font.
Sizes (px, rounded to int for QML): body 15, header title 19 w600, login brand name 21 w700,
brand tag 11 (letterspacing 2, uppercase), section head 16 w600, hint 12, footer 11,
field value 17, field placeholder 16, code box digit 24 w700, button label 16 w700,
dialog title 15 w700, option row 15, option code 14.

### Readability on device — type-scale principle

The target is a ~3.5–4" nHD (360×640) panel held at arm's length, so **content text must
run larger and brighter than a desktop mock implies**. Apply this to every screen (it drove
the Updates + Subscriptions readability pass on 2026-06-14):

- **Content titles ≥ 16–17px; secondary/meta ≥ 13px; body/description ≈ 14–15px.** Don't drop
  readable content text below 13px.
- **Never pair tiny with dim** — small *and* low-contrast is the worst combination. If text
  must be small, keep it bright. The episode description uses `textBody` (#b3b3bd), not
  `textDim`, for exactly this reason.
- Round design half-px values **up** to int for QML (`font.pixelSize` is int): 14.5 → 15, 13.5 → 14.
- Touch targets stay **≥ 44px** regardless of text size.
- Login / Verify already sit at this comfortable scale (16–24px headers, 17px input); the
  readability pass deliberately left them unchanged.

## Chrome metrics

- Status bar 26px (native Symbian status bar is used on device — don't re-implement).
- View header 52px; vertical gradient `#3b3b42 0% → #232328 6% → #1a1a1e 60% → #161619 100%`,
  1px black bottom border. Back button 44×44 hit target, 26px chevron glyph.
- Bottom toolbar 56px (NOT shown on pre-login screens).

## Login screens (`screens-login.jsx`)

- Content side padding 22.
- Brand: orb 76×76 (radial violet `#a98cff 30%,22% → #5b3fd6 48% → #2a1d54 100%` + white
  highlight dot 13px at top-right, opacity 0.85), margin-top 46; name margin-top 16;
  tag margin-top 4.
- "Sign in with phone" head: margin-top 38.
- Field row: margin-top 16, height 50, radius 7, vertical gradient `#0c0c0e → #161619`,
  1px `hairlineStrong` border (inset shadow approximated by the dark gradient).
  - Country-code chip: flag/abbrev + code (15 w600) + 16px down-chevron, right 1px
    `hairlineStrong` separator, padding 14/12.
  - Input: padding 0 14, caret 2×22 `accentBright`.
- Hint: margin-top 12, 12px `textDim`.
- Primary button: margin-top 22, height 50, radius 7, gradient `#a98cff → #5b3fd6`,
  white label.
  Disabled: gradient `#2a2a30 → #1d1d22`, label `textFaint`.
- Terms footer: anchored bottom, padding 18/22, 11px `textFaint`, links `accentBright` w600.
- Country picker dialog: scrim `rgba(0,0,0,0.6)` → `#99000000`; dialog left/right margin 14,
  vertically centered, radius 9, gradient `#1b1b20 → #131316`, border `hairlineStrong`;
  title bar padding 14/16, gradient `chromeHi → chromeLo`, 1px black bottom border;
  option rows padding 14/16, `hairline` separators; radio 20px circle, 1.5px `textFaint`
  border; selected → border + 12px inner dot `accentBright`, name `accentBright`.
- Code entry: head margin-top 30; "Code sent to …" sub margin-top 14, 13px `textDim`
  (number in `text` w600); code boxes margin-top 24, gap 9, height 56, radius 7, same inset
  field style; active box border `accent`; resend line margin-top 18, 13px `textDim`,
  action in `textFaint` w600.

## QML 1.1 adaptation rules

- No radial gradients → orb is an SVG asset (`qml/gfx/login-orb.svg`); CSS linear-gradient
  buttons/chrome map 1:1 to QML `Gradient` stops.
- Box shadows/glows are skipped (no shader effects in QML 1.1) except where a border
  substitutes (active code box).
- Flag emoji don't render on Symbian → "CN"/"US" text chips.
- SVG icons: Symbian sizes by `viewBox`, not width/height — bake the target size into both
  (see CLAUDE.md).
- Remember: no block expressions in bindings, functions only at Page root, no negative
  anchor margins.

## M2 screens (implemented)

**Bottom tab bar** (`BelleTabBar.qml`, 56px): dark glossy gradient (`#2a2a30 → #1d1d22 →
#141417`), 1px black top border, 4-tab Belle grab handle, 4 placeholder glyph tabs
(compass/search/headphones/person), active tab at full opacity + 5px accent dot (`accentBright`)
at bottom centre. Placeholder icons pending real assets; tab indices 0/1 (Discover/Search)
are inert for now.

**Updates page** (`UpdatesPage.qml`): custom 56px title bar (24px/800 "Updates" left,
"My Subscriptions" pill right, 14px — `accentBright` tinted border + headphones icon). Episode
card: 64px cover (`sourceSize` capped) + 2-line title (17px/bold) + 2-line desc (15px/`textBody`)
+ meta row (duration · when · plays · comments, 13px/faint, dot separators) + action row
(queue / comment+count [14px] / dots left, 48px play circle right). commentCount capped at "99+".
(Sizes reflect the 2026-06-14 readability pass — see the type-scale principle above.)

**Subscriptions page** (`SubscriptionsPage.qml`): `BelleHeader` with trailing toggle
action (grid↔list icons). Grid: 3-column `GridView`, `cellWidth = floor(width/3)`, 120px
`sourceSize`, "Often" badge (10px/accentBright, semi-transparent accent-tinted background).
List: search bar (42px, 15px placeholder, `hairline` border), "Starred" / "All Subscriptions"
subheads (15px), starred empty-state card (hint 14px, "+ Add" 15px), 72px rows (52px cover +
name [16px] / hosts·when [13px] with avatar stack of up to 2 rounded-square 19px avatars +
dots). Toggle uses `BelleHeader.actionIconSource`.
(Sizes reflect the 2026-06-14 readability pass — see the type-scale principle above.)

## M3 screen (implemented)

**Episode page** (`EpisodePage.qml`, design `screens-detail.jsx` + `.ep-*`/`.cmt-*`): pushed
from an Updates card tap (the cover+title area; the 48px play circle stays a separate target).
`BelleHeader` (back, "Episode") over a `Flickable`:

- **Hero** (`.ep-hero`): 104px square cover + show title (14px/`accentBright`) · episode title
  (19px/bold, wraps) · duration·time sub (13px/`textDim`). Seeded from the tapped inbox item for
  instant paint; the show title + notes fill from the fetched detail. **No episode-number field
  exists in the API** — the mock's "EP.47"/"183." prefix is just part of the title string, so the
  show line is only the podcast title.
- **Play CTA** (`.ep-play`): 46px violet gradient (`accentBright`→`accentDeep`), white play glyph
  + "Play". Inert placeholder — player is its own later milestone.
- **Show notes** (`.ep-notes`): plain-text `description`, 15px/`textBody`, hairline divider below.
  (HTML `shownotes` deferred.)
- **Top Comments** (`.cmt-head` + `.cmt`): header (15px/`accentBright`) + count (episode
  `commentCount`); rows of a 36px rounded avatar (initial fallback when no picture) + name·ipLoc
  (13px/`textDim`) + text (15px/`text`) + a vertical ♥ like cluster (heart 18px + count, `textFaint`).
- **No bottom toolbar** — the mockup's comment/add/share/list bar is omitted while its actions are
  deferred with the player.

Data: native `xyzApi.fetchEpisode(eid)` then `fetchComments(eid)`, sequenced (the client serves one
request at a time). New assets: `gfx/icon-heart.svg`, `gfx/icon-play-white.svg`. Sizes follow the
on-device type-scale above.

## Other screens (recorded for later milestones)

belle.css also specs: native two-line list rows (70px min, pressed state = violet gradient
+ 3px left bar), card feed, and the player (208px art, scrubber, 72px play button). Pull
metrics from the bundle when those screens are built.
