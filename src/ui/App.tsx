import { useEffect, useRef, useState } from 'react';
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

// macOS draws its own traffic lights; elsewhere Firn's window buttons wait
// above the page, which slides down to reveal them when the mouse reaches
// the top edge.
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
  const [topRevealed, setTopRevealed] = useState(false);
  const hideTimer = useRef<ReturnType<typeof setTimeout>>(undefined);

  const revealTop = (reveal: boolean) => {
    clearTimeout(hideTimer.current);
    if (reveal) {
      setTopRevealed(true);
      window.firn.revealTopBar(true);
    } else {
      // A short pause, so brushing past the edge doesn't make it flicker.
      hideTimer.current = setTimeout(() => {
        setTopRevealed(false);
        window.firn.revealTopBar(false);
      }, 250);
    }
  };

  useEffect(() => {
    const offs = [
      window.firn.onNavState(setNav),
      window.firn.onTabsState(setTabs),
      window.firn.onMaximizedChange(setMaximized),
    ];
    window.firn.ready();
    return () => offs.forEach((off) => off());
  }, []);

  const noTabs = tabs.tabs.length === 0;

  return (
    <div className={`app ${topRevealed ? 'top-revealed' : ''}`}>
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

      {/* The strip of frame above the page. Reaching it slides the page
          down to reveal the window buttons. */}
      {OWN_WINDOW_BUTTONS && (
        <div
          className="top-strip"
          onMouseEnter={() => revealTop(true)}
          onMouseLeave={() => revealTop(false)}
        >
          <div className="button-row window-buttons">
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
        </div>
      )}
    </div>
  );
}
