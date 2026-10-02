import type { CSSProperties } from 'react';
import type { TabView } from '../types';
import { useIconColor } from './iconColor';
import { TabIcon, tabTitle } from './TabList';

// Pinned tabs: a grid of favicon tiles at the top of the sidebar. Closing a
// pin (middle-click) unloads it rather than removing it; right-click for
// "Go back to home" and "Unpin".
//
// The tiles share each row evenly: one pin fills the row, two split it, and
// so on, until the tiles would get too narrow and a new row starts (so a
// wider sidebar fits more per row).
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
          <PinnedTile key={tab.id} tab={tab} active={tab.id === activeTabId} />
        ))}
      </div>
      <div className="pinned-divider" />
    </div>
  );
}

function PinnedTile({ tab, active }: { tab: TabView; active: boolean }) {
  // The active pin is tinted with its icon's own color.
  const color = useIconColor(tab.favicon);
  return (
    <button
      className={[
        'pinned-tile',
        active && 'is-active',
        color && 'is-tinted',
        !tab.loaded && 'is-unloaded',
      ]
        .filter(Boolean)
        .join(' ')}
      style={color ? ({ '--pin-rgb': color } as CSSProperties) : undefined}
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
  );
}
