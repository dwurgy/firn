import { useEffect, useMemo, useRef, useState } from 'react';
import { isSearch, toNavigableUrl } from '../url';
import type { OverlayState, Rect, TabView } from '../types';
import { TabIcon, tabTitle } from './TabList';
import {
  ArrowIcon,
  CloseIcon,
  ExpandIcon,
  GlobeIcon,
  SearchIcon,
} from './icons';

// The layer that floats above the web page: the command bar (new tab), the
// Ctrl+Tab switcher and Lookout's backdrop and buttons. It's transparent
// unless one of them is open.
export function Floating() {
  const [overlay, setOverlay] = useState<OverlayState>({ mode: 'hidden' });
  const [tabs, setTabs] = useState<TabView[]>([]);

  useEffect(() => {
    const offs = [
      window.firn.onOverlayState(setOverlay),
      window.firn.onTabsState((state) => setTabs(state.tabs)),
    ];
    window.firn.ready();
    return () => offs.forEach((off) => off());
  }, []);

  if (overlay.mode === 'lookout') {
    return <Lookout key={overlay.openId} {...overlay} />;
  }
  if (overlay.mode === 'command') {
    return (
      <CommandBar key={overlay.openId} tabs={tabs} beside={overlay.beside} />
    );
  }
  if (overlay.mode === 'switcher' && overlay.revealed) {
    return (
      <Switcher tabIds={overlay.tabIds} index={overlay.index} tabs={tabs} />
    );
  }
  return null;
}

const byRecent = (a: TabView, b: TabView) => b.lastActiveAt - a.lastActiveAt;

// --- Command bar ------------------------------------------------------------

type Result =
  | { kind: 'go'; input: string; search: boolean }
  | { kind: 'tab'; tab: TabView };

function buildResults(query: string, tabs: TabView[]): Result[] {
  const q = query.trim();
  if (!q) return [...tabs].sort(byRecent).slice(0, 6).map(asTab);

  const url = toNavigableUrl(q);
  const go: Result[] = url
    ? [{ kind: 'go', input: q, search: isSearch(url) }]
    : [];
  const needle = q.toLowerCase();
  const matches = tabs
    .filter(
      (t) =>
        t.title.toLowerCase().includes(needle) ||
        t.url.toLowerCase().includes(needle),
    )
    .sort(byRecent)
    .slice(0, 5)
    .map(asTab);
  return [...go, ...matches];
}

const asTab = (tab: TabView): Result => ({ kind: 'tab', tab });

function runResult(result: Result) {
  if (result.kind === 'go') window.firn.openUrl(result.input);
  else window.firn.activateTab(result.tab.id);
}

function CommandBar({ tabs, beside }: { tabs: TabView[]; beside?: string }) {
  const [query, setQuery] = useState('');
  const [selected, setSelected] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);
  const results = useMemo(() => buildResults(query, tabs), [query, tabs]);
  const current = Math.min(selected, results.length - 1);

  useEffect(() => inputRef.current?.focus(), []);

  const onKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Escape') {
      window.firn.closeOverlay();
    } else if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault();
      const step = e.key === 'ArrowDown' ? 1 : -1;
      const count = results.length;
      if (count) setSelected((current + step + count) % count);
    } else if (e.key === 'Enter') {
      e.preventDefault();
      if (results[current]) runResult(results[current]);
    }
  };

  return (
    <div
      className="backdrop"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) window.firn.closeOverlay();
      }}
    >
      <div className="panel command-bar">
        <div className="command-input-row">
          <span className="command-search-icon">
            <SearchIcon />
          </span>
          <input
            ref={inputRef}
            className="command-input"
            spellCheck={false}
            placeholder={
              beside
                ? `Open beside “${beside.length > 32 ? `${beside.slice(0, 30)}…` : beside}”`
                : 'Search or enter address'
            }
            value={query}
            onChange={(e) => {
              setQuery(e.target.value);
              setSelected(0);
            }}
            onKeyDown={onKeyDown}
          />
        </div>

        {results.length > 0 && (
          <ul className="results">
            {results.map((result, i) => (
              <li
                key={result.kind === 'tab' ? result.tab.id : 'go'}
                className={`result ${i === current ? 'is-selected' : ''}`}
                onMouseMove={() => setSelected(i)}
                onClick={() => runResult(result)}
              >
                {result.kind === 'go' ? (
                  <>
                    <span className="tab-icon">
                      {result.search ? <SearchIcon /> : <GlobeIcon />}
                    </span>
                    <span className="result-title">
                      {result.search ? (
                        <>
                          {result.input}
                          <span className="result-detail"> — Search</span>
                        </>
                      ) : (
                        result.input
                      )}
                    </span>
                  </>
                ) : (
                  <>
                    <span className="tab-icon">
                      <TabIcon tab={result.tab} />
                    </span>
                    <span className="result-title">
                      {tabTitle(result.tab)}
                      <span className="result-detail">
                        {' — '}
                        {result.tab.url.replace(/^https?:\/\/(www\.)?/i, '')}
                      </span>
                    </span>
                    <span className="result-action">
                      Switch to tab <ArrowIcon />
                    </span>
                  </>
                )}
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}

// --- Ctrl+Tab switcher ------------------------------------------------------

function Switcher({
  tabIds,
  index,
  tabs,
}: {
  tabIds: string[];
  index: number;
  tabs: TabView[];
}) {
  const byId = new Map(tabs.map((t) => [t.id, t]));
  const list = tabIds.map((id) => byId.get(id)).filter((t) => t !== undefined);

  return (
    <div className="backdrop is-switcher">
      <div className="panel switcher">
        <ul className="results">
          {list.map((tab) => (
            <li
              key={tab.id}
              className={`result ${tab.id === tabIds[index] ? 'is-selected' : ''}`}
              onClick={() => window.firn.activateTab(tab.id)}
            >
              <span className="tab-icon">
                <TabIcon tab={tab} />
              </span>
              <span className="result-title">{tabTitle(tab)}</span>
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}

// --- Lookout -----------------------------------------------------------------

// Around a link previewed in Lookout: the page dimmed behind it, a stand-in
// panel that scales in (the real page appears on top of it once it has),
// and the buttons beside the panel. Clicking anywhere outside closes it.
function Lookout({
  phase,
  area,
  panel,
}: {
  phase: 'open' | 'closing' | 'expanding';
  area: Rect;
  panel: Rect;
}) {
  const box = (r: Rect) => ({
    left: r.x,
    top: r.y,
    width: r.width,
    height: r.height,
  });
  return (
    <div
      className={`lookout is-${phase}`}
      onPointerDown={(e) => {
        if (!(e.target as HTMLElement).closest('.lookout-actions'))
          window.firn.closeOverlay();
      }}
    >
      <div className="lookout-backdrop" style={box(area)} />
      <div className="lookout-panel" style={box(panel)} />
      <div
        className="lookout-actions"
        style={{ left: panel.x + panel.width + 10, top: panel.y }}
      >
        <button
          className="lookout-button"
          title="Close (Esc)"
          onClick={() => window.firn.closeOverlay()}
        >
          <CloseIcon />
        </button>
        <button
          className="lookout-button"
          title="Open as tab"
          onClick={() => window.firn.expandLookout()}
        >
          <ExpandIcon />
        </button>
      </div>
    </div>
  );
}
