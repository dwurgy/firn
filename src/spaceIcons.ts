// The icons a space can have: simple line icons drawn in Firn's own style
// (see src/ui/SpaceIcon.tsx), shown in the space's color. A space saves the
// icon's name, e.g. "home".

export const SPACE_ICON_NAMES = [
  'home',
  'work',
  'leaf',
  'book',
  'palette',
  'music',
  'game',
  'plane',
  'coffee',
  'bag',
  'heart',
  'star',
  'school',
  'camera',
  'mountain',
  'sun',
] as const;

export type SpaceIconName = (typeof SPACE_ICON_NAMES)[number];

// Spaces used to have emoji icons; each becomes the closest line icon.
const FROM_EMOJI: Record<string, SpaceIconName> = {
  '🏠': 'home',
  '💼': 'work',
  '🌿': 'leaf',
  '📚': 'book',
  '🎨': 'palette',
  '🎵': 'music',
  '🎮': 'game',
  '✈': 'plane',
  '☕': 'coffee',
  '🛒': 'bag',
  '💡': 'sun',
  '🧪': 'school',
  '🏔': 'mountain',
  '🌊': 'leaf',
  '⭐': 'star',
  '❤': 'heart',
};

export function isSpaceIcon(icon: unknown): icon is SpaceIconName {
  return SPACE_ICON_NAMES.includes(icon as SpaceIconName);
}

// A saved icon as one of today's icons (an old emoji becomes its match), or
// null if there's no match.
export function toSpaceIcon(icon: unknown): SpaceIconName | null {
  if (isSpaceIcon(icon)) return icon;
  if (typeof icon !== 'string') return null;
  return FROM_EMOJI[icon.replace(/️/g, '')] ?? null;
}
