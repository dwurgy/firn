import { useEffect, useRef, useState } from 'react';
import type { NavState, SidebarState, SpacesState, TabsState } from '../types';
import { AddressBar } from './AddressBar';
import { Basecamp } from './Basecamp';
import { SpaceHeader, SpaceSwitcher } from './Spaces';
import { SpaceTabs } from './SpaceTabs';
import {
  BackIcon,
  ForwardIcon,
  ReloadIcon,
  SidebarIcon,
  StopIcon,
} from './icons';

const EMPTY_NAV: NavState = {
  url: '',
  title: '',
  canGoBack: false,
  canGoForward: false,
  isLoading: false,
  zoom: 1,
};

export const DEFAULT_SIDEBAR: SidebarState = {
  width: 260,
  collapsed: false,
  pageLeft: 260,
  peeking: false,
};

// The live state every sidebar needs, kept in step with the main process.
export function useSidebarData() {
  const [nav, setNav] = useState<NavState>(EMPTY_NAV);
  const [tabs, setTabs] = useState<TabsState>({
    tabs: [],
    activeTabId: null,
    splits: [],
  });
  const [sidebar, setSidebar] = useState<SidebarState>(DEFAULT_SIDEBAR);
  const [spaces, setSpaces] = useState<SpacesState>({
    spaces: [],
    activeSpaceId: '',
  });

  useEffect(() => {
    const offs = [
      window.firn.onNavState(setNav),
      window.firn.onTabsState(setTabs),
      window.firn.onSidebarState(setSidebar),
      window.firn.onSpacesState(setSpaces),
    ];
    window.firn.ready();
    return () => offs.forEach((off) => off());
  }, []);

  // The active space's color tints the frame (see "Space tint" in
  // styles.css); changing it cross-fades.
  const color = spaces.spaces.find((s) => s.id === spaces.activeSpaceId)?.color;
  useEffect(() => {
    const root = document.documentElement;
    const rgb = color && hexToRgb(color);
    if (rgb) {
      root.style.setProperty('--space-rgb', rgb);
      root.dataset.tinted = '';
    } else {
      delete root.dataset.tinted;
    }
  }, [color]);

  return { nav, tabs, sidebar, spaces };
}

// "#c9a27e" -> "201 162 126", for use in rgb().
function hexToRgb(hex: string) {
  const match = /^#([0-9a-f]{6})$/i.exec(hex);
  if (!match) return null;
  return [0, 2, 4].map((i) => parseInt(match[1].slice(i, i + 2), 16)).join(' ');
}

// The sidebar's contents: buttons, address bar and tabs. Used both in its
// usual place and when it peeks over the page while collapsed.
export function Sidebar({
  nav,
  tabs,
  spaces,
  collapsed,
  className = '',
  style,
}: {
  nav: NavState;
  tabs: TabsState;
  spaces: SpacesState;
  collapsed: boolean;
  className?: string;
  style?: React.CSSProperties;
}) {
  const space = spaces.spaces.find((s) => s.id === spaces.activeSpaceId);
  // Which space's name is being edited (only shown while it's the active
  // space).
  const [renamingId, setRenamingId] = useState<string | null>(null);
  useEffect(() => window.firn.onRenameSpace(setRenamingId), []);

  // Switching spaces slides the new space's tabs in from the side it's on.
  const index = spaces.spaces.findIndex((s) => s.id === spaces.activeSpaceId);
  const lastIndex = useRef(index);
  const direction = index < lastIndex.current ? -1 : 1;
  useEffect(() => {
    lastIndex.current = index;
  }, [index]);

  return (
    <aside
      className={`sidebar ${className}`}
      style={style}
      // Right-click on empty space: the space's menu (Change color...).
      // Tabs, tiles and the space's name have their own menus, and text
      // fields keep the usual one.
      onContextMenu={(e) => {
        if (e.defaultPrevented) return;
        if ((e.target as HTMLElement).closest('input, textarea')) return;
        e.preventDefault();
        window.firn.showSidebarMenu();
      }}
    >
      <div className="sidebar-top">
        <div className="button-row">
          <button
            className="icon-button"
            title={
              collapsed ? 'Keep sidebar open (Ctrl+S)' : 'Hide sidebar (Ctrl+S)'
            }
            onClick={() => window.firn.toggleSidebar()}
          >
            <SidebarIcon />
          </button>
        </div>
        <nav className="button-row">
          <button
            className="icon-button"
            title="Back"
            disabled={!nav.canGoBack}
            onClick={() => window.firn.command('back')}
          >
            <BackIcon />
          </button>
          <button
            className="icon-button"
            title="Forward"
            disabled={!nav.canGoForward}
            onClick={() => window.firn.command('forward')}
          >
            <ForwardIcon />
          </button>
          <button
            className="icon-button"
            title={nav.isLoading ? 'Stop' : 'Reload'}
            disabled={!nav.url}
            onClick={() =>
              window.firn.command(nav.isLoading ? 'stop' : 'reload')
            }
          >
            {nav.isLoading ? <StopIcon /> : <ReloadIcon />}
          </button>
        </nav>
      </div>

      <AddressBar nav={nav} />

      <Basecamp
        tabs={tabs.tabs.filter((t) => t.basecamp)}
        activeTabId={tabs.activeTabId}
      />

      <div
        key={spaces.activeSpaceId}
        className="space-content"
        style={{ '--space-from': `${direction * 8}px` } as React.CSSProperties}
      >
        <SpaceHeader
          space={space}
          renaming={!!space && renamingId === space.id}
          onDoneRenaming={() => setRenamingId(null)}
        />

        <SpaceTabs
          tabs={tabs.tabs.filter((t) => !t.basecamp)}
          activeTabId={tabs.activeTabId}
          folded={!!space?.pinsFolded}
        />
      </div>

      <SpaceSwitcher {...spaces} />
    </aside>
  );
}
