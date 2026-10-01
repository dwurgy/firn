import { useEffect, useLayoutEffect, useRef, useState } from 'react';
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

// Drag to reorder: how far the pointer must move before a press becomes a
// drag (so ordinary clicks never turn into accidental drags).
const DRAG_THRESHOLD = 4;
const ROW_GAP = 4; // matches the gap between tab rows in styles.css
const SETTLE_MS = 200;

interface Drag {
  id: string;
  from: number;
  startY: number;
  dy: number;
  pitch: number; // row height plus gap
  active: boolean;
}

const clamp = (n: number, lo: number, hi: number) =>
  Math.max(lo, Math.min(hi, n));

// Where the dragged tab would land, given how far it has moved.
const targetIndex = (drag: Drag, count: number) =>
  clamp(drag.from + Math.round(drag.dy / drag.pitch), 0, count - 1);

export function TabList({
  tabs,
  activeTabId,
}: {
  tabs: TabView[];
  activeTabId: string | null;
}) {
  const [drag, setDrag] = useState<Drag | null>(null);
  // Right after a drop, the moved tab glides from where it was let go into
  // its new slot.
  const [settle, setSettle] = useState<{ id: string; offset: number } | null>(
    null,
  );
  // The new order, shown straight away while the main process catches up.
  const [localOrder, setLocalOrder] = useState<string[] | null>(null);
  const dragRef = useRef<Drag | null>(null);

  useEffect(() => setLocalOrder(null), [tabs]);

  useLayoutEffect(() => {
    if (!settle || settle.offset === 0) return;
    const frame = requestAnimationFrame(() =>
      setSettle((s) => s && { ...s, offset: 0 }),
    );
    const done = setTimeout(() => setSettle(null), SETTLE_MS + 50);
    return () => {
      cancelAnimationFrame(frame);
      clearTimeout(done);
    };
  }, [settle]);

  const byId = new Map(tabs.map((t) => [t.id, t]));
  const ordered = localOrder
    ? localOrder.map((id) => byId.get(id)).filter((t) => t !== undefined)
    : tabs;

  const updateDrag = (next: Drag | null) => {
    dragRef.current = next;
    setDrag(next);
  };

  const finishDrag = (commit: boolean) => {
    const d = dragRef.current;
    updateDrag(null);
    if (!d || !d.active || !commit) return;
    const to = targetIndex(d, ordered.length);
    if (to === d.from) {
      setSettle({ id: d.id, offset: d.dy });
      return;
    }
    const ids = ordered.map((t) => t.id);
    ids.splice(d.from, 1);
    ids.splice(to, 0, d.id);
    setLocalOrder(ids);
    // Keep it exactly where it was dropped, then let it glide into place.
    setSettle({ id: d.id, offset: d.dy - (to - d.from) * d.pitch });
    window.firn.moveTab(d.id, to);
  };

  // How far each row is nudged to make room for the dragged one.
  const shiftFor = (index: number) => {
    if (!drag?.active) return 0;
    const to = targetIndex(drag, ordered.length);
    if (drag.from < to && index > drag.from && index <= to) return -drag.pitch;
    if (drag.from > to && index >= to && index < drag.from) return drag.pitch;
    return 0;
  };

  return (
    <ul
      className={`tab-list ${drag?.active ? 'is-dragging' : ''} ${
        settle ? 'is-settling' : ''
      }`}
    >
      {ordered.map((tab, index) => {
        const isDragged = drag?.active && drag.id === tab.id;
        const isSettling = settle?.id === tab.id;
        const offset = isDragged
          ? drag.dy
          : isSettling
            ? settle.offset
            : shiftFor(index);
        return (
          <li
            key={tab.id}
            className={[
              'tab',
              tab.id === activeTabId && 'is-active',
              isDragged && 'is-dragged',
              isSettling && 'is-settling-row',
            ]
              .filter(Boolean)
              .join(' ')}
            style={
              offset ? { transform: `translateY(${offset}px)` } : undefined
            }
            title={tabTitle(tab)}
            onPointerDown={(e) => {
              if (e.button !== 0) return;
              window.firn.activateTab(tab.id);
              e.currentTarget.setPointerCapture(e.pointerId);
              updateDrag({
                id: tab.id,
                from: index,
                startY: e.clientY,
                dy: 0,
                pitch: e.currentTarget.offsetHeight + ROW_GAP,
                active: false,
              });
            }}
            onPointerMove={(e) => {
              const d = dragRef.current;
              if (!d || d.id !== tab.id) return;
              const raw = e.clientY - d.startY;
              const active = d.active || Math.abs(raw) > DRAG_THRESHOLD;
              // Keep it within the list.
              const dy = clamp(
                raw,
                -d.from * d.pitch,
                (ordered.length - 1 - d.from) * d.pitch,
              );
              if (active) updateDrag({ ...d, dy, active });
            }}
            onPointerUp={() => finishDrag(true)}
            onPointerCancel={() => finishDrag(false)}
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
              onPointerDown={(e) => e.stopPropagation()}
              onClick={() => window.firn.closeTab(tab.id)}
            >
              <CloseIcon />
            </button>
          </li>
        );
      })}
    </ul>
  );
}
