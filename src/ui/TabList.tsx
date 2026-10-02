import { useState } from 'react';
import type { TabView } from '../types';
import { GlobeIcon } from './icons';

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
