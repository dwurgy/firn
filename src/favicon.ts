// Picks the best icon a page offers. Sites often list several: a tiny
// favicon (sometimes an older design kept around), larger ones, and an "app
// icon" for phone home screens (apple-touch-icon). Basecamp tiles and tab
// rows look sharper with a bigger icon, and the bigger ones are more often
// the site's current logo.
//
// Preferred, in order:
// 1. A large regular icon (48px or more, or a scalable SVG): crisp and
//    see-through.
// 2. The app icon, when the site only lists small regular icons. It usually
//    sits on a solid square, so Firn rounds its corners (styles.css).
// 3. Whatever the engine picked (the page's first favicon).

export interface IconLink {
  rel: string; // e.g. "icon", "shortcut icon", "apple-touch-icon"
  href: string;
  sizes: string; // e.g. "32x32", "16x16 32x32", "any", or ""
  type: string; // e.g. "image/svg+xml", or ""
}

const LARGE = 48;
const SCALABLE = 512; // an SVG counts as this big

export function pickIcon(links: IconLink[], fallback: string): string {
  let bestRegular: { href: string; size: number } | null = null;
  let bestApp: { href: string; size: number } | null = null;
  for (const link of links) {
    if (!/^(https?:|data:image\/)/i.test(link.href)) continue;
    const rels = link.rel.toLowerCase().split(/\s+/);
    const size = sizeOf(link);
    if (rels.includes('icon')) {
      if (size >= LARGE && (!bestRegular || size > bestRegular.size))
        bestRegular = { href: link.href, size };
    } else if (
      rels.includes('apple-touch-icon') ||
      rels.includes('apple-touch-icon-precomposed')
    ) {
      // Unsized app icons are 180px by convention.
      const appSize = size || 180;
      if (!bestApp || appSize > bestApp.size)
        bestApp = { href: link.href, size: appSize };
    }
  }
  return bestRegular?.href ?? bestApp?.href ?? fallback;
}

// The largest size a link declares (0 if unknown).
function sizeOf(link: IconLink): number {
  const isSvg =
    /svg/i.test(link.type) || /\.svg(\?|#|$)/i.test(link.href.split('?')[0]);
  if (isSvg || /\bany\b/i.test(link.sizes)) return SCALABLE;
  let largest = 0;
  for (const match of link.sizes.matchAll(/(\d+)\s*x\s*(\d+)/gi))
    largest = Math.max(largest, Number(match[1]), Number(match[2]));
  return largest;
}

// Runs inside the page (in an isolated world) to list its icon links. Links
// meant for another color scheme (media="(prefers-color-scheme: dark)" and
// the like) are left out when they don't apply.
export const ICON_LINKS_SCRIPT = `
[...document.querySelectorAll('link[rel][href]')]
  .filter((l) => /(^|\\s)(icon|apple-touch-icon|apple-touch-icon-precomposed)(\\s|$)/i.test(l.rel))
  .filter((l) => !l.media || matchMedia(l.media).matches)
  .map((l) => ({ rel: l.rel, href: l.href, sizes: l.getAttribute('sizes') || '', type: l.type || '' }))
`;

// The same icon links, read from a page's HTML instead of the live page
// (for the welcome, which shows sites' icons without opening them).
// `dark`: links meant only for the other color scheme are left out.
export function iconLinksFromHtml(
  html: string,
  baseUrl: string,
  dark: boolean,
): IconLink[] {
  const links: IconLink[] = [];
  for (const [tag] of html.matchAll(/<link\b[^>]*>/gi)) {
    const attrs: Record<string, string> = {};
    for (const m of tag.matchAll(
      /([a-zA-Z:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))/g,
    ))
      attrs[m[1].toLowerCase()] = (m[2] ?? m[3] ?? m[4] ?? '').replace(
        /&amp;/g,
        '&',
      );
    const rel = attrs.rel ?? '';
    if (
      !/(^|\s)(icon|apple-touch-icon|apple-touch-icon-precomposed)(\s|$)/i.test(
        rel,
      ) ||
      !attrs.href
    )
      continue;
    const media = attrs.media ?? '';
    if (/prefers-color-scheme:\s*dark/i.test(media) && !dark) continue;
    if (/prefers-color-scheme:\s*light/i.test(media) && dark) continue;
    let href: string;
    try {
      href = new URL(attrs.href, baseUrl).href;
    } catch {
      continue;
    }
    links.push({ rel, href, sizes: attrs.sizes ?? '', type: attrs.type ?? '' });
  }
  return links;
}
