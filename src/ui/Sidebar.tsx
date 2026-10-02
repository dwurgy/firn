import { useEffect, useState } from 'react';
import type { NavState, SidebarState, TabsState } from '../types';
import { AddressBar } from './AddressBar';
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

  useEffect(() => {
    const offs = [
      window.firn.onNavState(setNav),
      window.firn.onTabsState(setTabs),
      window.firn.onSidebarState(setSidebar),
    ];
    window.firn.ready();
    return () => offs.forEach((off) => off());
  }, []);

  return { nav, tabs, sidebar };
}

// The sidebar's contents: buttons, address bar and tabs. Used both in its
// usual place and when it peeks over the page while collapsed.
export function Sidebar({
  nav,
  tabs,
  collapsed,
  className = '',
  style,
}: {
  nav: NavState;
  tabs: TabsState;
  collapsed: boolean;
  className?: string;
  style?: React.CSSProperties;
}) {
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

      <section className="tabs-section">
        <button className="new-tab" onClick={() => window.firn.newTab()}>
          <span className="tab-icon">
            <PlusIcon />
          </span>
          New tab
        </button>
        <TabList tabs={tabs.tabs} activeTabId={tabs.activeTabId} />
      </section>
    </aside>
  );
}
