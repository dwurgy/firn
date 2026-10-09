// Firn's keyboard shortcuts, in one list: the main process matches keys
// against it (src/main.ts, handleShortcut), and Settings' Keyboard
// shortcuts page shows it (src/ui/Shortcuts.tsx), so the page can't drift
// from what the keys really do. Shortcuts can't be changed (a deliberate
// "no": it serves few people and adds a lot to explain).
//
// Keys are written like "Mod+Shift+T":
// - Mod is Ctrl, or ⌘ on a Mac; Ctrl is always the Control key; Meta is ⌘
//   (or the Windows key); Alt is ⌥ on a Mac.
// - The last part is the key: a letter or sign as typed ("T", ",", "["),
//   or a name ("Tab", "Escape", "F5", "ArrowLeft"). "1-8" means any of
//   those digits (the number is passed on), and "Digit1-9" the same keys
//   by position (for Shift+1, which types "!").
// A key matches when every modifier it names is held (others don't
// matter), so a list's earlier entries win: Mod+Shift+T comes before
// Mod+T.

export type ShortcutId =
  | 'next-tab'
  | 'previous-tab'
  | 'escape'
  | 'diagnostics'
  | 'pin'
  | 'sidebar'
  | 'address'
  | 'find'
  | 'history'
  | 'settings'
  | 'find-previous'
  | 'find-next'
  | 'zoom-in'
  | 'zoom-out'
  | 'zoom-reset'
  | 'reopen-tab'
  | 'new-tab'
  | 'close-tab'
  | 'space-number'
  | 'last-tab'
  | 'tab-number'
  | 'back'
  | 'forward'
  | 'hard-reload'
  | 'reload'
  | 'dev-tools';

export type ShortcutGroup = 'Tabs' | 'Spaces' | 'Pages' | 'Firn';

export interface Shortcut {
  id: ShortcutId;
  // What it does, in plain words, for the page.
  label: string;
  group: ShortcutGroup;
  // The keys that do it (any of them).
  keys: string[];
  // Different keys on a Mac.
  mac?: string[];
  // What the page shows, if not all of `keys` (spare spellings of the same
  // key are left out, and ranges can read "1 – 8").
  show?: string[];
  macShow?: string[];
  // Not on the page (for working out problems).
  hidden?: true;
}

export const SHORTCUTS: Shortcut[] = [
  {
    id: 'previous-tab',
    label: 'Switch to the previous tab you used',
    group: 'Tabs',
    keys: ['Ctrl+Shift+Tab'],
    hidden: true,
  },
  {
    id: 'next-tab',
    label: 'Switch between recent tabs',
    group: 'Tabs',
    keys: ['Ctrl+Tab'],
  },
  {
    id: 'escape',
    label: 'Close Lookout',
    group: 'Pages',
    keys: ['Escape'],
  },
  {
    id: 'diagnostics',
    label: 'Print what each layer is doing',
    group: 'Firn',
    keys: ['Mod+Shift+D'],
    hidden: true,
  },
  {
    id: 'pin',
    label: 'Pin or unpin the tab',
    group: 'Tabs',
    keys: ['Mod+D'],
  },
  {
    id: 'sidebar',
    label: 'Hide or show the sidebar',
    group: 'Firn',
    keys: ['Mod+S'],
  },
  {
    id: 'address',
    label: 'Type an address or search',
    group: 'Pages',
    keys: ['Mod+L'],
  },
  {
    id: 'find',
    label: 'Find on the page',
    group: 'Pages',
    keys: ['Mod+F'],
  },
  {
    id: 'history',
    label: 'History',
    group: 'Firn',
    keys: ['Mod+H'],
    mac: ['Mod+Y'],
  },
  {
    id: 'settings',
    label: 'Settings',
    group: 'Firn',
    keys: ['Mod+,'],
  },
  {
    id: 'find-previous',
    label: 'Previous match',
    group: 'Pages',
    keys: ['Shift+F3', 'Mod+Shift+G'],
    show: ['Shift+F3'],
    macShow: ['Mod+Shift+G'],
  },
  {
    id: 'find-next',
    label: 'Next match',
    group: 'Pages',
    keys: ['F3', 'Mod+G'],
    show: ['F3'],
    macShow: ['Mod+G'],
  },
  {
    id: 'zoom-in',
    label: 'Zoom in',
    group: 'Pages',
    keys: ['Mod+=', 'Mod++'],
    show: ['Mod+='],
  },
  {
    id: 'zoom-out',
    label: 'Zoom out',
    group: 'Pages',
    keys: ['Mod+-', 'Mod+_'],
    show: ['Mod+-'],
  },
  {
    id: 'zoom-reset',
    label: 'Actual size',
    group: 'Pages',
    keys: ['Mod+0'],
  },
  {
    id: 'reopen-tab',
    label: 'Reopen the tab you closed',
    group: 'Tabs',
    keys: ['Mod+Shift+T'],
  },
  {
    id: 'new-tab',
    label: 'New tab',
    group: 'Tabs',
    keys: ['Mod+T'],
  },
  {
    id: 'close-tab',
    label: 'Close the tab',
    group: 'Tabs',
    keys: ['Mod+W'],
  },
  {
    id: 'space-number',
    label: 'Go to a space (first to ninth)',
    group: 'Spaces',
    keys: ['Mod+Shift+Digit1-9'],
    show: ['Mod+Shift+1 – 9'],
  },
  {
    id: 'last-tab',
    label: 'Go to the last tab',
    group: 'Tabs',
    keys: ['Mod+9'],
  },
  {
    id: 'tab-number',
    label: 'Go to a tab (first to eighth)',
    group: 'Tabs',
    keys: ['Mod+1-8'],
    show: ['Mod+1 – 8'],
  },
  {
    id: 'back',
    label: 'Back',
    group: 'Pages',
    keys: ['Alt+ArrowLeft', 'Mod+['],
    show: ['Alt+ArrowLeft'],
    macShow: ['Mod+['],
  },
  {
    id: 'forward',
    label: 'Forward',
    group: 'Pages',
    keys: ['Alt+ArrowRight', 'Mod+]'],
    show: ['Alt+ArrowRight'],
    macShow: ['Mod+]'],
  },
  {
    id: 'hard-reload',
    label: 'Reload, fetching everything again',
    group: 'Pages',
    keys: ['Shift+F5', 'Mod+Shift+R'],
    show: ['Mod+Shift+R'],
  },
  {
    id: 'reload',
    label: 'Reload',
    group: 'Pages',
    keys: ['F5', 'Mod+R'],
    show: ['Mod+R'],
  },
  {
    id: 'dev-tools',
    label: 'Developer tools',
    group: 'Pages',
    keys: ['F12', 'Mod+Shift+I', 'Meta+Alt+I'],
    show: ['F12'],
    macShow: ['Mod+Alt+I'],
  },
];

// The keys of a shortcut on this kind of computer.
const keysOf = (s: Shortcut, mac: boolean) => (mac && s.mac) || s.keys;

export interface KeyInput {
  key: string;
  code: string;
  control: boolean;
  meta: boolean;
  alt: boolean;
  shift: boolean;
}

// Which shortcut a key press is (and, for a numbered one, its number).
export function matchShortcut(
  input: KeyInput,
  platform: string,
): { id: ShortcutId; number?: number } | null {
  const mac = platform === 'darwin';
  const key = input.key.toLowerCase();
  for (const shortcut of SHORTCUTS)
    for (const keys of keysOf(shortcut, mac)) {
      // ("Mod++": the key is "+" itself.)
      const parts = keys.endsWith('++')
        ? [...keys.slice(0, -2).split('+'), '+']
        : keys.split('+');
      const last = parts.pop()!;
      const held = {
        mod: mac ? input.meta : input.control,
        ctrl: input.control,
        meta: input.meta,
        alt: input.alt,
        shift: input.shift,
      };
      if (
        !parts.every(
          (part) => held[part.toLowerCase() as keyof typeof held] === true,
        )
      )
        continue;
      const range = /^(Digit)?(\d)-(\d)$/.exec(last);
      if (range) {
        const n = range[1]
          ? Number(/^Digit(\d)$/.exec(input.code)?.[1])
          : /^\d$/.test(key)
            ? Number(key)
            : NaN;
        if (n >= Number(range[2]) && n <= Number(range[3]))
          return { id: shortcut.id, number: n };
        continue;
      }
      if (key === last.toLowerCase()) return { id: shortcut.id };
    }
  return null;
}

// What Settings' page lists, by group, for this kind of computer: each
// shortcut's keys as separate key caps ("Ctrl", "Shift", "T").
export function shortcutsToShow(platform: string) {
  const mac = platform === 'darwin';
  const groups: ShortcutGroup[] = ['Tabs', 'Spaces', 'Pages', 'Firn'];
  return groups.map((group) => ({
    group,
    shortcuts: SHORTCUTS.filter((s) => s.group === group && !s.hidden)
      // Go to a tab, then the last one; back before forward; and so on.
      .sort((a, b) => ORDER.indexOf(a.id) - ORDER.indexOf(b.id))
      .map((s) => ({
        id: s.id,
        label: s.label,
        keys: ((mac && s.macShow) || s.show || keysOf(s, mac)).map((keys) =>
          capsOf(keys, mac),
        ),
      })),
  }));
}

// The order on the page (the list above is in matching order).
const ORDER: ShortcutId[] = [
  'new-tab',
  'close-tab',
  'reopen-tab',
  'pin',
  'next-tab',
  'tab-number',
  'last-tab',
  'space-number',
  'address',
  'back',
  'forward',
  'reload',
  'hard-reload',
  'find',
  'find-next',
  'find-previous',
  'zoom-in',
  'zoom-out',
  'zoom-reset',
  'escape',
  'dev-tools',
  'sidebar',
  'history',
  'settings',
];

const NAMES: Record<string, [string, string]> = {
  // [Windows and Linux, Mac]
  mod: ['Ctrl', '⌘'],
  ctrl: ['Ctrl', '⌃'],
  meta: ['Win', '⌘'],
  alt: ['Alt', '⌥'],
  shift: ['Shift', '⇧'],
  arrowleft: ['←', '←'],
  arrowright: ['→', '→'],
  escape: ['Esc', 'Esc'],
  tab: ['Tab', 'Tab'],
};

function capsOf(keys: string, mac: boolean) {
  const parts = keys.endsWith('++')
    ? [...keys.slice(0, -2).split('+'), '+']
    : keys.split('+');
  return parts.map((part) => {
    const name = NAMES[part.toLowerCase()];
    return name ? name[mac ? 1 : 0] : part;
  });
}

// A shortcut's keys as an Electron menu accelerator (its first keys), so
// a menu shows the same keys as everywhere else.
export function menuAccelerator(id: ShortcutId, platform: string) {
  const shortcut = SHORTCUTS.find((s) => s.id === id);
  const keys = shortcut && keysOf(shortcut, platform === 'darwin')[0];
  return keys?.replace(/^Mod\+/, 'CmdOrCtrl+');
}
