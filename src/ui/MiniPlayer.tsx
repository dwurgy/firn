import { useEffect, useState } from 'react';
import type { PlayerState, TabView } from '../types';
import { PauseIcon, PlayIcon } from './icons';
import { TabIcon, tabTitle } from './TabList';

// How long the player takes to fade away (matches .mini-player.is-leaving).
const LEAVE_MS = 200;

// The mini player at the bottom of the sidebar, above the Firn button:
// shown while a tab that isn't on screen (in any space) is playing sound.
// Click it to go to that tab; the button pauses it, or plays it again.
export function MiniPlayer({ player }: { player: PlayerState | null }) {
  // The last player stays on screen while it fades away.
  const [shown, setShown] = useState(player);
  const [leaving, setLeaving] = useState(false);
  useEffect(() => {
    if (player) {
      setShown(player);
      setLeaving(false);
      return;
    }
    setLeaving(true);
    const timer = setTimeout(() => setShown(null), LEAVE_MS);
    return () => clearTimeout(timer);
  }, [player]);
  if (!shown) return null;

  // Enough of a tab for its icon and name.
  const tab = {
    url: shown.url,
    title: shown.title,
    favicon: shown.favicon,
    isLoading: false,
  } as TabView;
  return (
    <section
      className={`mini-player ${leaving ? 'is-leaving' : ''}`}
      aria-label="Playing in another tab"
    >
      <button
        className="mini-player-tab"
        title="Go to this tab"
        onClick={() => window.firn.activateTab(shown.tabId)}
      >
        <span className="tab-icon">
          <TabIcon tab={tab} />
        </span>
        <span className="mini-player-text">
          <span className="mini-player-title">{tabTitle(tab)}</span>
          <span className="mini-player-site">{siteOf(shown.url)}</span>
        </span>
      </button>
      <button
        className="icon-button mini-player-toggle"
        title={shown.playing ? 'Pause' : 'Play'}
        aria-label={shown.playing ? 'Pause' : 'Play'}
        onClick={() => window.firn.togglePlaying(shown.tabId)}
      >
        {shown.playing ? <PauseIcon /> : <PlayIcon />}
      </button>
    </section>
  );
}

function siteOf(url: string) {
  try {
    return new URL(url).hostname.replace(/^www\./, '');
  } catch {
    return '';
  }
}
