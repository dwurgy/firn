// Firn's own simple line icons. Soft, rounded strokes to match the calm feel.

const base = {
  width: 16,
  height: 16,
  viewBox: '0 0 16 16',
  fill: 'none',
  stroke: 'currentColor',
  strokeWidth: 1.6,
  strokeLinecap: 'round' as const,
  strokeLinejoin: 'round' as const,
  'aria-hidden': true,
};

export const BackIcon = () => (
  <svg {...base}>
    <path d="M9.5 3.5 5 8l4.5 4.5" />
  </svg>
);

export const ForwardIcon = () => (
  <svg {...base}>
    <path d="M6.5 3.5 11 8l-4.5 4.5" />
  </svg>
);

export const ReloadIcon = () => (
  <svg {...base}>
    <path d="M12.6 8a4.6 4.6 0 1 1-1.35-3.25" />
    <path d="M12.8 2.8v2.6h-2.6" />
  </svg>
);

export const StopIcon = () => (
  <svg {...base}>
    <path d="M4.5 4.5l7 7M11.5 4.5l-7 7" />
  </svg>
);
