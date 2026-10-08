import { Sidebar, useSidebarData } from './Sidebar';

// The sidebar sliding in over the page while it's collapsed. It lives in its
// own layer above the page; src/main.ts decides when to show and hide it.
export function Peek() {
  const { nav, tabs, sidebar, spaces, downloads, barOnTop } = useSidebarData();
  return (
    <div
      className={`peek ${sidebar.peeking ? 'is-shown' : ''} ${sidebar.docking ? 'is-docking' : ''}`}
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
