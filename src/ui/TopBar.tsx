import { useEffect, useState } from 'react';
import type { NavState } from '../types';
import { AddressBar } from './AddressBar';
import { CloseIcon, MaximizeIcon, MinimizeIcon, RestoreIcon } from './icons';

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
// there, with the same address bar as the sidebar's, centered over the page.
// The bar has no background: the frame behind it (frosted glass, where
// available) shows through. When to come and go is decided in src/main.ts.
export function TopBar() {
  const [maximized, setMaximized] = useState(false);
  const [shown, setShown] = useState(false);
  const [nav, setNav] = useState<NavState>(EMPTY_NAV);
  const [addressOnTop, setAddressOnTop] = useState(false);
  const [sidebarWidth, setSidebarWidth] = useState(260);

  useEffect(() => {
    const offs = [
      window.firn.onMaximizedChange(setMaximized),
      window.firn.onTopBarState(setShown),
      window.firn.onNavState(setNav),
      window.firn.onSettingsState(({ settings }) =>
        setAddressOnTop(settings.addressBar === 'top'),
      ),
      window.firn.onSidebarState(({ width }) => setSidebarWidth(width)),
    ];
    window.firn.ready();
    return () => offs.forEach((off) => off());
  }, []);

  return (
    <div className={`top-bar ${shown ? 'is-shown' : ''}`}>
      {/* Empty bar space is a real title bar (drag, snap to screen edges,
          double-click to maximize). See the drag rules in styles.css. */}
      <div className="top-bar-drag" />
      {addressOnTop && (
        <div
          className="top-bar-address"
          // As wide as in the sidebar (its width less the side insets).
          style={{ width: sidebarWidth - 16 }}
        >
          <AddressBar nav={nav} />
        </div>
      )}
      {window.firn.platform !== 'darwin' && (
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
  );
}
