# Firn brand

The logo and app icons, made with Claude Design. The mark is a firn crystal
("Drift · Lean"): an abstract, hand-shaped crystal of settled alpine snow,
with six soft, uneven arms. The wordmark is "firn" in Fraunces (soft),
converted to outlines.

**Everything in this folder is final.** Earlier explorations (other marks,
other fonts) are kept only in the Firn design system, never here. If a file
isn't listed below, don't use it.

- `svg/` – the mark, wordmark ("firn") and lockups for light, dark and
  Glacier backgrounds, plus the Glacier app icon artwork.
- `app-icons/` – ready-made Glacier app icons (Windows `.ico`, macOS `.icns`,
  PNGs from 16 to 1024px).
- `favicon/` – favicons (16–512px, `.ico`, `.svg`) for firnbrowser.com.
  Tab favicon = bare flake (glacier-deep, lighter on dark themes).
  Home-screen icons (180/192/512) = glacier tile.
- `icon-composer/` – **`Firn.icon`, the final Mac app icon** for macOS 26+
  ("Liquid Glass", made in Apple's Icon Composer), plus the two layer SVGs
  it was made from and step-by-step notes.

Firn itself uses the **Glacier** app icon, copied into `../assets/`:

- Windows: `icon.ico` = `app-icons/firn-app-icon-windows-glacier.ico`
- macOS 26 and later: `icon-composer/Firn.icon` (the Liquid Glass icon),
  compiled by the Mac build on GitHub
- older macOS: `icon.icns` = `app-icons/firn-app-icon-macos-glacier.icns`
- Linux: `icon.png` = `app-icons/firn-app-icon-windows-glacier-512.png`

…and the mark (`svg/firn-mark.svg`) on its "No open tabs" page. The
`-small` SVGs are versions drawn for tiny sizes (taskbar, tabs); use them at
48px and under.

Colors: Glacier `#6E98B2` (mark) on frame sand `#E9E3DA`, page white
`#FBFAF8`, ink `#241F1B`, dark frame `#3A3734`. Type: Fraunces (soft) for the
wordmark and big headings only; the system UI font for everything else.

These files are Firn's name and logo: they aren't covered by the code's
open-source license (see "License" in the main README).
