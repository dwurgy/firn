import { useState } from 'react';
import type { TabView } from '../types';
import { CloseIcon, GlobeIcon } from './icons';

export function TabIcon({ tab }: { tab: TabView }) {
  const [broken, setBroken] = useState<string | null>(null);
  if (tab.isLoading) return <span className="tab-spinner" />;
  if (!tab.favicon || broken === tab.favicon) return <GlobeIcon />;
  return (
    <img
      className="tab-favicon"
      src={tab.favicon}
      alt=""
      draggable={false}
      onError={() => setBroken(tab.favicon)}
    />
  );
}

export function tabTitle(tab: TabView) {
  if (tab.title) return tab.title;
  if (!tab.url) return 'New tab';
  return tab.url.replace(/^https?:\/\/(www\.)?/i, '');
}

export function TabList({
  tabs,
  activeTabId,
}: {
  tabs: TabView[];
  activeTabId: string | null;
}) {
  return (
    <ul className="tab-list">
      {tabs.map((tab) => (
        <li
          key={tab.id}
          className={`tab ${tab.id === activeTabId ? 'is-active' : ''}`}
          title={tabTitle(tab)}
          onMouseDown={(e) => {
            if (e.button === 0) window.firn.activateTab(tab.id);
          }}
          // Middle-click closes, like other browsers.
          onAuxClick={(e) => {
            if (e.button === 1) window.firn.closeTab(tab.id);
          }}
        >
          <span className="tab-icon">
            <TabIcon tab={tab} />
          </span>
          <span className="tab-title">{tabTitle(tab)}</span>
          <button
            className="tab-close"
            title="Close tab"
            onMouseDown={(e) => e.stopPropagation()}
            onClick={() => window.firn.closeTab(tab.id)}
          >
            <CloseIcon />
          </button>
        </li>
      ))}
    </ul>
  );
}
