import { useEffect, useState } from 'react';
import type { NavState } from '../types';
import { AddressBar } from './AddressBar';
import { CloseIcon, MaximizeIcon, MinimizeIcon, RestoreIcon } from './icons';
import { NavButtons, SidebarToggle } from './Sidebar';

const EMPTY_NAV: NavState = {
  url: '',
  title: '',
  canGoBack: false,
  canGoForward: false,
  isLoading: false,
  zoom: 1,
  sitePermissions: false,
};

// The bar above the page. In the usual look it appears when the mouse
// reaches the top edge, while the page glides down to make room, with the
// window buttons (Windows and Linux; on macOS it's just a strip to grab the
// window by). With the address bar set to sit at the top, it's always
// there, across the whole window: the sidebar's top row moves up into it,
// exactly where it was (the macOS traffic lights, the sidebar button,
// back, forward, and reload), with the same address bar as the sidebar's,
// centered over the page. The sidebar, docked or peeking, sits below it.
// The bar has no background: the frame behind it (frosted glass, where
// available) shows through. When to come and go is decided in src/main.ts.
export function TopBar() {
  const [maximized, setMaximized] = useState(false);
  const [shown, setShown] = useState(false);
  const [nav, setNav] = useState<NavState>(EMPTY_NAV);
  const [addressOnTop, setAddressOnTop] = useState(false);
  const [sidebarWidth, setSidebarWidth] = useState(260);
  const [collapsed, setCollapsed] = useState(false);
  // Where the page starts, to center the address bar over it.
  const [pageLeft, setPageLeft] = useState(260);
  // Where the peeking sidebar reaches into the bar (0 when it isn't out):
  // that part mustn't drag the window, or it would swallow the sidebar's
  // clicks.
  const [peekCover, setPeekCover] = useState(0);

  useEffect(() => {
    const offs = [
      window.firn.onMaximizedChange(setMaximized),
      window.firn.onTopBarState(setShown),
      window.firn.onNavState(setNav),
      window.firn.onSettingsState(({ settings }) =>
        setAddressOnTop(settings.addressBar === 'top'),
      ),
      window.firn.onSidebarState(({ width, peeking, pageLeft, collapsed }) => {
        setSidebarWidth(width);
        setCollapsed(collapsed);
        setPageLeft(pageLeft);
        setPeekCover(peeking ? Math.max(0, width + 32 - pageLeft) : 0);
      }),
    ];
    window.firn.ready();
    return () => offs.forEach((off) => off());
  }, []);

  return (
    <div
      className={`top-bar ${shown ? 'is-shown' : ''}`}
      style={{ '--sidebar-width': `${sidebarWidth}px` } as React.CSSProperties}
    >
      {/* Empty bar space is a real title bar (drag, snap to screen edges,
          double-click to maximize). See the drag rules in styles.css. */}
      {/* (With the address bar at the top, the peeking sidebar slides out
          below the bar, so it never covers it.) */}
      <div
        className="top-bar-drag"
        style={{ left: addressOnTop ? 0 : peekCover }}
      />
      {addressOnTop && (
        <>
          <div className="top-bar-nav">
            <div className="button-row">
              <SidebarToggle collapsed={collapsed} />
            </div>
            <NavButtons nav={nav} />
          </div>
          <div
            className="top-bar-address"
            style={
              {
                // As wide as in the sidebar (its width less the side insets).
                width: sidebarWidth - 16,
                '--address-half': `${(sidebarWidth - 16) / 2}px`,
                '--page-left': `${pageLeft}px`,
              } as React.CSSProperties
            }
          >
            <AddressBar nav={nav} />
          </div>
        </>
      )}
      {window.firn.platform !== 'darwin' && (
        <div className="button-row top-bar-window">
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
  );
}
