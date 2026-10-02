import type { CSSProperties } from 'react';
import type { TabView } from '../types';
import { useIconColor } from './iconColor';
import { TabIcon, tabTitle } from './TabList';

// Basecamp: a grid of favorite sites at the top of the sidebar, the same in
// every space (at most 12). Closing one (middle-click) unloads it rather
// than removing it; right-click for "Go back to home" and "Remove from
// Basecamp".
//
// The tiles share each row evenly: one pin fills the row, two split it, and
// so on, until the tiles would get too narrow and a new row starts (so a
// wider sidebar fits more per row).
export function Basecamp({
  tabs,
  activeTabId,
}: {
  tabs: TabView[];
  activeTabId: string | null;
}) {
  if (!tabs.length) return null;
  return (
    <div className="basecamp">
      <div className="basecamp-grid">
        {tabs.map((tab) => (
          <BasecampTile
            key={tab.id}
            tab={tab}
            active={tab.id === activeTabId}
          />
        ))}
      </div>
    </div>
  );
}

function BasecampTile({ tab, active }: { tab: TabView; active: boolean }) {
  // The active tile is tinted with its icon's own color.
  const color = useIconColor(tab.favicon);
  return (
    <button
      className={[
        'basecamp-tile',
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
      <span className="basecamp-icon">
        <TabIcon tab={tab} />
      </span>
    </button>
  );
}
