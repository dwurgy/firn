import { useEffect, useRef, useState } from 'react';
import { CloseIcon, MaximizeIcon, MinimizeIcon, RestoreIcon } from './icons';

// Minimize / maximize / close, tucked into the top-right corner. They slide
// in when the mouse reaches the corner and tuck away again when it leaves.
export function WindowControls() {
  const [maximized, setMaximized] = useState(false);
  const [shown, setShown] = useState(false);
  const hideTimer = useRef<ReturnType<typeof setTimeout>>(undefined);

  const hideSoon = (delay: number) => {
    clearTimeout(hideTimer.current);
    hideTimer.current = setTimeout(() => {
      setShown(false);
      // Let the fade finish before the layer goes away.
      setTimeout(() => window.firn.hideWindowControls(), 200);
    }, delay);
  };

  useEffect(() => {
    const offs = [
      window.firn.onMaximizedChange(setMaximized),
      window.firn.onWindowControlsShown(() => {
        setShown(true);
        // If the mouse just brushed the corner and moved on, tuck away.
        hideSoon(1200);
      }),
    ];
    window.firn.ready();
    return () => offs.forEach((off) => off());
  }, []);

  return (
    <div
      className={`window-controls ${shown ? 'is-shown' : ''}`}
      onMouseEnter={() => clearTimeout(hideTimer.current)}
      onMouseLeave={() => hideSoon(300)}
    >
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
  );
}
