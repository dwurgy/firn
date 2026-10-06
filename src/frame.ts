// The window's frame around the page, shared by the main process and the UI
// (through the preload bridge), so both agree.

// macOS 26 and later (Liquid Glass) have rounder window corners (16pt).
export function isLiquidGlass(platform: string, systemVersion: string) {
  return platform === 'darwin' && parseInt(systemVersion, 10) >= 26;
}

// The page's corners. With Liquid Glass they follow the window's own corners:
// the window's 16pt less the 8pt inset, so the frame around the page is
// equally thick all the way round. Elsewhere, Firn's own 12px.
export function pageRadius(platform: string, systemVersion: string) {
  return isLiquidGlass(platform, systemVersion) ? 8 : 12;
}
