import { useEffect, useState } from 'react';
import { CloseIcon, MaximizeIcon, MinimizeIcon, RestoreIcon } from './icons';

// The window buttons (minimize / maximize / close, Windows and Linux) that
// appear above the page when the mouse reaches the top edge, while the page
// glides down to make room. The bar has no background: the frame behind it
// (frosted glass, where available) shows through. When to go away is
// decided in src/main.ts (it watches the cursor).
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
      {/* Empty bar space is a real title bar (drag, snap to screen edges,
          double-click to maximize). See the drag rules in styles.css. */}
      <div className="top-bar-drag" />
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
