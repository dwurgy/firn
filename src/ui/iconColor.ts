import { useEffect, useState } from 'react';

// Picks out a favicon's main color, so the active pinned tile can glow in
// the site's own color (YouTube red, Gmail red, Todoist red, Notion none).
// Returns "r, g, b" for use in rgba(), or null for icons without a clear
// color (black, white or gray logos), which stay neutral.

const SIZE = 32; // icons are scaled down to this before looking at pixels
const HUE_BUCKETS = 24;
const cache = new Map<string, Promise<string | null>>();

export function useIconColor(favicon: string): string | null {
  const [color, setColor] = useState<string | null>(null);
  useEffect(() => {
    let current = true;
    setColor(null);
    if (favicon) iconColor(favicon).then((c) => current && setColor(c));
    return () => {
      current = false;
    };
  }, [favicon]);
  return color;
}

function iconColor(favicon: string) {
  let found = cache.get(favicon);
  if (!found) {
    found = window.firn
      .iconData(favicon)
      .then((data) => (data ? colorOf(data) : null))
      .catch(() => null);
    cache.set(favicon, found);
  }
  return found;
}

async function colorOf(dataUrl: string): Promise<string | null> {
  const image = new Image();
  image.src = dataUrl;
  await image.decode();
  const canvas = document.createElement('canvas');
  canvas.width = canvas.height = SIZE;
  const context = canvas.getContext('2d', { willReadFrequently: true });
  if (!context) return null;
  context.drawImage(image, 0, 0, SIZE, SIZE);
  const pixels = context.getImageData(0, 0, SIZE, SIZE).data;

  // Group the colorful pixels by hue and keep the biggest group.
  const buckets = Array.from({ length: HUE_BUCKETS }, () => ({
    weight: 0,
    r: 0,
    g: 0,
    b: 0,
  }));
  let opaque = 0;
  let colorful = 0;
  for (let i = 0; i < pixels.length; i += 4) {
    const [r, g, b, a] = [
      pixels[i],
      pixels[i + 1],
      pixels[i + 2],
      pixels[i + 3],
    ];
    if (a < 128) continue;
    opaque++;
    const [h, s, l] = toHsl(r, g, b);
    if (s < 0.3 || l < 0.15 || l > 0.9) continue; // grays, near-black, near-white
    const weight = s;
    const bucket = buckets[Math.floor(h * HUE_BUCKETS) % HUE_BUCKETS];
    bucket.weight += weight;
    bucket.r += r * weight;
    bucket.g += g * weight;
    bucket.b += b * weight;
    colorful += weight;
  }
  // Mostly black, white or gray: no tint.
  if (!opaque || colorful < opaque * 0.08) return null;

  // The strongest hue, together with its neighbors (hues near a bucket edge).
  let best = 0;
  const around = (i: number) =>
    [i - 1, i, i + 1].map((j) => buckets[(j + HUE_BUCKETS) % HUE_BUCKETS]);
  const total = (i: number) => around(i).reduce((sum, b) => sum + b.weight, 0);
  for (let i = 1; i < HUE_BUCKETS; i++) if (total(i) > total(best)) best = i;
  const group = around(best);
  const weight = total(best);
  const sum = (key: 'r' | 'g' | 'b') =>
    group.reduce((acc, b) => acc + b[key], 0) / weight;

  // Keep it pleasant: never washed out, never neon, never too dark.
  const [h, s, l] = toHsl(sum('r'), sum('g'), sum('b'));
  const [r, g, b] = fromHsl(h, clamp(s, 0.45, 0.8), clamp(l, 0.45, 0.6));
  return `${r}, ${g}, ${b}`;
}

const clamp = (value: number, min: number, max: number) =>
  Math.min(max, Math.max(min, value));

function toHsl(r: number, g: number, b: number): [number, number, number] {
  r /= 255;
  g /= 255;
  b /= 255;
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const l = (max + min) / 2;
  const d = max - min;
  if (!d) return [0, 0, l];
  const s = d / (1 - Math.abs(2 * l - 1));
  let h =
    max === r
      ? (g - b) / d + (g < b ? 6 : 0)
      : max === g
        ? (b - r) / d + 2
        : (r - g) / d + 4;
  h /= 6;
  return [h, s, l];
}

function fromHsl(h: number, s: number, l: number): [number, number, number] {
  const k = (n: number) => (n + h * 12) % 12;
  const a = s * Math.min(l, 1 - l);
  const f = (n: number) =>
    Math.round(255 * (l - a * Math.max(-1, Math.min(k(n) - 3, 9 - k(n), 1))));
  return [f(0), f(8), f(4)];
}
