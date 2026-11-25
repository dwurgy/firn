<!-- Brand sheet for Frost, Firn's look since 24 Nov 2026. Written from the approved designs on the "Firn" design canvas (https://claude.ai/artifact/SzAEmr51ke1cre4YwPavDm). Copy it into the site and app repos; once the site ships, its CSS wins. -->

# Firn brand sheet: Frost

Firn's look since 24 Nov 2026 (it replaced Sunrise): **a frosted window on a snowy morning. Everything outside is soft and out of focus, and one clear lens brings it into focus.** Quiet, cold air, and a hair of warm light low on the horizon. Firn sells the feeling, not the feature list: very few words, a lot of empty sky.

The values below are copied from the approved designs on the "Firn" design canvas (https://claude.ai/artifact/SzAEmr51ke1cre4YwPavDm). Once the site ships them, the site's CSS wins.

Three states, one window:

- **Out of focus** (home page, the welcome's Hello, the 404, the link preview): the logo, huge and blurred, on the sky.
- **The lens** (home, Hello, 404): one round piece of clear glass that shows whatever is under it sharp and slightly magnified.
- **In focus** (the welcome's "Welcome in."): the whole logo sharp, no lens. The fog has lifted.
- **Everyday pages and steps** (inner web pages, the welcome's steps): the plain sky, nothing behind the content.

## The sky

One plain vertical gradient, the same on every screen.

- **Light ("snowy morning"):** `sky-morning-top` `#D3DBDF` → `sky-morning-low` `#E9ECEA`.
- **Dark ("blue hour"):** `sky-night-top` `#151A27` → `sky-night-low` `#232B3F`.
- **Text:** `ink` `#241F1B` on the morning sky; `ink-night` `#E9E3DA` on blue hour. Muted: `ink-muted` `#5E564E` and `ink-muted-night` `#B9B2AA`.

## The horizon (light mode only)

A faint band of warmth along the bottom edge, like low sun on the horizon. It is something you feel before you see: if you can point to where it starts, it is too strong.

- Drawn over the sky from the bottom up: `horizon-1` `rgba(242,196,160,.20)` at the bottom → `horizon-2` `rgba(236,206,186,.11)` at 24% → clear at 58% of one screen.
- On long pages it has a fixed height: the same stops at 0, 200 px, and 480 px.
- **Never in dark mode**, and never from a corner or the top.

## The blurred logo

- The full-colour lockup on the morning sky; the on-dark (cream) lockup on blue hour.
- **Width:** `min(104vw, 1560px)`. The logo file has more empty space on the flake's side, so it is shifted left by 2.5% of its own width to put equal margins either side of the artwork.
- **Position:** centred in the open space above the footer text, not in the middle of the screen.
- **Blur:** 1.34% of the logo's width (20 px at a 1440 px screen, about 5 px on a phone), at 85% opacity. In the app this is a pre-blurred picture, never a live blur.

## The lens

- **Size:** radius `clamp(104px, 13vw, 190px)`.
- **What it does:** shows the sharp logo, and any text or buttons under it, magnified by 2.8%.
- **Rim:** a 1 px hairline `rgba(255,255,255,.35)`, a 1 px outer line `rgba(36,31,27,.09)`, and a soft shadow `0 12px 40px rgba(36,31,27,.17)`.
- **Lit edge, light mode (from the horizon, so along the bottom):** `inset 0 -3.5px 2px -1px rgba(255,238,220,.98)`, `inset 0 2.5px 2px -1px rgba(255,255,255,.4)`, at 70% opacity, with a warm halo beneath: `0 9px 18px -9px rgba(242,188,146,.4)`.
- **Lit edge, dark mode (top left, no warmth):** `inset 3px 3px 2px -1px rgba(233,227,218,.6)`, `inset -2px -2px 2px -1px rgba(233,227,218,.18)`; shadow `rgba(0,0,0,.4)`.
- **Clear, never bubbly:** no inner gloss, no haze. It is the one clear thing on a frosted page.
- **On the website it follows the pointer, slowly:** it eases up to a top speed of 13% of the page width per second (never less than 120 px a second) × 0.8, and eases to a stop. It can go anywhere on the page. Left alone for 5 seconds it drifts along the name. On a phone, tap or drag moves it. The system pointer stays visible.
- **In the app it sits still** on the name. Nothing moves while idle.

## Glass and buttons

- **The frosted pill** ("Frosty, no tint", the same idea as the app's Liquid Glass formula): fill `rgba(255,255,255,.5)` (dark: `rgba(44,53,76,.5)`), a 20 px blur behind it, a 1 px hairline, the lit edge on the same side as the lens's, and the shadow `0 8px 28px`. Fully rounded. Text in ink.
- **One pill per screen.** Everything else is a plain text link, underlined.
- **Choice cards** (the welcome): the same frosted fill at 16–18 px corners; the selected one has a 1.5 px ink outline and an ink check.
- **Tags** (release notes): outline only, 7 px corners, no fill. Platform tag `rgba(36,31,27,.6)`, version tag `rgba(36,31,27,.26)`.
- **In the app, use Apple's real Liquid Glass** for these, never the CSS imitation.

## Snow

Soft, out-of-focus flakes drifting down at three depths: tiny and sharp, medium, and large and very blurred. White on the morning sky; cream at about half strength on blue hour. Density is low (about one flake per 53,000 px²). Never snowflake shapes. Off with **Reduce motion**. Website only.

## The logo in dark mode

**Always cream on dark:** the on-dark lockup, and the cream flake (`firn-mark-on-dark.svg`) when the flake stands alone. The one exception is the "no tabs" screen, where the blurred flake takes the space's colour.

## In the app

Frost is for **moments, never everyday browsing**.

- **The welcome:** Hello is out of focus with the lens resting on the name; the steps are the plain sky with a question on the left and the choices on the right; "Welcome in." is fully in focus.
- **The "no tabs" screen:** the sky, the horizon, and one very large flake (about as wide as the page is tall) running off the right edge, blurred (about 4.5% of its width) and tinted in the space's colour at 62% opacity (50% in dark). No words, no lens.
- **Settings and other everyday screens** stay plain warm paper.
- **Not in** scam warnings, Lookout, the command bar, menus, or downloads.

## Keep it smooth

No live blur on anything large: the blurred logo is a picture. When nothing moves, nothing runs. Everything moving is off with Reduce motion.

## Website (firnbrowser.com)

Redesigned 24 Nov 2026 around Frost. The home page is **one screen that says almost nothing**: the blurred logo, the lens, one line, and one button.

- **Home:** no header. Bottom left: "A calm browser **for Mac, iPhone, and iPad.**" and a quiet row of links (Privacy, Release notes, Tip jar). Bottom right: one frosted pill, "Download", and the small print "Free. Needs macOS 14 or later."
- **Download by device:** on a Mac (or any computer) the pill fetches the Mac app. On an iPhone or iPad it links to the App Store.
- **Inner pages** (Release notes, Support, Privacy, Tip jar, Press kit, /mac): the same sky, completely still. The small logo top left is the only header and links home. One narrow column (620 px) set left of centre, a Gooper Deck headline, system-font body. At the bottom: one row of links (Download, Release notes, Support, Privacy, Tip jar, Press kit) and "Firn · A David Wurgler app · © 2026", with the name linked to davidwurgler.com. No nav bar, no phone menu, no footer columns.
- **Release notes:** a month rail on the left to jump around, a text filter (All, Mac, iPhone and iPad), and each entry as date, a plain-English headline, then outline tags for the platform and version.
- **Support** includes the FAQ: questions first, then "Still stuck?" with email and GitHub Issues.
- **404:** the home page with "Nothing here. **Just snow.**" and a link home.
- **Link preview** (1200 × 630): dark. The cream logo blurred on blue hour, no lens, with the tagline sharp at the bottom left. People see blue hour in the feed and arrive in the morning.
- **Dark mode** follows the visitor's system.
- **Privacy:** no third-party scripts, fonts, cookies, or forms; fonts load from fonts.firnbrowser.com. The page runs a few lines of its own script to tell a phone from a Mac and to move the lens. Pointer position is used on the page only, never stored or sent.
