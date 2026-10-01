import { useEffect, useRef, useState } from 'react';
import { CloseIcon, MaximizeIcon, MinimizeIcon, RestoreIcon } from './icons';

// The bar that slides down over the top of the page when the mouse reaches
// the top edge, holding minimize / maximize / close (Windows and Linux).
export function TopBar() {
  const [maximized, setMaximized] = useState(false);
  const [shown, setShown] = useState(false);
  const hideTimer = useRef<ReturnType<typeof setTimeout>>(undefined);

  const hideSoon = (delay: number) => {
    clearTimeout(hideTimer.current);
    hideTimer.current = setTimeout(() => {
      setShown(false);
      // Let the slide finish before the layer goes away.
      setTimeout(() => window.firn.revealTopBar(false), 200);
    }, delay);
  };

  useEffect(() => {
    const offs = [
      window.firn.onMaximizedChange(setMaximized),
      window.firn.onTopBarShown(() => {
        setShown(true);
        // If the mouse just brushed the edge and moved on, slide away.
        hideSoon(1200);
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
