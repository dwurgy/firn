Firn app icon: layers for Apple's Icon Composer (macOS 26 / 27 and later)
=========================================================================

FINAL: Firn.icon (in this folder) is Firn's Mac app icon on macOS 26 and
later: glacier gradient fill, the Firn flake as one glass layer; the dark
and tinted looks are left to macOS. The Mac build compiles it (see
"Getting it into Firn" below). Older Macs keep the glacier .icns.

Why: since macOS 26, Mac app icons are built from layers of "Liquid Glass".
A flat icon (our .icns) still works, but macOS guesses the layers and adds a
generic glass look. A layered icon lets macOS 27 give the Firn crystal its own
sharp glass edges, highlights and shadow, plus proper dark and tinted versions.

The layers (1024 x 1024, full square: macOS cuts the rounded shape itself)
  firn-icon-layer-1-background.svg   glacier gradient, #9DB7C8 (top) > #82A3B8 > #6E98B2 (bottom)
  firn-icon-layer-2-mark.svg         the Lean crystal in page white #FBFAF8, centred,
                                     about 61% of the width (same size as the current icon)

Doing it (on a Mac, about five minutes)
  1. Download Icon Composer from developer.apple.com (free).
  2. New document. Drag in firn-icon-layer-2-mark.svg as the only layer.
  3. Background: in the document's fill, choose a gradient from #9DB7C8 (top)
     to #6E98B2 (bottom). Or drag firn-icon-layer-1-background.svg in as the bottom
     layer and turn its glass effect off. The built-in fill is preferred.
  4. Mark layer: keep Liquid Glass on. Specular: Automatic. Shadow: neutral.
     Translucency: low (macOS 27 looks best with a fairly solid crystal).
  5. Check the Dark, Clear and Tinted previews. In Dark, the background can be
     charcoal #3A3734 with the mark in glacier #7F9CB0, like the dark tile.
  6. Save as AppIcon.icon.

Getting it into Firn (done)
  forge.config.mts hands Firn.icon to the packager next to assets/icon.icns.
  On a Mac with macOS 26+ and Xcode 26 (GitHub's Mac build), the packager
  compiles it with actool into Firn.app/Contents/Resources/Assets.car and
  sets CFBundleIconName; CFBundleIconFile still points at the .icns for
  older macOS. A Mac without Xcode 26 builds Firn with the .icns only.
  To change the icon: edit Firn.icon in Icon Composer and replace the folder.

Windows and Linux are not affected: they keep using the .ico and PNGs.
