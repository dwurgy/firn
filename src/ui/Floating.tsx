import { useEffect, useMemo, useRef, useState } from 'react';
import { isSearch, toNavigableUrl } from '../url';
import type {
  CommandAction,
  HistoryEntry,
  OverlayState,
  Rect,
  Space,
  SpacesState,
  TabView,
} from '../types';
import { TabIcon, tabTitle } from './TabList';
import {
  ActionIcon,
  ArrowIcon,
  CloseIcon,
  ExpandIcon,
  GlobeIcon,
  HistoryIcon,
  SearchIcon,
} from './icons';

// The layer that floats above the web page: the command bar (new tab), the
// Ctrl+Tab switcher and Lookout's backdrop and buttons. It's transparent
// unless one of them is open.
export function Floating() {
  const [overlay, setOverlay] = useState<OverlayState>({ mode: 'hidden' });
  const [tabs, setTabs] = useState<TabView[]>([]);
  const [activeTabId, setActiveTabId] = useState<string | null>(null);
  const [spaces, setSpaces] = useState<SpacesState>({
    spaces: [],
    activeSpaceId: '',
  });

  useEffect(() => {
    const offs = [
      window.firn.onOverlayState(setOverlay),
      window.firn.onTabsState((state) => {
        setTabs(state.tabs);
        setActiveTabId(state.activeTabId);
      }),
      window.firn.onSpacesState(setSpaces),
    ];
    window.firn.ready();
    return () => offs.forEach((off) => off());
  }, []);

  if (overlay.mode === 'lookout') {
    return <Lookout key={overlay.openId} {...overlay} />;
  }
  if (overlay.mode === 'command') {
    return (
      <CommandBar
        key={overlay.openId}
        tabs={tabs}
        activeTabId={activeTabId}
        spaces={spaces}
        beside={overlay.beside}
      />
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
// Type an address or a search, or find an open tab (in any space), a page
// from the history, or a quick action. Results are kept short and calm:
// a few of each kind, best first.

type AnyTab = TabView & { spaceId: string };

interface Action {
  action: CommandAction;
  label: string;
  words: string; // extra words it answers to
  arg?: string;
}

type Result =
  | { kind: 'go'; input: string; search: boolean }
  | { kind: 'tab'; tab: AnyTab }
  | { kind: 'history'; entry: HistoryEntry }
  | { kind: 'action'; action: Action };

const resultKey = (r: Result) =>
  r.kind === 'tab'
    ? `tab:${r.tab.id}`
    : r.kind === 'history'
      ? `history:${r.entry.url}`
      : r.kind === 'action'
        ? `action:${r.action.action}:${r.action.arg ?? ''}`
        : 'go';

// Every word typed appears somewhere in `text`.
const matches = (text: string, words: string[]) => {
  const haystack = text.toLowerCase();
  return words.every((word) => haystack.includes(word));
};

// Every word typed starts one of the words in `text`.
const startsWords = (text: string, words: string[]) => {
  const own = text.toLowerCase().split(/\s+/);
  return words.every((word) => own.some((w) => w.startsWith(word)));
};

// The quick actions that make sense right now.
function actionsFor(
  active: TabView | undefined,
  spaces: SpacesState,
): Action[] {
  const actions: Action[] = [];
  if (active && !active.basecamp)
    actions.push({
      action: 'pin',
      label: active.pinned ? 'Unpin tab' : 'Pin tab',
      words: 'pin unpin',
    });
  if (active)
    actions.push(
      {
        action: 'basecamp',
        label: active.basecamp ? 'Remove from Basecamp' : 'Add to Basecamp',
        words: 'basecamp favorite',
      },
      {
        action: 'copy-link',
        label: 'Copy link',
        words: 'copy link url address',
      },
      { action: 'close', label: 'Close tab', words: 'close tab' },
    );
  if (active?.splitId)
    actions.push({
      action: 'separate',
      label: 'Separate split view',
      words: 'split separate unsplit',
    });
  actions.push(
    {
      action: 'reopen',
      label: 'Reopen closed tab',
      words: 'reopen undo closed',
    },
    {
      action: 'sidebar',
      label: 'Hide or show sidebar',
      words: 'sidebar hide show collapse',
    },
    {
      action: 'clear',
      label: 'Clear unpinned tabs',
      words: 'clear tabs close all',
    },
    { action: 'new-space', label: 'New space', words: 'new space add create' },
  );
  for (const space of spaces.spaces)
    if (space.id !== spaces.activeSpaceId)
      actions.push({
        action: 'switch-space',
        label: `Go to ${space.icon} ${space.name}`,
        words: `switch space go ${space.name}`,
        arg: space.id,
      });
  return actions;
}

function buildResults({
  query,
  shownTabs,
  allTabs,
  history,
  actions,
}: {
  query: string;
  shownTabs: TabView[];
  allTabs: AnyTab[];
  history: HistoryEntry[];
  actions: Action[];
}): Result[] {
  const q = query.trim();
  if (!q)
    return [...shownTabs]
      .sort(byRecent)
      .slice(0, 6)
      .map((tab) => ({ kind: 'tab', tab: tab as AnyTab }));

  const url = toNavigableUrl(q);
  const go: Result[] = url
    ? [{ kind: 'go', input: q, search: isSearch(url) }]
    : [];
  const words = q.toLowerCase().split(/\s+/).filter(Boolean);
  const tabs = allTabs
    .filter((t) => matches(`${t.title} ${t.url}`, words))
    .sort(byRecent)
    .slice(0, 4);
  // Pages that are already open show once, as their tab.
  const open = new Set(allTabs.map((t) => t.url));
  const pages = history.filter((h) => !open.has(h.url)).slice(0, 4);
  // Actions answer to the start of a word ("pi" → Pin tab), from two
  // letters on, so a single letter doesn't bring up a list of them.
  const doable =
    q.length < 2
      ? []
      : actions
          .filter((a) => startsWords(`${a.label} ${a.words}`, words))
          .slice(0, 3);
  return [
    ...go,
    ...tabs.map((tab): Result => ({ kind: 'tab', tab })),
    ...doable.map((action): Result => ({ kind: 'action', action })),
    ...pages.map((entry): Result => ({ kind: 'history', entry })),
  ];
}

function runResult(result: Result) {
  if (result.kind === 'go') window.firn.openUrl(result.input);
  else if (result.kind === 'tab') window.firn.activateTab(result.tab.id);
  else if (result.kind === 'history') window.firn.openUrl(result.entry.url);
  else window.firn.runAction(result.action.action, result.action.arg);
}

const shortUrl = (url: string) => url.replace(/^https?:\/\/(www\.)?/i, '');

function CommandBar({
  tabs,
  activeTabId,
  spaces,
  beside,
}: {
  tabs: TabView[];
  activeTabId: string | null;
  spaces: SpacesState;
  beside?: string;
}) {
  const [query, setQuery] = useState('');
  const [selected, setSelected] = useState(0);
  const [allTabs, setAllTabs] = useState<AnyTab[]>([]);
  const [history, setHistory] = useState<HistoryEntry[]>([]);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    inputRef.current?.focus();
    window.firn.allTabs().then(setAllTabs);
  }, []);

  // History matches arrive a moment after typing; the newest query wins.
  useEffect(() => {
    let current = true;
    const q = query.trim();
    if (!q) setHistory([]);
    else window.firn.searchHistory(q).then((h) => current && setHistory(h));
    return () => {
      current = false;
    };
  }, [query]);

  const active = tabs.find((t) => t.id === activeTabId);
  const results = useMemo(
    () =>
      buildResults({
        query,
        shownTabs: tabs,
        allTabs,
        history,
        // Opening something beside a tab: actions don't apply.
        actions: beside ? [] : actionsFor(active, spaces),
      }),
    [query, tabs, allTabs, history, beside, active, spaces],
  );
  const current = Math.min(selected, results.length - 1);
  const spaceOf = (id: string) => spaces.spaces.find((s) => s.id === id);

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
                : 'Search, enter an address, or type a command'
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
                key={resultKey(result)}
                className={`result is-${result.kind} ${i === current ? 'is-selected' : ''}`}
                onMouseMove={() => setSelected(i)}
                onClick={() => runResult(result)}
              >
                <ResultRow
                  result={result}
                  spaceOf={spaceOf}
                  activeSpaceId={spaces.activeSpaceId}
                />
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}

function ResultRow({
  result,
  spaceOf,
  activeSpaceId,
}: {
  result: Result;
  spaceOf: (id: string) => Space | undefined;
  activeSpaceId: string;
}) {
  if (result.kind === 'go')
    return (
      <>
        <span className="tab-icon">
          {result.search ? <SearchIcon /> : <GlobeIcon />}
        </span>
        <span className="result-title">
          {result.input}
          {result.search && <span className="result-detail"> — Search</span>}
        </span>
      </>
    );
  if (result.kind === 'tab') {
    const { tab } = result;
    // Tabs in another space say which.
    const space =
      !tab.basecamp && tab.spaceId !== activeSpaceId
        ? spaceOf(tab.spaceId)
        : undefined;
    return (
      <>
        <span className="tab-icon">
          <TabIcon tab={tab} />
        </span>
        <span className="result-title">
          {tabTitle(tab)}
          <span className="result-detail"> — {shortUrl(tab.url)}</span>
        </span>
        <span className="result-action">
          {space ? `${space.icon} ${space.name}` : 'Switch to tab'}
          <ArrowIcon />
        </span>
      </>
    );
  }
  if (result.kind === 'history') {
    const { entry } = result;
    return (
      <>
        <span className="tab-icon">
          <HistoryIcon />
        </span>
        <span className="result-title">
          {entry.title || shortUrl(entry.url)}
          <span className="result-detail"> — {shortUrl(entry.url)}</span>
        </span>
        <span className="result-action">
          Visited <ArrowIcon />
        </span>
      </>
    );
  }
  return (
    <>
      <span className="tab-icon">
        <ActionIcon />
      </span>
      <span className="result-title">{result.action.label}</span>
      <span className="result-action">Action</span>
    </>
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
