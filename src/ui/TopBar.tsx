import { useEffect, useRef, useState } from 'react';
import { CloseIcon, MaximizeIcon, MinimizeIcon, RestoreIcon } from './icons';

// The bar that slides down over the top of the page when the mouse reaches
// the top edge, holding minimize / maximize / close (Windows and Linux).
// It only covers the page itself; the frame around it belongs to the
// sidebar's layer, which slides its outline of the page down in step.
// When to slide away is decided in src/main.ts (it watches the cursor).
export function TopBar() {
  const [maximized, setMaximized] = useState(false);
  const [shown, setShown] = useState(false);
  const dragging = useRef(false);
  const endDrag = () => {
    if (!dragging.current) return;
    dragging.current = false;
    window.firn.dragWindow('end');
  };

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
      {/* Empty bar space moves the window. Firn does the moving itself
          rather than using a Windows title-bar area, which misbehaves in
          this layer. */}
      <div
        className="top-bar-drag"
        onPointerDown={(e) => {
          if (e.button !== 0 || e.detail > 1) return;
          e.currentTarget.setPointerCapture(e.pointerId);
          dragging.current = true;
          window.firn.dragWindow('start');
        }}
        onPointerMove={() => {
          if (dragging.current) window.firn.dragWindow('move');
        }}
        onPointerUp={endDrag}
        onPointerCancel={endDrag}
        onLostPointerCapture={endDrag}
        onDoubleClick={() => window.firn.windowCommand('toggle-maximize')}
      />
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
