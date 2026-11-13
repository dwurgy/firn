# From First light to Sunrise: the plan

Planned 2026-11-12. The welcome and the empty page move from "First light" to "Sunrise", the look of the new firnbrowser.com. Every value comes from `brand/BRAND.md` (a copy from `dwurgy/firn-site`; the site's CSS wins). Design work: Opus. Work on the `ios` branch, where both apps build from `Shared/`.

## What's there today

**`Shared/FirstLight.swift`** (361 lines, one file for both apps; the iOS twins are `#if os(…)` halves inside it):

- `FirstLightScene(spaceColor:part:sunRises:)`: the whole scene. `part` splits it for the Mac welcome's finish: `.back` (sky, sun, flakes) behind the rising window, `.front` (snow and grain) in front of it. `sunRises` lifts the sun 6% and fades a brighter one in over 1.2s.
- `FirstLightSky`: a `Canvas`, drawn once per size and look: a vertical gradient from a pale sky (`#F2F5F6`) to the page color, plus three soft hazes (cool high, warm low).
- `FirstLightSun`: two elliptical glows behind the snowline, centered across the window.
- `FirstLightSnow` / `SnowBand`: five smooth, wavy bands (SVG paths from the Electron app, in a 1280 × 200 box), stretched to the width, 25% of the height. Flat colors, no texture, no rims.
- `FirstLightFlakes`: four small Firn marks drifting in Core Animation (an AppKit view on the Mac, a UIKit twin on iOS).
- The paper grain (`FirstLightGrain` image, 412 KB in `Firn/Assets.xcassets`), multiplied over the snow.

**`Shared/Theme.swift`, `Theme.FirstLight`:** the sky, haze, and sun colors, the flake color, the grain's strength, and `snow(_:)`: glacier blues for Glacier, otherwise the space color mixed into the page (20–78%).

**Who uses it:**

| Where | File | What |
|---|---|---|
| Mac empty page | `Firn/PageArea.swift`, `Firn/PagePanes.swift` | `FirstLightScene(spaceColor:)`, whole |
| Mac welcome | `Firn/Welcome.swift` | `.whole` while it runs; `.back` and `.front` around the rising window for "Welcome in." |
| iPhone and iPad empty page | `Firn iOS/BrowserScreen.swift` | `FirstLightScene(spaceColor:)`, whole |
| iPhone overview's haze | `Firn iOS/OverviewHaze.swift` | only the grain image (not the scene; an everyday screen) |
| iPhone welcome | not built yet | `docs/IOS-PLAN.md`, phase 8 |

## What changes

- **The sky** becomes BRAND.md's blue hour, compressed for one screen ("For a single screen"): `#1C2130` at the top, then `#556079` → `#8D8C9E` → `#CDB8B4` → `#EAD3C5` packed just above the snow; dark stays blue hour all the way. Plus the two soft apricot glows. The old pale sky and three hazes go.
  - **This turns the top of the light-mode scene dark navy.** Text and buttons over the sky must be light in both modes (BRAND.md, "Text on the dark sky"): the Mac welcome's words, its buttons (the `#F5F1EC` pill), and the iPhone's status bar over the empty page.
- **The sun:** a disc (radial, lit above center), its glow, and a warm band on the sky above the snow, at **62% across**, in the lowest dip of the top snow edge, so the snow hides its lower part. Sizes scale with the width (disc 150 and glow 550 at 1440 wide). Dark: only a cap and a faint glow; the welcome's rise is capped so the sun never clears the snow.
- **The snow:** five layers instead of five bands, each with:
  - a **hand-cut edge** (the site's own, below),
  - a **rim** (4pt warm on the surface, 3pt white below; dark values in BRAND.md), and a few soft **lip** bands under it,
  - its color drawn a little darker (light: 80% layer + `#26394B`; dark: 90% + `#0B121B`) with the **snow texture** tiled over it at 256pt, so the white crystals bring it back up,
  - **light**: brighter at the top, deeper lower down, and on the surface a warm wash where the sun is,
  - a faint **shadow** from each edge onto the layer above.
- **The flakes** stay (BRAND.md keeps them): same Core Animation drift, now on the dark sky in `#9DB7C8`. Check their spots against where the welcome's words sit.
- **The paper grain** leaves the scene (the snow texture takes its place). The image stays for the iPhone overview's haze, renamed `PaperGrain` in the last step.

### Performance (CLAUDE.md, required)

Gradients, shapes, and static images only. The snow is drawn once per size, look, and space color in one `Canvas` (with `.drawingGroup()` if profiling says so), never per frame. A space change cross-fades the old snow into the new with opacity (BRAND.md says 600ms; today's is 400ms: see questions). Nothing redraws while idle; the flakes stay Core Animation. Reduce Motion: no drift, no rise, an instant color change.

## The snow texture

The site tiles two 256px images made from real snow photos: `snow-fresh.webp` (surface and settled) and `snow-packed.webp` (packed, deep, ice).

**Suggestion:** David copies the two files into this repo (I can't reach `firn-site`). They go in `Firn/Assets.xcassets` (shared by both apps, as the grain and the mark are) as `SnowFresh` and `SnowPacked`, tiled with `Image(…).resizable(resizingMode: .tile)` or a tiled image shading in the `Canvas`.

- **Format:** asset catalogs don't take WebP reliably, so convert once to PNG (lossless, simplest) or HEIC (smaller) with `sips`. If the site's tiles are 256 actual pixels, they'd look soft on Retina; the best is the 512px (2x) and 768px (3x) versions from `make-snow-tiles.py` if David can make them on the site's side; otherwise use the 256px ones as 1x and judge on screen.
- **Cost:** two grey-and-white noise tiles, roughly 30–150 KB each per scale depending on format and size, so about **0.2–0.6 MB** in all. For scale: the grain alone is 412 KB today, and the app is many MB (WebKit isn't in it, but Sparkle, Fraunces, the block lists, and the icons are). App thinning on iOS ships only the phone's scale. I'll measure the real numbers in step 1.
- **Keep the sources too:** the original WebP files next to `brand/BRAND.md` (`brand/sunrise/`), so a later update from the site is a copy and one `sips` command.

## The snow edges

The site's hand-cut edges are in `design/firn-sunrise/tools/snow-edges.json` (in `firn-site`).

**Suggestion:** David copies that file into `brand/sunrise/snow-edges.json`. A small script in this repo (`scripts/snow-edges.py`, run by hand, not at build time) turns it into Swift path data, just like today's `SnowBand.paths` (SVG strings drawn through the existing `SVGPath.cgPath`). The app ships no JSON and parses nothing at launch, and an update from the site is "copy the file, run the script". I'll read the file's format before writing the script; if it holds points instead of SVG paths, the script writes them as straight segments, as the site's CSS clip paths do.

Things to check once the file is here: how many edges it has (five layers, or more for other widths), the box they're drawn in, and whether the site uses a different edge or height on narrow screens (the iPhone is about 390pt wide; stretching a 1440-wide ridge into that may squash it, so the iPhone may want only part of the width, cropped around the 62% dip).

## Space colors

BRAND.md gives the snow for three spaces. Measured in OKLCH (the color space the site likely used): every row keeps Glacier's lightness and chroma exactly, and only the hue turns:

| Space | Its color | Snow hue turn |
|---|---|---|
| Glacier | `#7F9CB0` | 0° (base, hue ≈ 236°) |
| Sage | `#8FAE8B` | about −28° (toward teal) |
| Sand | `#C9A27E` | about +38° (toward periwinkle) |

So the turn isn't "toward the space's own hue" (Sand's shortest way would have been toward green); it's a chosen amount per space. **Suggestion:** one helper turns Glacier's ten snow colors (five light, five dark) by a per-space angle in OKLCH. A FirnCore test checks it reproduces BRAND.md's Sage and Sand rows to within one unit per channel, so the method is proven before it makes new colors. Then the other five need an angle each:

| Space | Its color | A starting guess, to judge on screen |
|---|---|---|
| Lagoon | `#6FA3A0` | −45° (sea-green snow) |
| Dusk | `#8E8FB8` | +18° (a touch violet) |
| Ochre | `#C4A95B` | +28° |
| Clay | `#B07F6A` | +50° |
| Heather | `#B88A9E` | +62° (lilac) |

The chroma is tiny (the surface is barely tinted), so eight snows can't all be far apart; neighbors will be close. That's in keeping with "only a little, so it always reads as snow". A preview page (`docs/sunrise-snow-colors.html`, eight rows, light and dark, each beside its space's dot) lets David pick before any Swift uses them. If the site later adds its own rows for these five, the site wins.

Note: BRAND.md calls Dusk "Lilac" and uses the space names Personal, Work, and Kitchen; the app's names stay Glacier, Sage, Sand, and so on.

## The steps

Each step builds both apps, keeps the Mac's and the iPhone's tests passing, and leaves everything looking finished (never half First light, half Sunrise on screen in a way that looks broken). The code stays in `FirstLight.swift` and `Theme.FirstLight` until the last step, so callers don't change mid-way.

1. **Files in, nothing visible** (Mac and iPhone build; nothing changes on screen). David copies `snow-fresh.webp`, `snow-packed.webp`, and `snow-edges.json` into `brand/sunrise/`, and pastes (or copies) the site's snow and sky CSS rules if BRAND.md leaves anything out (the texture's blend mode and strength, the lip bands, the snow's height on one screen; `design/share-preview/og.html` is the best single-screen example). I convert the tiles into the asset catalog, write `scripts/snow-edges.py`, and generate the edge paths (unused yet). Measure the app's size before and after.
2. **Snow colors** (no visible change). The OKLCH helper in FirnCore with its test (Sage and Sand match BRAND.md), the ten Glacier colors, and the preview page for the five other spaces. **David picks the five angles.** Then `Theme.FirstLight.snow(_:)` returns the new colors, but nothing draws them yet.
3. **The new snow, on the empty page** (Mac and iPhone/iPad, empty page only; the welcome too, since it shares the scene). Five textured layers with hand-cut edges, rims, lips, light, and shadows replace the wavy bands; the grain leaves the scene; the space change cross-fades. The old pale sky and sun stay above it for this step (a calm combination: light sky over textured snow). Check: light, dark, every space color, Reduce Motion, the Mac sidebar shown and hidden, iPhone portrait, iPad landscape and a narrow Stage Manager window, and that nothing redraws while idle.
4. **The sky and the sun** (same places). The compressed blue-hour sky, the apricot glows, and the sun at 62% in the top edge's dip; dark's capped sun. The iPhone's status bar turns light over the empty page. Now the empty page is Sunrise on Mac, iPhone, and iPad. The Mac welcome's words would be dark on a dark sky here, so **steps 4 and 5 ship together** (one branch state David checks at once), or step 4 keeps the welcome on the old sky with `part` for one commit.
5. **The Mac welcome on Sunrise** (Mac only). Words, the Hello mark, and buttons light on the sky (BRAND.md's pill, the small eyebrow pill, the light focus ring); the welcome's glass cards checked over the dark sky; the flakes kept clear of the words. "Welcome in.": `.back` is sky, sun, and flakes, `.front` is the snow, as today; the sun's rise is capped in dark. Check the finish frame by frame from a recording (light, dark, Reduce Motion).
6. **Rename** (Mac and iPhone; nothing visible). One rename-only commit, easy to check: `FirstLight.swift` → `Sunrise.swift`, `FirstLightScene` → `SunriseScene` (and its parts), `Theme.FirstLight` → `Theme.Sunrise`, `FirstLightGrain` → `PaperGrain`; the old Electron SVG paths deleted. Update CLAUDE.md, `docs/IOS-PLAN.md` (phase 8 becomes "Sunrise, and being the default browser"), and `docs/HISTORY.md`.
7. **A look over** (Mac, iPhone, iPad). Light, dark, Reduce Motion, Reduce Transparency, Increase Contrast (text on the sky), VoiceOver (the scene stays hidden from it), the eight spaces, Instruments for idle redraws and the first draw's time, and the app's size. The security check: nothing new (bundled images and colors only; no input, no network).

**The iPhone's welcome** isn't part of this: it doesn't exist yet. Phase 8 of `docs/IOS-PLAN.md` builds it directly on Sunrise.

**Why rename last, not first:** renaming first would mean files called Sunrise drawing First light for several steps, and every step's diff would mix a rename with real changes. Last, it's one commit with no behavior change.

## Questions for David

1. **The texture files and the edges:** can you copy `snow-fresh.webp`, `snow-packed.webp`, and `snow-edges.json` from `firn-site` into `brand/sunrise/` here? And, if easy, 2x and 3x versions of the tiles from `make-snow-tiles.py`?
2. **The CSS:** BRAND.md doesn't say how the texture sits on the color (blend mode, strength) or how tall the snow is on one screen. Could you paste the snow rules from `public/home.css` (or `og.html`), or should I judge them on screen?
3. **The five other snows:** pick angles from the preview page (step 2), or would you rather the site settle them first so both match?
4. **Color change timing:** BRAND.md says the snow changes over 600ms; the app does 400ms today. Match the site?
5. **The grain:** the scene drops it (the snow texture replaces it). Keep it on the iPhone overview's haze, as now?
6. **Fonts on the Mac:** the Mac welcome's headlines (and the Settings and History window titles) still use Fraunces; BRAND.md says Gooper Deck. Part of step 5, or its own step? (iOS already uses Gooper Deck; the empty page has no words on either.)
