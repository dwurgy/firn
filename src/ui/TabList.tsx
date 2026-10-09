import { useState } from 'react';
import type { TabView } from '../types';
import { GlobeIcon, MutedIcon, SoundIcon } from './icons';

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

// The speaker on a tab playing sound (or muted): click to mute it, or to
// turn it back on. Shown only while there's something to hear or undo.
// `badge`: the small one in a Basecamp tile's corner (the tile is itself a
// button, so this one can't be).
export function TabSound({ tab, badge }: { tab: TabView; badge?: boolean }) {
  if (!tab.audible && !tab.muted) return null;
  const Tag = badge ? 'span' : 'button';
  const label = tab.muted ? 'Unmute tab' : 'Mute tab';
  return (
    <Tag
      className={`tab-sound ${badge ? 'is-badge' : ''} ${tab.muted ? 'is-muted' : ''}`}
      role={badge ? 'button' : undefined}
      title={label}
      // Its own name for screen readers, kept in step as it changes.
      aria-label={label}
      onPointerDown={(e) => e.stopPropagation()}
      onClick={(e) => {
        e.stopPropagation();
        window.firn.toggleMute(tab.id);
      }}
    >
      {tab.muted ? <MutedIcon /> : <SoundIcon />}
    </Tag>
  );
}
