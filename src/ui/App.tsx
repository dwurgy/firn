import { useEffect, useState } from 'react';
import type { NavState, TabsState } from '../types';
import { AddressBar } from './AddressBar';
import { TabList } from './TabList';
import { BackIcon, ForwardIcon, PlusIcon, ReloadIcon, StopIcon } from './icons';

// macOS draws its own traffic lights; elsewhere Firn's window buttons are on
// a bar that slides down over the page when the mouse reaches the top edge.
const OWN_WINDOW_BUTTONS = window.firn.platform !== 'darwin';

const EMPTY_NAV: NavState = {
  url: '',
  title: '',
  canGoBack: false,
  canGoForward: false,
  isLoading: false,
};

export function App() {
  const [nav, setNav] = useState<NavState>(EMPTY_NAV);
  const [tabs, setTabs] = useState<TabsState>({ tabs: [], activeTabId: null });

  useEffect(() => {
    const offs = [
      window.firn.onNavState(setNav),
      window.firn.onTabsState(setTabs),
    ];
    window.firn.ready();
    return () => offs.forEach((off) => off());
  }, []);

  const noTabs = tabs.tabs.length === 0;

  return (
    <div className="app">
      <aside className="sidebar">
        <div className="sidebar-top">
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

      {/* Sits right behind the web page so the page looks lifted off the
          frame. With no tabs open, this calm page shows instead. */}
      <main className={`page-area ${noTabs ? 'is-empty' : ''}`}>
        {noTabs && (
          <div className="empty-page">
            <p className="empty-title">No open tabs</p>
            <p className="empty-hint">Press Ctrl+T to open one.</p>
          </div>
        )}
      </main>

      {/* The strip of frame above the page. Reaching it brings down the bar
          with the window buttons (see TopBar.tsx). */}
      {OWN_WINDOW_BUTTONS && (
        <div
          className="top-strip"
          onMouseEnter={() => window.firn.revealTopBar(true)}
        />
      )}
    </div>
  );
}
