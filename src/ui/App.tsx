import { useEffect, useState } from 'react';
import type { NavState, TabsState } from '../types';
import { AddressBar } from './AddressBar';
import { TabList } from './TabList';
import {
  BackIcon,
  CloseIcon,
  ForwardIcon,
  MaximizeIcon,
  MinimizeIcon,
  PlusIcon,
  ReloadIcon,
  RestoreIcon,
  StopIcon,
} from './icons';

// macOS draws its own traffic lights; elsewhere Firn draws the window buttons.
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
  const [maximized, setMaximized] = useState(false);

  useEffect(() => {
    const offs = [
      window.firn.onNavState(setNav),
      window.firn.onTabsState(setTabs),
      window.firn.onMaximizedChange(setMaximized),
    ];
    window.firn.ready();
    return () => offs.forEach((off) => off());
  }, []);

  const activeTab = tabs.tabs.find((t) => t.id === tabs.activeTabId);
  const showEmptyPage = Boolean(activeTab && !activeTab.url);

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

          {OWN_WINDOW_BUTTONS && (
            <div className="button-row">
              <button
                className="icon-button"
                title="Minimize"
                onClick={() => window.firn.windowCommand('minimize')}
              >
                <MinimizeIcon />
              </button>
              <button
                className="icon-button"
                title={maximized ? 'Restore' : 'Maximize'}
                onClick={() => window.firn.windowCommand('toggle-maximize')}
              >
                {maximized ? <RestoreIcon /> : <MaximizeIcon />}
              </button>
              <button
                className="icon-button close-button"
                title="Close"
                onClick={() => window.firn.windowCommand('close')}
              >
                <CloseIcon />
              </button>
            </div>
          )}
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
          frame. A fresh new tab has no page yet, so this shows instead. */}
      <main className={`page-area ${showEmptyPage ? 'is-empty' : ''}`}>
        {showEmptyPage && (
          <div className="empty-page">
            <p className="empty-title">A fresh page</p>
            <p className="empty-hint">
              Type an address or a search in the sidebar.
            </p>
          </div>
        )}
      </main>
    </div>
  );
}
