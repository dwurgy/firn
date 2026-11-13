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
- **The sun** (`.sunrise` in `home.css`): a 300pt strip on the sky just above the surface, holding a warm **band** (clear to `rgba(240,170,128,.5)` at its bottom), a **halo** (720pt tall, radial at 62%, `rgba(244,184,140,.55)` to clear), the **glow** (550pt, its bottom 244pt below the strip's; `rgba(244,160,104,.7)` → `rgba(246,180,136,.32)` at 40% → clear), and the **disc** (150pt, its bottom 44pt below the strip's, radial lit at 50% 40%: `#FFF0DA` → `#FAC690` 36% → `#F29A5C` 80% → `#EA8A50`), all at **62% across**, in the lowest dip of the top snow edge, so the snow hides the disc's lower part. The site's rise moves disc and glow down by 300 × (1 − r) and fades band and halo from .36 to 1; the welcome's finish can use the same r. Dark: disc and glow sit 78pt lower (only a cap shows), a fainter band (`rgba(242,190,150,.2)`), halo (.2), and glow (.3 → .1 at 45%). Sizes may need scaling on the iPhone; judge on screen.
- **The snow:** five layers instead of five bands, each overlapping the one above by its edge height and cut along a **hand-cut edge** (the site's own, below). Inside each layer, drawn bottom to top with plain normal layering (the site uses no blend modes, filters, masks, or opacity groups; `.lay` in firn-site's `public/home.css`, about line 297):
  1. **Base color**, the layer's snow color pushed darker: light `mix(s, #26394B)` at 80% s; dark 90% s with `#0B121B` (84% for layer 2 in dark).
  2. **Texture**, tiled at 256pt: `snow-fresh` on layers 1 and 2, `snow-packed` on 3 to 5. White with only the alpha changing, so one tile sits on any color.
  3. **Veil**, the layer's own color over the texture to soften the grain: 0% in light, 42% in dark.
  4. **Deep**, a vertical gradient from clear at 30% of the layer's height to `rgba(14,32,50,.13)` at its bottom (.16, .18, .20 for layers 3, 4, 5). Dark: `rgba(4,8,14,.2)`, and .24 for layers 3 to 5.
  5. **Lift**, from `rgba(255,255,255,.2)` at the layer's top to clear 280pt down (dark: .07).
  6. **Surface only, a warm wash** where the sun is: a radial gradient at 62% across, at the top, 70% wide and 420pt tall, `rgba(255,206,160,.42)` to clear (dark: 380pt, `rgba(242,170,120,.14)`).
  7. **Crest** (a strip 1.6 × the edge height): five **lip** bands (the edge shifted down 0.05, 0.11, 0.19, 0.30, 0.45 × the edge height, filled above, `rgba(255,255,255,.06)` each; surface `rgba(255,236,214,.1)`; dark `rgba(220,234,246,.04)` and surface `rgba(255,214,180,.05)`), then the **rim** along the edge: 3pt `rgba(255,255,255,.85)`, surface 4pt `rgba(255,240,222,.95)`; dark `rgba(214,230,244,.38)` and surface `rgba(255,222,196,.5)`.
  8. **Shadow** at the layer's bottom, cast by the next layer's edge: ten copies of that edge shifted up by 0.6 × (i/10)^1.6 × the edge height (i = 1…10), each filled below at `rgba(16,34,52,.032)` (dark `rgba(2,6,12,.06)`), so it fades smoothly.
  - **Edge heights:** 64pt, and 96pt for the surface; the site uses 36pt and 56pt under 600pt wide (so the iPhone in portrait, and narrow iPad windows).
- **The flakes** stay (BRAND.md keeps them): same Core Animation drift, now on the dark sky in `#9DB7C8`. Check their spots against where the welcome's words sit.
- **The paper grain** leaves the scene (the snow texture takes its place). The image stays for the iPhone overview's haze, renamed `PaperGrain` in the last step.

### Performance (CLAUDE.md, required)

Gradients, shapes, and static images only, in normal layering (as the site: no blend modes). The snow is drawn once per size, look, and space color in one `Canvas` (with `.drawingGroup()` if profiling says so), never per frame. A space change cross-fades the old snow into the new with opacity over 600ms (the site's `transition: background-color .6s`; today's app uses 400ms: see questions). Nothing redraws while idle; the flakes stay Core Animation. Reduce Motion: no drift, no rise, an instant color change.

## The snow texture

The site tiles two images made from real snow photos (`make-snow-tiles.py` in firn-site): `snow-fresh.webp` (surface and settled) and `snow-packed.webp` (packed, deep, ice). Each is **512px shown at 256pt, so already @2x**, and is pure white with only the alpha changing (crystals opaque, shadowed grain clear). **Copied into `brand/sunrise/`** (2026-11-12), with `snow-edges.json`. No @3x (David: the tiles stay @2x; the iPhone's empty page uses them too, scaled up, which noise texture hides well; judge on the phone).

**Suggestion: ship the WebP files as they are, about 84 KB for both.** Put them in the app bundle as plain resources (both targets), not the asset catalog, and load each once with `NSImage`/`UIImage` (both decode WebP on macOS 14 and iOS 26), cached in a static. Drawing them in the `Canvas` as a tiled image shading at 256pt. Converted to PNG for the asset catalog they'd be about 260 KB (measured); HEIC is about 270 KB. Either is small (the grain alone is 412 KB), so if loading WebP outside the catalog causes any trouble, PNG in `Assets.xcassets` (marked @2x) is the fallback. A later update from the site is a copy into `brand/sunrise/` and into the bundle.

## The snow edges

`brand/sunrise/snow-edges.json` (copied from firn-site's `design/firn-sunrise/tools/`) holds five edges, `l1` to `l5`, each **121 points**: x in percent of the width (0 to 100), y from 0 (the edge's highest point) to 1 (its lowest), multiplied by the layer's edge height (64pt, 96pt for the surface). The site joins them with straight lines (`make-snow-edges.py` writes them into CSS clip paths and the crest and shadow SVGs). So they stretch across any width, and the ridge's height stays fixed in points: no squashing on the iPhone, only a narrower ridge.

**Suggestion:** a small script in this repo (`scripts/snow-edges.py`, run by hand, never at build time) writes the five point lists into a Swift file as constant arrays. Firn builds each layer's shape from them (one polygon: the edge across the top, closed down the sides), and the crest's lip bands and the shadow's copies reuse the same points shifted, as the site does. The app ships no JSON and parses nothing at launch; an update from the site is "copy the file, run the script". The old Electron band paths go away.

## Space colors

The site's rule, from the comment above its snow colors in `home.css`: Personal's (Glacier's) colors **with the hue turned a little in OKLCH, same lightness and chroma**: Work 30% of the way toward its Sage, Kitchen 20% toward its Sand "by way of rose" (the long way round, through violet). "Full turns read as green or brown ground." Dark does the same. Measured, it checks out: Glacier's snow sits at hue ≈ 236°; Sage (hue 142°) gives −28°, and Sand (64°, reached through rose) gives +38°.

**Suggestion:** the same rule for the other five: 30% toward the cool and green colors by the short way, 20% toward the warm ones by way of rose. One helper turns Glacier's ten snow colors (five light, five dark) by the space's angle in OKLCH. A FirnCore test checks it reproduces BRAND.md's Sage and Sand rows to within one unit per channel, so the method is proven before it makes new colors.

| Space | Its color (OKLCH hue) | Rule | Snow turn | Snow hue |
|---|---|---|---|---|
| Lagoon | `#6FA3A0` (191°) | 30%, short way | −14° | 223° |
| Sage | `#8FAE8B` (142°) | 30%, short way | −28° (site) | 208° |
| Glacier | `#7F9CB0` | none | 0° | 236° |
| Dusk | `#8E8FB8` (284°) | 30%, short way | +14° | 250° |
| Heather | `#B88A9E` (351°) | 20%, by rose | +23° | 259° |
| Clay | `#B07F6A` (44°) | 20%, by rose | +34° | 270° |
| Sand | `#C9A27E` (64°) | 20%, by rose | +38° (site) | 274° |
| Ochre | `#C4A95B` (91°) | 20%, by rose | +43° | 279° |

The chroma is tiny (the surface is barely tinted), so neighbors will be close: Clay, Sand, and Ochre land within 9° of each other, and Lagoon and Dusk sit near Glacier. That fits "the same snow in every space, only the light on it shifts", but a preview page (`docs/sunrise-snow-colors.html`, eight rows of five layers, light and dark, each beside its space's dot) lets David see it, and nudge an angle, before any Swift uses them. If the site later adds rows for these five, the site wins.

Note: BRAND.md calls Dusk "Lilac" and uses the space names Personal, Work, and Kitchen; the app's names stay Glacier, Sage, Sand, and so on.

## The steps

Each step builds both apps, keeps the Mac's and the iPhone's tests passing, and leaves everything looking finished (never half First light, half Sunrise on screen in a way that looks broken). The code stays in `FirstLight.swift` and `Theme.FirstLight` until the last step, so callers don't change mid-way.

1. **Files in, nothing visible** (Mac and iPhone build; nothing changes on screen). The source files are already in `brand/sunrise/`. Add the two WebP tiles to both app targets as resources, write `scripts/snow-edges.py`, and generate the edge points (unused yet). Measure the app's size before and after. **Done (2026-11-13):** the tiles live in `Shared/Sunrise/` (both targets sync `Shared/`, so no project-file edit; they land at the bundle's top level), `scripts/snow-edges.py` writes `Shared/Sunrise/SnowEdges.swift` (`SnowEdges.layers`, surface first, x as a 0–1 fraction). Debug builds grew 124 KB (Mac) and 156 KB (iPhone).
2. **Snow colors** (no visible change). The OKLCH helper in FirnCore with its test (Sage and Sand match BRAND.md), the ten Glacier colors, and the preview page for all eight spaces. the five new rows use the rule as is (decided 2026-11-13: keep it subtle). Then `Theme.FirstLight.snow(_:)` returns the new colors, but nothing draws them yet. **Done (2026-11-13):** `SnowColors` in FirnCore (OKLCH, the rule, and Glacier's ten colors), tested: Sage and Sand match BRAND.md within one unit, and the eight turns match the table. The new colors are `Theme.FirstLight.sunriseSnow(_:)`, beside the old `snow(_:)` so nothing on screen changes; step 3 swaps them and deletes the old one.
3. **The new snow, on the empty page** (Mac and iPhone/iPad, empty page only; the welcome too, since it shares the scene). Five textured layers with hand-cut edges, rims, lips, light, and shadows replace the wavy bands; the grain leaves the scene; the space change cross-fades. The old pale sky and sun stay above it for this step (a calm combination: light sky over textured snow). Check: light, dark, every space color, Reduce Motion, the Mac sidebar shown and hidden, iPhone portrait, iPad landscape and a narrow Stage Manager window, and that nothing redraws while idle.
   **Done (2026-11-13; David checked it):** `FirstLightSnow` draws the five layers in one `Canvas` per look and space (`SnowLayers`), colors in `Theme.FirstLight.snow(_:dark:)` (the old `snow(_:)` and `sunriseSnow(_:)` are gone); the grain left the scene (the image stays for the iPhone overview). The snow takes 30% of the height (`snowShare`); each layer shows 1.15 × its ridge (the deepest 0.6), spare room shared evenly, and the ridges shrink when there isn't room (on a 800pt Mac window they're about 70% of the site's). On one screen the layers are thin, so the lift fades over the layer's own height (at most 280pt) and the surface's warm light shrinks with the ridges. A space change fades the new snow in over 600ms (question 2: matched to the site). Checked by rendering the scene off screen (Mac and iPhone sizes, light and dark); not yet in the running apps. To judge: whether the surface reads a little grey at its bottom (its deep and the next edge's shadow add up on a thin layer), the white rims' strength, and the snow's height.
4. **The sky and the sun** (same places). The compressed blue-hour sky, the apricot glows, and the sun at 62% in the top edge's dip; dark's capped sun. The iPhone's status bar turns light over the empty page. Now the empty page is Sunrise on Mac, iPhone, and iPad. The Mac welcome's words would be dark on a dark sky here, so **steps 4 and 5 ship together** (one branch state David checks at once), or step 4 keeps the welcome on the old sky with `part` for one commit.

   **Done (2026-11-13; David checked it):** chosen: step 4 keeps the Mac welcome on the old sky (`FirstLightScene(oldSky: true)`, which step 5 deletes), so the empty page can be checked alone. `SunriseSky` draws the sky, two apricot glows, and the sun in one `Canvas` per size and look, colors in `Theme.FirstLight.sky(dark:)`. The sky's stops run from the top to the middle of the surface's ridge (warm stops from 60% down; a first guess, no `og.html` to copy). The sun's strip ends at the surface's dip; disc and glow share a middle 31pt above it (78pt lower in dark), scaled 0.75–1 by window height, 0.5 under 600pt wide. The flakes turn `#9DB7C8` at 30% and are hidden under 600pt wide (BRAND.md). The iPhone's status bar turns light over the empty page through a see-through UIKit window that takes no touches (`Firn iOS/LightStatusBar.swift`; SwiftUI can't set it). Checked by rendering off screen (Mac and iPhone, light and dark); the status bar and touches through the overlay not yet checked on a device. To judge: where the warm colors start, the sun's size, and the apricot glows' strength.
5. **The Mac welcome on Sunrise** (Mac only). Words, the Hello mark, and buttons light on the sky (BRAND.md's pill, the small eyebrow pill, the light focus ring); the welcome's glass cards checked over the dark sky; the flakes kept clear of the words. "Welcome in.": `.back` is sky, sun, and flakes, `.front` is the snow, as today; the sun's rise is capped in dark. Check the finish frame by frame from a recording (light, dark, Reduce Motion).

   **Built (2026-11-13; not yet checked by David):** `oldSky`, the old sky and sun, and their colors are gone. On the sky, in both looks: Hello's words (`#F5F1EC`, muted `#D4CDC5`), its mark in the on-dark lockup's sand, the step dots, "Welcome in.", and Let's Begin as BRAND.md's light pill (`SkyButton`, with the 3pt `#CFE3EF` focus ring). Hello sits higher (its light words had reached the warm band). "Skip setup" sits on the snow, so it stays the ordinary glass button. The steps' card gets paper under its glass (`Theme.Welcome.cardBase`), so it reads as paper over the navy. The sun: `SunriseSky` is now three layers (sky; band and halo; glow and disc), each drawn once, and the site's rise moves them by offset and opacity only (`sunUp`): low through the welcome (r = 0.75, a sliver in light, hidden in dark), up over 1.2s with "Welcome in." (a cap in dark); Reduce Motion: always up. Fixed on the way: in the finish's front, the snow alone was centered in the window instead of at its bottom. A `welcome` demo shot (`scripts/demo-shots.sh … welcome`). Checked from real-window captures in demo mode (Hello and a card step, light and dark; the finish frame by frame, light and dark). Not checked: Reduce Motion, keyboard focus on the sky button, macOS 14/15. Then (David, 2026-11-13, question 4): the welcome's headlines (Hello, the steps' titles, and "Welcome in.") are Gooper Deck through `BrandFont.gooper` (`Firn/Typography.swift`); the Mac target got the iPhone's "Copy Private Fonts" step (script sandboxing off for it, as on the iPhone), and without the files the welcome falls back to Fraunces. Settings, History, and sheet titles keep Fraunces for now. Checked from captures, light and dark.
6. **Rename** (Mac and iPhone; nothing visible). One rename-only commit, easy to check: `FirstLight.swift` → `Sunrise.swift`, `FirstLightScene` → `SunriseScene` (and its parts), `Theme.FirstLight` → `Theme.Sunrise`, `FirstLightGrain` → `PaperGrain`; the old Electron SVG paths deleted. Update CLAUDE.md, `docs/IOS-PLAN.md` (phase 8 becomes "Sunrise, and being the default browser"), and `docs/HISTORY.md`.
7. **A look over** (Mac, iPhone, iPad). Light, dark, Reduce Motion, Reduce Transparency, Increase Contrast (text on the sky), VoiceOver (the scene stays hidden from it), the eight spaces, Instruments for idle redraws and the first draw's time, and the app's size. The security check: nothing new (bundled images and colors only; no input, no network).

**The iPhone's welcome** isn't part of this: it doesn't exist yet. Phase 8 of `docs/IOS-PLAN.md` builds it directly on Sunrise.

**Why rename last, not first:** renaming first would mean files called Sunrise drawing First light for several steps, and every step's diff would mix a rename with real changes. Last, it's one commit with no behavior change.

## Questions for David

Answered (David, 2026-11-12): the tiles are 512px at 256pt (@2x, no @3x), about 84 KB; normal layering, no blend mode; `.lay` in `home.css` has the base mix, the dark veil, the darkening gradient, and the top lift (all above). Files copied from firn-site read-only.

Decided (David, 2026-11-13, after `docs/sunrise-snow-colors.html`): **the snow stays subtle**; it must never change color wildly between spaces (the old First light snow, mixing the space color in at up to 78%, did, and felt lame). So the five other snows use the site's rule as it is (the table above, no nudges). Near-twins (Clay, Sand, and Ochre; Lagoon and Dusk beside Glacier) are fine: the space's color shows in its name and dots, not loudly in the snow. Any later tweak only makes the turns smaller, never larger.

Still open:

1. **How tall the snow is on one screen:** on the site each layer is a whole section of the page; on one screen the five layers have to share the bottom. Judge on screen (starting near today's 25% of the height, the surface's edge at the sun's dip), unless firn-site's `og.html` has a single-screen version to copy.
2. **Color change timing:** the site changes the snow over 600ms; the app does 400ms today. Match the site?
3. **The grain:** the scene drops it (the snow texture replaces it). Keep it on the iPhone overview's haze, as now?
4. **Answered (David, 2026-11-13): Gooper Deck for the Mac welcome now.** Was: **Fonts on the Mac:** the Mac welcome's headlines (and the Settings and History window titles) still use Fraunces; BRAND.md says Gooper Deck. Part of step 5, or its own step? (iOS already uses Gooper Deck; the empty page has no words on either.)
