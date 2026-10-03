import type { ReactNode } from 'react';
import type { SpaceIconName } from '../spaceIcons';

// Firn's space icons: soft, rounded line drawings on a 16px grid, in the
// same style as the other icons (icons.tsx). They take the text color, so
// they can be shown in the space's color.
const DRAWINGS: Record<SpaceIconName, ReactNode> = {
  home: (
    <>
      <path d="M2.5 7.4 8 3l5.5 4.4" />
      <path d="M4 6.3v6.2a1 1 0 0 0 1 1h6a1 1 0 0 0 1-1V6.3" />
      <path d="M6.7 13.5v-3h2.6v3" />
    </>
  ),
  work: (
    <>
      <rect x="2" y="5" width="12" height="8.5" rx="1.6" />
      <path d="M5.8 5V3.9a1 1 0 0 1 1-1h2.4a1 1 0 0 1 1 1V5" />
      <path d="M2 9h12" />
    </>
  ),
  leaf: (
    <>
      <path d="M13.3 2.7C7.3 2.7 3 5.9 3 11.1c0 .6.1 1.2.2 1.7 5.6 0 10.1-3.3 10.1-10.1Z" />
      <path d="M3.2 12.8 9.3 6.7" />
    </>
  ),
  book: (
    <>
      <path d="M8 4.3C6.6 3.3 4.6 2.9 2.5 3.1v9.5c2.1-.2 4.1.2 5.5 1.2 1.4-1 3.4-1.4 5.5-1.2V3.1c-2.1-.2-4.1.2-5.5 1.2Z" />
      <path d="M8 4.3v9.5" />
    </>
  ),
  palette: (
    <>
      <path d="M8 2.5C4.9 2.5 2.5 4.9 2.5 8s2.4 5.5 5.5 5.5c.9 0 1.3-.6 1-1.4-.3-.9.3-1.6 1.2-1.6h1.5c1 0 1.8-.8 1.8-1.8C13.5 5 11 2.5 8 2.5Z" />
      <circle cx="5.3" cy="7.4" r=".75" fill="currentColor" stroke="none" />
      <circle cx="7.3" cy="5.1" r=".75" fill="currentColor" stroke="none" />
      <circle cx="10.2" cy="5.5" r=".75" fill="currentColor" stroke="none" />
    </>
  ),
  music: (
    <>
      <path d="M6 12V4.1l7-1.5v8" />
      <circle cx="4.4" cy="12" r="1.6" />
      <circle cx="11.4" cy="10.6" r="1.6" />
    </>
  ),
  game: (
    <>
      <path d="M5.1 5h5.8a3.4 3.4 0 0 1 3.2 4.5l-.6 1.9a1.5 1.5 0 0 1-2.6.5l-1.1-1.3H6.2l-1.1 1.3a1.5 1.5 0 0 1-2.6-.5l-.6-1.9A3.4 3.4 0 0 1 5.1 5Z" />
      <path d="M5.2 7v2.2M4.1 8.1h2.2" />
      <path d="M10.4 7.5h.01M11.6 8.7h.01" />
    </>
  ),
  plane: (
    <path d="M13.5 2.5c.6.6.5 1.5-.1 2.1L11.1 7l1.4 5.4-1.1 1.1-2.6-4.5-2.2 2.2.3 1.7-.9.9-1.2-2.3-2.3-1.2.9-.9 1.7.3L7.3 7.5 2.8 4.9l1.1-1.1 5.4 1.4 2.4-2.3c.6-.6 1.5-.7 2-.1Z" />
  ),
  coffee: (
    <>
      <path d="M3 6.2h8v4.3a3 3 0 0 1-3 3H6a3 3 0 0 1-3-3Z" />
      <path d="M11 7.2h.7a1.7 1.7 0 0 1 0 3.4H11" />
      <path d="M5.6 2.6v1.6M8.4 2.6v1.6" />
    </>
  ),
  bag: (
    <>
      <path d="M3.4 5.6h9.2l-.7 7a1 1 0 0 1-1 .9H5.1a1 1 0 0 1-1-.9Z" />
      <path d="M6 7.3V5a2 2 0 0 1 4 0v2.3" />
    </>
  ),
  heart: (
    <path d="M8 13.2S2.5 10 2.5 6.2A2.9 2.9 0 0 1 8 4.8a2.9 2.9 0 0 1 5.5 1.4C13.5 10 8 13.2 8 13.2Z" />
  ),
  star: (
    <path d="m8 2.4 1.7 3.5 3.8.5-2.8 2.7.7 3.8L8 11.1l-3.4 1.8.7-3.8-2.8-2.7 3.8-.5Z" />
  ),
  school: (
    <>
      <path d="M1.8 6.2 8 3.2l6.2 3L8 9.2Z" />
      <path d="M4.5 7.6v3c1 .9 2.2 1.4 3.5 1.4s2.5-.5 3.5-1.4v-3" />
      <path d="M14.2 6.2v3.3" />
    </>
  ),
  camera: (
    <>
      <path d="M2.5 5.6a1 1 0 0 1 1-1h1.9l1-1.5h3.2l1 1.5h1.9a1 1 0 0 1 1 1v6.4a1 1 0 0 1-1 1h-9a1 1 0 0 1-1-1Z" />
      <circle cx="8" cy="8.6" r="2.3" />
    </>
  ),
  mountain: (
    <>
      <path d="M1.8 13 6.3 5.3l2.5 4 1.5-2.2 3.9 5.9Z" />
      <path d="m4.6 8.2 1.7.9 1.4-.9" />
    </>
  ),
  sun: (
    <>
      <circle cx="8" cy="8" r="2.6" />
      <path d="M8 1.8v1.3M8 12.9v1.3M1.8 8h1.3M12.9 8h1.3M3.6 3.6l.9.9M11.5 11.5l.9.9M3.6 12.4l.9-.9M11.5 4.5l.9-.9" />
    </>
  ),
};

export function SpaceIcon({
  name,
  size = 16,
}: {
  name: string;
  size?: number;
}) {
  const drawing = DRAWINGS[name as SpaceIconName];
  if (!drawing) return null;
  return (
    <svg
      className="space-icon"
      data-icon={name}
      width={size}
      height={size}
      viewBox="0 0 16 16"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.5}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden
    >
      {drawing}
    </svg>
  );
}
