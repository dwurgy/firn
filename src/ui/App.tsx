import { useEffect, useRef, useState } from 'react';
import { Sidebar, useSidebarData } from './Sidebar';

const PAGE_INSET = 8; // matches --page-inset in styles.css
const DEFAULT_WIDTH = 260;

export function App() {
  const { nav, tabs, sidebar, spaces } = useSidebarData();
  // The top bar is down: the outline of the page slides down with it.
  const [topBarShown, setTopBarShown] = useState(false);
  const [resizing, setResizing] = useState(false);
  const resize = useRef<{ startX: number; startWidth: number } | null>(null);

  useEffect(() => window.firn.onTopBarState(setTopBarShown), []);

  // How far the sidebar has tucked away (0 = fully out, 1 = fully away),
  // following the page's left edge as it glides.
  const away = Math.min(
    1,
    Math.max(
      0,
      (sidebar.width - sidebar.pageLeft) / (sidebar.width - PAGE_INSET),
    ),
  );
  // Nothing on screen (e.g. a new, empty space).
  const noTabs = !tabs.activeTabId;

  return (
    <div
      className={[
        'app',
        topBarShown && 'top-bar-shown',
        resizing && 'is-resizing',
      ]
        .filter(Boolean)
        .join(' ')}
      style={
        {
          '--sidebar-width': `${sidebar.width}px`,
          '--page-left': `${sidebar.pageLeft}px`,
        } as React.CSSProperties
      }
    >
      <Sidebar
        nav={nav}
        tabs={tabs}
        spaces={spaces}
        collapsed={sidebar.collapsed}
        className={away > 0 ? 'is-tucking' : ''}
        style={
          away > 0
            ? {
                transform: `translateX(${-away * sidebar.width}px)`,
                opacity: 1 - away,
              }
            : undefined
        }
      />

      {/* The gap between sidebar and page: drag it to resize the sidebar,
          double-click to reset. */}
      {!sidebar.collapsed && (
        <div
          className="sidebar-resizer"
          title="Drag to resize · Double-click to reset"
          onPointerDown={(e) => {
            if (e.button !== 0) return;
            e.currentTarget.setPointerCapture(e.pointerId);
            resize.current = { startX: e.clientX, startWidth: sidebar.width };
            setResizing(true);
          }}
          onPointerMove={(e) => {
            const r = resize.current;
            if (r)
              window.firn.setSidebarWidth(r.startWidth + e.clientX - r.startX);
          }}
          onPointerUp={() => {
            resize.current = null;
            setResizing(false);
          }}
          onDoubleClick={() => window.firn.setSidebarWidth(DEFAULT_WIDTH)}
        />
      )}

      {/* Sits right behind the web page so the page looks lifted off the
          frame. With no tabs open, this calm page shows instead. */}
      <main className={`page-area ${noTabs ? 'is-empty' : ''}`}>
        {noTabs && (
          <div className="empty-page">
            <p className="empty-title">No open tabs</p>
            <p className="empty-hint">Press Ctrl+T to open one.</p>
          </div>
        )}
      </main>
    </div>
  );
}
