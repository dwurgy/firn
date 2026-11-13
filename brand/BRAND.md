# Firn brand sheet: Sunrise

The look of firnbrowser.com since November 2026, written down in one place
so the app (welcome screens, empty tab page), Claude Design and anything new
can start from the same rules. Values are copied from the live site:
`public/home.css` (home), `public/page.css` (inner pages) and
`public/site.css` (shared). If this sheet and the CSS ever disagree, the CSS
is what ships; fix the sheet.

## The idea

Sunrise at a snowy cabin near Sisters, Oregon, with a fresh cup of coffee in
hand. Quiet, cold air, warm light coming up.

- **The window (home, welcome screens):** blue-hour sky at the top, warming
  to dawn at the horizon, the sun just coming up over fresh snow.
- **The desk inside (inner pages, settings, everyday screens):** plain warm
  paper, no sky, with the snow kept to one edge at the bottom.
- **Calm.** Lots of space, few things on screen, slow and small motion. No
  carousels, pop-ups or stock photos (snow texture is the one exception).

## Colour

### Paper and text (warm neutrals)

| Role | Light | Dark |
|---|---|---|
| Page / paper | `#FBFAF8` | `#2B2826` |
| Ink (headlines, body, main button) | `#241F1B` | `#F5F1EC` |
| Muted text | `#5E564E` | `#D4CDC5` |
| Faint (hints, rules) | `#9D9389` | `#958D85` |
| Frame / sand | `#E9E3DA` | `#3A3734` |

### Blue-hour sky

The sky is one plain vertical gradient. On home it runs over the whole page
(px from the top):

- **Light:** `#1C2130` 0 → `#252C3E` 520 → `#343E57` 1000 → `#556079` 1420 →
  `#8D8C9E` 1760 → `#CDB8B4` 1960 → `#EAD3C5` 2200 → `#F4E5DA` 2700 →
  `#F7F0E8` 3200 → `#F6F3EE` 3800
- **Dark:** stays blue hour all the way: `#1A1F2D` → `#212839` → `#283043` →
  `#2E3548` → `#34394B` → `#373A48` → `#383733`

For a single screen, compress it: dark at the top, then the last stops
(`#556079` → `#8D8C9E` → `#CDB8B4` → `#EAD3C5`) packed just above the snow.
The link preview (`design/share-preview/og.html`) does exactly this at 630px.

Top-of-screen colour (status bar, theme-color, window background behind the
sky): `#1C2130` light, `#1A1F2D` dark.

**Text on the dark sky** is always light, in both modes: `#F5F1EC` (15:1),
muted `#D4CDC5` (11:1), small print `#B9B2AA` (8:1). Logo: the on-dark lockup.

### The sun

- **Disc** (150px on a 1440px-wide screen): radial gradient, lit a little
  above centre: `#FFF0DA` 0% → `#FAC690` 36% → `#F29A5C` 80% → `#EA8A50` 100%.
- **Glow** around it (550px): `rgba(244,160,104,.7)` → `rgba(246,180,136,.32)`
  at 40% → clear.
- **Warm band** on the sky above the snow: clear → `rgba(240,170,128,.5)`.
- It sits at **62% across**, in the lowest dip of the top snow edge, so the
  snow hides its lower part. Always peeking or rising, never high in the sky.
- **Dark mode:** the sun never clears the snow; only a cap and a faint glow
  (glow `rgba(242,170,120,.3)`).
- Soft apricot glows on the sky: `rgba(242,196,160,.55)` and
  `rgba(236,206,186,.45)`, radial, fading to clear.

### Snow and ice

Five layers, light at the surface, deeper as you dig down. The default is
**Personal** (glacier blue):

| Layer | Light | Dark |
|---|---|---|
| `--s1` surface (fresh) | `#DCE5EB` | `#536777` |
| `--s2` settled | `#C3D3DE` | `#4A5B69` |
| `--s3` packed | `#A6BFCF` | `#42505C` |
| `--s4` deep | `#8AABC0` | `#3B4350` |
| `--s5` glacier ice (footer) | `#6E98B2` | `#34353A` |

Each layer's colour is drawn a little darker (light: 80% layer colour mixed
with `#26394B`; dark: 90% with `#0B121B`) so the white crystals of the
texture bring it back up.

The snow takes on the light of the current space, but only a little (a hue
turn, same lightness), so it always reads as snow:

| Space | Its colour | Snow `--s1`…`--s5` (light) | Dark |
|---|---|---|---|
| Personal | Glacier `#7F9CB0` | as above | as above |
| Work | Sage `#8FAE8B` | `#DAE6E8` `#C0D5D8` `#A1C2C6` `#83AFB5` `#649DA4` | `#4D6A70` `#455E63` `#3D5257` `#35454D` `#32363A` |
| Kitchen | Sand `#C9A27E` | `#E1E3EC` `#CCD0E0` `#B3BAD2` `#9CA4C4` `#8690B7` | `#5F6379` `#55576A` `#4B4D5D` `#44404E` `#373439` |

Other space colours (dots and tints only): Lagoon `#6FA3A0`, Lilac `#8E8FB8`.

### Blue is for branding only

Logo, snow, ice, flakes and glows are blue. **Buttons, links and text are
never blue**: they stay in the warm neutrals above.

## How the snow is drawn

- **Edge:** a hand-cut ridge line across the full width, not a smooth wave.
  The real edges are in `design/firn-sunrise/tools/snow-edges.json`
  (`make-snow-edges.py` writes them into the CSS). Reuse them, don't draw new
  ones by eye.
- **Rim:** a thin bright line along the edge. Surface layer: 4px
  `rgba(255,240,222,.95)` (warm, it catches the sun); lower layers: 3px
  `rgba(255,255,255,.85)`. Dark: `rgba(255,222,196,.5)` and
  `rgba(214,230,244,.38)`.
- **Lip:** a few soft light bands just under the rim (`rgba(255,236,214,.1)`
  on the surface), kept inside the snow.
- **Texture:** `public/assets/snow-fresh.webp` (surface and settled) and
  `snow-packed.webp` (packed, deep, ice), tiled at 256px. Made by
  `make-snow-tiles.py` from the photos in `design/firn-sunrise/photos/`.
- **Light on the snow:** brighter at the top (`rgba(255,255,255,.2)` fading
  over 280px), deeper lower down (`rgba(14,32,50,.13–.2)`). The surface also
  gets a warm wash where the sun is: `rgba(255,206,160,.42)` at 62%.
- **Shadow:** each edge casts a faint shadow (`rgba(16,34,52,.032)`) on the
  layer above it.
- **One-edge version** (inner pages, a single screen): paper above, then one
  edge with its rim, over glacier ice (`--s5`, packed texture). The link
  preview uses the surface layer instead, so the sun can peek over it.

## Type

- **Headlines:** Gooper Deck, weight **400**; emphasis **600**, never
  heavier. Fallback Georgia. Emphasis is weight, **never colour**.
- **Everything else:** `system-ui, -apple-system, 'Segoe UI', sans-serif`
  (SF Pro on the Mac).
- Home headline: "A calm browser, **made for Mac.**" (the bold phrase never
  breaks across lines).
- Gooper Deck is licensed: never commit or share the font files.

## Logo and flakes

- Only the files in `public/assets/`: `firn-lockup.svg` (full colour, on
  paper), `firn-lockup-on-dark.svg` (on the sky, on ice, in dark mode),
  `firn-mark.svg` (the bare flake). Never redraw or re-type the wordmark
  (Gooper Condensed Medium, outlines only).
- **Drifting flakes:** a few faint Firn flakes on the sky (`#9DB7C8`, or the
  flake at low opacity). Never on or touching text. Hide them on small screens.

## Buttons, links and focus

- **Main button on paper:** ink background, paper text.
- **Main button on the dark sky:** `#F5F1EC` pill with `#2B2826` text,
  weight 600, fully rounded.
- **Small pill on the sky** (eyebrow): `rgba(245,241,236,.1)` fill,
  `rgba(245,241,236,.18)` border, light text.
- **Links:** ink (or muted), underlined 3px below the text.
- **Focus ring:** 3px solid frost: `#16304A` on light paper and light snow,
  `#CFE3EF` on the dark sky and in dark mode.
- **Frosted glass** for small floating panels only (menus, cards): semi-clear
  with a small blur. Never on large areas.

## Motion

- Hover and focus: 200ms, gentle.
- The sun rises as you scroll; the snow changes colour with the space over
  600ms. Home also has a few mouse touches (sun glints on the snow, the sky
  leaning toward the cursor, frost breath on the ice). That's the limit; don't
  add more.
- Everything moving is off with **Reduce motion**: the sun is simply risen.

## Voice

- Short, plain, warm sentences. First person from David where it's personal.
- **Serial (Oxford) comma, always:** "Vertical tabs, spaces, and split view".
- Every privacy claim must be literally true.

## Where to look

- The brief and the plan: `SUNRISE-BRIEF.md`, `DIG-DOWN-PLAN.md` (this folder)
- Live styles: `public/home.css`, `public/page.css`, `public/site.css`
- A single-screen example: `design/share-preview/og.html` (the link preview)
