import { useEffect } from 'react';
import { Sidebar, useSidebarData } from './Sidebar';

// The sidebar sliding in over the page while it's collapsed. It lives in its
// own layer above the page; src/main.ts decides when to show and hide it.
export function Peek() {
  const { nav, tabs, sidebar, spaces, downloads, barOnTop } = useSidebarData();
  // Holding the mouse button down in it (a tab being dragged, maybe out
  // onto the page) keeps it open until it's let go, wherever that is.
  useEffect(() => {
    const letGo = () => window.firn.setPeekHolding(false);
    window.addEventListener('pointerup', letGo);
    window.addEventListener('pointercancel', letGo);
    window.addEventListener('blur', letGo);
    return () => {
      window.removeEventListener('pointerup', letGo);
      window.removeEventListener('pointercancel', letGo);
      window.removeEventListener('blur', letGo);
    };
  }, []);
  // (Over the page with a dragged tab, it steps aside: see `aside`.)
  const shown = sidebar.peeking && !sidebar.aside;
  return (
    <div
      className={`peek ${shown ? 'is-shown' : ''} ${sidebar.docking ? 'is-docking' : ''}`}
      onPointerDown={(e) => {
        if (e.button === 0) window.firn.setPeekHolding(true);
      }}
      // Typing (address bar, a space's name) keeps it open; a click on a
      // button doesn't.
      onFocus={(e) => {
        if ((e.target as HTMLElement).matches('input, textarea'))
          window.firn.setPeekTyping(true);
      }}
      onBlur={(e) => {
        if ((e.target as HTMLElement).matches('input, textarea'))
          window.firn.setPeekTyping(false);
      }}
      style={{ '--sidebar-width': `${sidebar.width}px` } as React.CSSProperties}
    >
      <Sidebar
        nav={nav}
        tabs={tabs}
        spaces={spaces}
        downloads={downloads}
        collapsed={sidebar.collapsed}
        barOnTop={barOnTop}
      />
    </div>
  );
}
