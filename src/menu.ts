// The Mac menu bar: Firn, File, Edit, View, Window and Help, each short and
// in plain words. (Windows and Linux have no menu bar: everything here is
// also in the sidebar, the Firn menu and right-click menus.)
//
// The shortcuts shown here are the same ones Firn already handles itself
// (see handleShortcut in main.ts); when a page or panel has focus, Firn's
// own handling runs and the menu's copy stays quiet, so nothing happens
// twice. The Edit menu is also what makes Cmd+C, Cmd+V and friends work in
// text fields on a Mac.

import type { MenuItemConstructorOptions } from 'electron';

export interface MenuActions {
  settings: () => void;
  hide: () => void;
  newTab: () => void;
  reopenClosedTab: () => void;
  closeTab: () => void;
  find: () => void;
  toggleSidebar: () => void;
  back: () => void;
  forward: () => void;
  reload: () => void;
  history: () => void;
  zoom: (direction: 1 | -1 | 0) => void;
  devTools: () => void;
  website: () => void;
}

export const macMenuTemplate = (
  a: MenuActions,
): MenuItemConstructorOptions[] => [
  {
    label: 'Firn',
    submenu: [
      { role: 'about', label: 'About Firn' },
      { type: 'separator' },
      { label: 'Settings…', accelerator: 'Cmd+,', click: a.settings },
      { type: 'separator' },
      // Cmd+H opens History in Firn, so hiding has no shortcut here.
      { label: 'Hide Firn', click: a.hide },
      { role: 'hideOthers', label: 'Hide Others' },
      { role: 'unhide', label: 'Show All' },
      { type: 'separator' },
      { role: 'quit', label: 'Quit Firn' },
    ],
  },
  {
    label: 'File',
    submenu: [
      { label: 'New Tab', accelerator: 'Cmd+T', click: a.newTab },
      {
        label: 'Reopen Closed Tab',
        accelerator: 'Cmd+Shift+T',
        click: a.reopenClosedTab,
      },
      { type: 'separator' },
      { label: 'Close Tab', accelerator: 'Cmd+W', click: a.closeTab },
    ],
  },
  {
    label: 'Edit',
    submenu: [
      { role: 'undo' },
      { role: 'redo' },
      { type: 'separator' },
      { role: 'cut' },
      { role: 'copy' },
      { role: 'paste' },
      { role: 'selectAll' },
      { type: 'separator' },
      { label: 'Find…', accelerator: 'Cmd+F', click: a.find },
    ],
  },
  {
    label: 'View',
    submenu: [
      {
        label: 'Show or Hide Sidebar',
        accelerator: 'Cmd+S',
        click: a.toggleSidebar,
      },
      { type: 'separator' },
      { label: 'Back', accelerator: 'Cmd+[', click: a.back },
      { label: 'Forward', accelerator: 'Cmd+]', click: a.forward },
      { label: 'Reload', accelerator: 'Cmd+R', click: a.reload },
      { label: 'History', accelerator: 'Cmd+H', click: a.history },
      { type: 'separator' },
      { label: 'Actual Size', accelerator: 'Cmd+0', click: () => a.zoom(0) },
      { label: 'Zoom In', accelerator: 'Cmd+=', click: () => a.zoom(1) },
      { label: 'Zoom Out', accelerator: 'Cmd+-', click: () => a.zoom(-1) },
      { type: 'separator' },
      { role: 'togglefullscreen', label: 'Full Screen' },
      { label: 'Developer Tools', accelerator: 'Alt+Cmd+I', click: a.devTools },
    ],
  },
  { role: 'windowMenu', label: 'Window' },
  {
    role: 'help',
    label: 'Help',
    submenu: [{ label: 'Firn Website', click: a.website }],
  },
];
