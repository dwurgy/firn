import { useEffect, useState } from 'react';
import { CloseIcon, MaximizeIcon, MinimizeIcon, RestoreIcon } from './icons';

// The bar that slides down over the top of the page when the mouse reaches
// the top edge, holding minimize / maximize / close (Windows and Linux).
// It only covers the page itself; the frame around it belongs to the
// sidebar's layer, which slides its outline of the page down in step.
// When to slide away is decided in src/main.ts (it watches the cursor).
export function TopBar() {
  const [maximized, setMaximized] = useState(false);
  const [shown, setShown] = useState(false);

  useEffect(() => {
    const offs = [
      window.firn.onMaximizedChange(setMaximized),
      window.firn.onTopBarState(setShown),
    ];
    window.firn.ready();
    return () => offs.forEach((off) => off());
  }, []);

  return (
    <div className={`top-bar ${shown ? 'is-shown' : ''}`}>
      <div className="top-bar-cover">
        <span className="top-bar-corner is-left" />
        <span className="top-bar-corner is-right" />
        <span className="top-bar-edge" />
      </div>
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
    </div>
  );
}
