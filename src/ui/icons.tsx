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

// Window buttons (Windows and Linux), drawn with the same stroke as above.

export const MinimizeIcon = () => (
  <svg {...base}>
    <path d="M3.5 8h9" />
  </svg>
);

export const MaximizeIcon = () => (
  <svg {...base}>
    <rect x="3.5" y="3.5" width="9" height="9" rx="1.5" />
  </svg>
);

export const RestoreIcon = () => (
  <svg {...base}>
    <rect x="3.5" y="5.5" width="7" height="7" rx="1.5" />
    <path d="M5.5 3.5h5.5a1.5 1.5 0 0 1 1.5 1.5v5.5" />
  </svg>
);

export const CloseIcon = () => (
  <svg {...base}>
    <path d="M4 4l8 8M12 4l-8 8" />
  </svg>
);

export const PlusIcon = () => (
  <svg {...base}>
    <path d="M8 3.5v9M3.5 8h9" />
  </svg>
);

// Shown for pages that have no icon of their own.
export const GlobeIcon = () => (
  <svg {...base} strokeWidth={1.4}>
    <circle cx="8" cy="8" r="5.5" />
    <path d="M2.5 8h11M8 2.5c1.6 1.6 2.3 3.4 2.3 5.5S9.6 11.9 8 13.5M8 2.5C6.4 4.1 5.7 5.9 5.7 8s.7 3.9 2.3 5.5" />
  </svg>
);

export const SearchIcon = () => (
  <svg {...base}>
    <circle cx="7" cy="7" r="4.5" />
    <path d="m10.5 10.5 3 3" />
  </svg>
);

export const ArrowIcon = () => (
  <svg {...base} width={14} height={14}>
    <path d="M3.5 8h9M9 4.5 12.5 8 9 11.5" />
  </svg>
);

// Show / hide the sidebar.
export const SidebarIcon = () => (
  <svg {...base}>
    <rect x="2.5" y="3.5" width="11" height="9" rx="2" />
    <path d="M6.5 3.5v9" />
  </svg>
);

// Stopping a page load uses the very same mark as closing the window.
export const StopIcon = CloseIcon;

// Points down at the everyday tabs that "Clear" closes.
export const ClearDownIcon = () => (
  <svg {...base} width={11} height={11} strokeWidth={1.7}>
    <path d="M8 3v9.5M4 9l4 4 4-4" />
  </svg>
);

// Lookout's "Open as tab": two corners pulling outward.
export const ExpandIcon = () => (
  <svg {...base}>
    <path d="M9.5 3.5h3v3M12.5 3.5 9 7M6.5 12.5h-3v-3M3.5 12.5 7 9" />
  </svg>
);

// "Separate split view": two panes drawing apart.
export const SeparateIcon = () => (
  <svg {...base}>
    <rect x="2.5" y="4" width="4.5" height="8" rx="1.2" />
    <rect x="9" y="4" width="4.5" height="8" rx="1.2" />
  </svg>
);

// A page from the history: a soft clock.
export const HistoryIcon = () => (
  <svg {...base} strokeWidth={1.4}>
    <circle cx="8" cy="8" r="5.5" />
    <path d="M8 5v3.2l2 1.3" />
  </svg>
);

// A quick action in the command bar: a small four-pointed spark.
export const ActionIcon = () => (
  <svg {...base} strokeWidth={1.4}>
    <path d="M8 2.8c.4 2.6 1.6 3.8 4.2 4.2v.1c-2.6.4-3.8 1.6-4.2 4.2h-.1c-.4-2.6-1.6-3.8-4.2-4.2V7c2.6-.4 3.8-1.6 4.2-4.2Z" />
  </svg>
);

// A pinned tab's "unload" button (a pin is never closed outright).
export const UnloadIcon = () => (
  <svg {...base}>
    <path d="M4.5 8h7" />
  </svg>
);

// Points down while a space's pins are showing, right while folded away.
export const ChevronIcon = () => (
  <svg {...base} width={12} height={12}>
    <path d="M4.5 6.5 8 10l3.5-3.5" />
  </svg>
);

export const MoreIcon = () => (
  <svg {...base} fill="currentColor" stroke="none">
    <circle cx="4" cy="8" r="1.15" />
    <circle cx="8" cy="8" r="1.15" />
    <circle cx="12" cy="8" r="1.15" />
  </svg>
);

export const UpIcon = () => (
  <svg {...base}>
    <path d="M4 10l4-4 4 4" />
  </svg>
);

export const DownIcon = () => (
  <svg {...base}>
    <path d="M4 6l4 4 4-4" />
  </svg>
);

export const DownloadIcon = () => (
  <svg {...base}>
    <path d="M8 2.8v7M5 7l3 3 3-3" />
    <path d="M3 12.8h10" />
  </svg>
);

export const FileIcon = () => (
  <svg {...base}>
    <path d="M4.5 2.5h4.6l2.9 2.9v7.1a1 1 0 0 1-1 1H4.5a1 1 0 0 1-1-1v-9a1 1 0 0 1 1-1Z" />
    <path d="M9 2.6v2.9h2.9" />
  </svg>
);

export const FolderIcon = () => (
  <svg {...base}>
    <path d="M2.5 4.5a1 1 0 0 1 1-1h2.6l1.5 1.6h4.9a1 1 0 0 1 1 1v5.9a1 1 0 0 1-1 1h-9a1 1 0 0 1-1-1Z" />
  </svg>
);

export const RetryIcon = () => (
  <svg {...base}>
    <path d="M3.4 8a4.6 4.6 0 1 0 1.35-3.25" />
    <path d="M3.2 2.8v2.6h2.6" />
  </svg>
);

export const MicIcon = () => (
  <svg {...base}>
    <rect x="5.8" y="2.3" width="4.4" height="7.4" rx="2.2" />
    <path d="M3.6 7.8a4.4 4.4 0 0 0 8.8 0M8 12.2v1.6" />
  </svg>
);

export const PinIcon = () => (
  <svg {...base}>
    <path d="M8 14s4.5-4.1 4.5-7.6a4.5 4.5 0 0 0-9 0C3.5 9.9 8 14 8 14Z" />
    <circle cx="8" cy="6.4" r="1.6" />
  </svg>
);

export const BellIcon = () => (
  <svg {...base}>
    <path d="M4 10.8V7.2a4 4 0 0 1 8 0v3.6l1 1.4H3Z" />
    <path d="M6.6 13.6a1.5 1.5 0 0 0 2.8 0" />
  </svg>
);

export const ClipboardIcon = () => (
  <svg {...base}>
    <rect x="3.5" y="3.2" width="9" height="10.5" rx="1.4" />
    <path d="M6 3.2a2 2 0 0 1 4 0" />
    <path d="M6 7.5h4M6 10h2.6" />
  </svg>
);

export const AppIcon = () => (
  <svg {...base}>
    <path d="M9 2.8h4.2V7M13.2 2.8 7.4 8.6" />
    <path d="M11.5 9.6v2.6a1 1 0 0 1-1 1h-6.7a1 1 0 0 1-1-1V5.5a1 1 0 0 1 1-1h2.6" />
  </svg>
);

export const CameraIcon = () => (
  <svg {...base}>
    <rect x="2" y="4.2" width="8.6" height="7.6" rx="1.6" />
    <path d="m10.6 7 3.4-2v6l-3.4-2" />
  </svg>
);

export const SiteIcon = () => (
  <svg {...base}>
    <path d="M3 5h5.5M11.5 5H13M3 11h1.5M7.5 11H13" />
    <circle cx="10" cy="5" r="1.5" />
    <circle cx="6" cy="11" r="1.5" />
  </svg>
);
