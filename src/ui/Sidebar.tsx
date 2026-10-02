import { useEffect, useRef, useState } from 'react';
import type { NavState, SidebarState, SpacesState, TabsState } from '../types';
import { AddressBar } from './AddressBar';
import { PinnedGrid } from './PinnedGrid';
import { SpaceHeader, SpaceSwitcher } from './Spaces';
import { TabList } from './TabList';
import {
  BackIcon,
  ForwardIcon,
  PlusIcon,
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
  const [tabs, setTabs] = useState<TabsState>({ tabs: [], activeTabId: null });
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

  return { nav, tabs, sidebar, spaces };
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
    <aside className={`sidebar ${className}`} style={style}>
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

      <div
        key={spaces.activeSpaceId}
        className="space-content"
        style={{ '--space-from': `${direction * 8}px` } as React.CSSProperties}
      >
        <SpaceHeader
          space={space}
          renaming={!!space && renamingId === space.id}
          onRename={() => space && setRenamingId(space.id)}
          onDoneRenaming={() => setRenamingId(null)}
        />

        <PinnedGrid
          tabs={tabs.tabs.filter((t) => t.pinned)}
          activeTabId={tabs.activeTabId}
        />

        <section className="tabs-section">
          <button className="new-tab" onClick={() => window.firn.newTab()}>
            <span className="tab-icon">
              <PlusIcon />
            </span>
            New tab
          </button>
          <TabList
            tabs={tabs.tabs.filter((t) => !t.pinned)}
            activeTabId={tabs.activeTabId}
          />
        </section>
      </div>

      <SpaceSwitcher {...spaces} />
    </aside>
  );
}
