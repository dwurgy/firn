import { useEffect, useRef, useState } from 'react';
import { CloseIcon, MaximizeIcon, MinimizeIcon, RestoreIcon } from './icons';

// The bar that slides down over the top of the page when the mouse reaches
// the top edge, holding minimize / maximize / close (Windows and Linux).
// It only covers the page itself; the frame around it belongs to the
// sidebar's layer, which slides its outline of the page down in step.
export function TopBar() {
  const [maximized, setMaximized] = useState(false);
  const [shown, setShown] = useState(false);
  const hideTimer = useRef<ReturnType<typeof setTimeout>>(undefined);

  const hideSoon = (delay: number) => {
    clearTimeout(hideTimer.current);
    hideTimer.current = setTimeout(
      () => window.firn.revealTopBar(false),
      delay,
    );
  };

  useEffect(() => {
    const offs = [
      window.firn.onMaximizedChange(setMaximized),
      window.firn.onTopBarState((isShown) => {
        setShown(isShown);
        // If the mouse just brushed the edge and moved on, slide away.
        if (isShown) hideSoon(1200);
      }),
    ];
    window.firn.ready();
    return () => offs.forEach((off) => off());
  }, []);

  return (
    <div
      className={`top-bar ${shown ? 'is-shown' : ''}`}
      onMouseEnter={() => clearTimeout(hideTimer.current)}
      // A short pause, so brushing past the edge doesn't make it flicker.
      onMouseLeave={() => hideSoon(250)}
    >
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
