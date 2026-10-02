import type { TabView } from '../types';
import { TabIcon, tabTitle } from './TabList';

// Pinned tabs: a grid of favicon tiles at the top of the sidebar. Closing a
// pin (middle-click) unloads it rather than removing it; right-click for
// "Go back to home" and "Unpin".
export function PinnedGrid({
  tabs,
  activeTabId,
}: {
  tabs: TabView[];
  activeTabId: string | null;
}) {
  if (!tabs.length) return null;
  return (
    <div className="pinned">
      <div className="pinned-grid">
        {tabs.map((tab) => (
          <button
            key={tab.id}
            className={[
              'pinned-tile',
              tab.id === activeTabId && 'is-active',
              !tab.loaded && 'is-unloaded',
            ]
              .filter(Boolean)
              .join(' ')}
            title={tabTitle(tab)}
            onPointerDown={(e) => {
              if (e.button === 0) window.firn.activateTab(tab.id);
            }}
            onAuxClick={(e) => {
              if (e.button === 1) window.firn.closeTab(tab.id);
            }}
            onContextMenu={(e) => {
              e.preventDefault();
              window.firn.showTabMenu(tab.id);
            }}
          >
            <span className="pinned-icon">
              <TabIcon tab={tab} />
            </span>
          </button>
        ))}
      </div>
      <div className="pinned-divider" />
    </div>
  );
}
