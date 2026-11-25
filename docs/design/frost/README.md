# Frost: the approved welcome and "no tabs" designs for the Firn apps

Approved 24 Nov 2026. Frost replaces First light as the look for Firn's brand
moments: the welcome and the "no tabs" screen. Everyday screens do not change.

> **Changed since (David, 2026-11-24):** no lens in the apps, only the blurred
> logo; the lens is for the website's landing page. The Mac welcome's tips
> step is dropped. The drawings and BRAND.md still show the lens.

## What's here

- `BRAND.md`: the Frost brand sheet, with every value written out. Read the
  sections "The sky", "The horizon", "The blurred logo", "The lens", "Glass
  and buttons", "In the app", and "Keep it smooth".
- `welcome-mac/`: the Mac welcome at 1200 × 760, each in light and dark.
  - `hello`: the opening. Blurred logo, the lens resting on the name, one
    headline, one line, and the "Let's Begin" pill.
  - `search`: step 1 of 6. This is the pattern for every step: the small
    mark top left, a question on the left, the choices on the right, and
    along the bottom the step dots, "Skip setup", "Back", and one
    "Continue" pill.
  - `space`: step 3 of 6, the same pattern with a text field and colors.
  - `welcome-in`: the finish. The whole logo sharp, no lens, "Welcome in."
- `no-tabs-mac/`: the "no tabs" screen, light and dark. Not part of the
  welcome; a separate task.
- `welcome-iphone/`: Hello and Search for iPhone, light and dark. For the
  iPhone and iPad session only.
- `images/`: the blurred logo as ready-made pictures, at 2x, with clear
  backgrounds. Use these; never blur live.
  - `firn-lockup-blurred.png`: for light mode. 2704 × 1416 px. The logo
    inside is 2500 px wide (1250 pt), with 102 px (51 pt) of clear margin
    on every side for the blur to spread into.
  - `firn-lockup-blurred-on-dark.png`: for dark mode. Same size.
  - `firn-mark-blurred.png`: the flake for "no tabs". 1928 × 1928 px. The
    flake inside is 1520 px wide (760 pt), with 204 px (102 pt) of margin.
    Use it as a shape and fill it with the space's color.
  - Draw each at 85% opacity (the flake at 62% in light, 50% in dark), as
    BRAND.md says. The opacity is not baked into the pictures.

## Steps that have no drawing

The designs show Hello, Search, Space, and the finish. The other steps keep
their current words and controls and take the same layout as Search and
Space: question on the left, choices on the right, the same bottom row.

## How to read the `.dc.html` files

They come from a design tool. They are reference only.

- The screen's markup is between `<x-dc>` and `</x-dc>`. Sizes, colors, and
  spacing are in `<helmet><style>` and in inline `style="…"` attributes.
  CSS px equal points on the Mac.
- Ignore `<script src="./support.js">` and the script at the bottom.
- Light and dark values sit side by side in the `:root` rules.

## Three substitutions

1. **Font.** The designs use Fraunces as a stand-in. The app uses Gooper
   Deck from the git-ignored PrivateFonts folder, and falls back to the
   system serif in builds without it. Fraunces weight 300 becomes Gooper
   Deck Regular; Fraunces 500 becomes Gooper Deck SemiBold. Never commit
   the font files.
2. **Logo images.** `/_blob/e3257822…` is `brand/svg/firn-lockup.svg` and
   `/_blob/496d69a1…` is `brand/svg/firn-lockup-on-dark.svg`. The small
   mark (`/_blob/0d156ee2…`) is `brand/svg/firn-mark.svg`, and
   `/_blob/4d75049b…` is the cream mark for dark mode.
3. **Glass.** The designs fake frosted glass with CSS. The app uses
   Apple's real Liquid Glass with the "Frosty, no tint" formula.
