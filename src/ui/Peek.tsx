import { Sidebar, useSidebarData } from './Sidebar';

// The sidebar sliding in over the page while it's collapsed. It lives in its
// own layer above the page; src/main.ts decides when to show and hide it.
export function Peek() {
  const { nav, tabs, sidebar, spaces } = useSidebarData();
  return (
    <div
      className={`peek ${sidebar.peeking ? 'is-shown' : ''}`}
      style={{ '--sidebar-width': `${sidebar.width}px` } as React.CSSProperties}
    >
      <Sidebar
        nav={nav}
        tabs={tabs}
        spaces={spaces}
        collapsed={sidebar.collapsed}
      />
    </div>
  );
}
