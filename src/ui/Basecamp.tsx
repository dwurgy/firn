import {
  useLayoutEffect,
  useRef,
  useState,
  type CSSProperties,
  type PointerEvent as ReactPointerEvent,
} from 'react';
import type { TabView } from '../types';
import { useIconColor } from './iconColor';
import { TabIcon, TabSound, tabTitle } from './TabList';

// Basecamp: a grid of favorite sites at the top of the sidebar, the same in
// every space (at most 12). Closing one (middle-click) unloads it rather
// than removing it; right-click for "Go back to home" and "Remove from
// Basecamp".
//
// The tiles share each row evenly: one pin fills the row, two split it, and
// so on, until the tiles would get too narrow and a new row starts (so a
// wider sidebar fits more per row).
//
// Drag a tile to reorder Basecamp, like the sidebar's tabs: it lifts and
// follows the pointer, the others glide aside to make room, and it settles
// into its new place. (Within Basecamp only.)

// How far the pointer must move before a press becomes a drag (so ordinary
// clicks never turn into accidental drags).
const DRAG_THRESHOLD = 4;
const GLIDE = { duration: 200, easing: 'cubic-bezier(0.33, 1, 0.68, 1)' };

interface Spot {
  x: number;
  y: number;
}

interface Drag {
  id: string;
  startX: number;
  startY: number;
  dx: number;
  dy: number;
  active: boolean;
  // Measured once the drag starts: each tile's spot within the grid, and
  // the grid's size.
  spots: Map<string, Spot>;
  size: {
    width: number;
    height: number;
    tileWidth: number;
    tileHeight: number;
  };
}

export function Basecamp({
  tabs,
  activeTabId,
}: {
  tabs: TabView[];
  activeTabId: string | null;
}) {
  const gridRef = useRef<HTMLDivElement>(null);
  const dragRef = useRef<Drag | null>(null);
  const [drag, setDrag] = useState<Drag | null>(null);
  // After a drop, tiles stay where they were dropped until the new order
  // arrives; then they glide from there into place.
  const [pending, setPending] = useState<{
    signature: string;
    offsets: Map<string, Spot>;
  } | null>(null);
  const [returning, setReturning] = useState<string | null>(null);
  const ids = tabs.map((t) => t.id);
  const signature = ids.join(',');

  // --- Gliding into new places ----------------------------------------------
  // When the tiles change (a drop, one added or removed), note where each
  // one was just before the update, then glide it from there.
  const lastSignature = useRef(signature);
  const before = useRef<Map<string, Spot> | null>(null);
  if (lastSignature.current !== signature) {
    lastSignature.current = signature;
    before.current = spotsOf(gridRef.current);
  }
  useLayoutEffect(() => {
    const was = before.current;
    before.current = null;
    const grid = gridRef.current;
    if (!was || !grid) return;
    const now = spotsOf(grid);
    for (const el of tileElements(grid)) {
      const id = el.dataset.tile!;
      const from = was.get(id);
      const to = now.get(id)!;
      if (!from) el.animate([{ opacity: 0 }, { opacity: 1 }], GLIDE);
      else if (Math.abs(from.x - to.x) > 0.5 || Math.abs(from.y - to.y) > 0.5)
        el.animate(
          [
            { translate: `${from.x - to.x}px ${from.y - to.y}px` },
            { translate: '0 0' },
          ],
          GLIDE,
        );
    }
  });

  // --- Dragging ---------------------------------------------------------------

  const update = (next: Drag | null) => {
    dragRef.current = next;
    setDrag(next);
  };

  // Where the dragged tile would land: the spot nearest its middle.
  const dropIndex = (d: Drag) => {
    const self = d.spots.get(d.id)!;
    const x = self.x + d.dx;
    const y = self.y + d.dy;
    let best = 0;
    let bestDistance = Infinity;
    ids.forEach((id, i) => {
      const spot = d.spots.get(id)!;
      const distance = (spot.x - x) ** 2 + (spot.y - y) ** 2;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = i;
      }
    });
    return best;
  };

  // How far each tile moves to make room: the others shift into the spots
  // of the new order; the dragged one stays under the pointer.
  const offsetsFor = (d: Drag) => {
    const offsets = new Map<string, Spot>();
    const order = ids.filter((id) => id !== d.id);
    order.splice(dropIndex(d), 0, d.id);
    order.forEach((id, i) => {
      if (id === d.id) return;
      const from = d.spots.get(id)!;
      const to = d.spots.get(ids[i])!;
      if (from.x !== to.x || from.y !== to.y)
        offsets.set(id, { x: to.x - from.x, y: to.y - from.y });
    });
    offsets.set(d.id, { x: d.dx, y: d.dy });
    return offsets;
  };

  const onPointerDown = (e: ReactPointerEvent, id: string) => {
    if (e.button !== 0) return;
    window.firn.activateTab(id);
    // (A click without a real pointer behind it can't be captured; it still
    // switches tabs, it just can't start a drag.)
    try {
      e.currentTarget.setPointerCapture(e.pointerId);
    } catch {
      return;
    }
    if (tabs.length < 2) return;
    update({
      id,
      startX: e.clientX,
      startY: e.clientY,
      dx: 0,
      dy: 0,
      active: false,
      spots: new Map(),
      size: { width: 0, height: 0, tileWidth: 0, tileHeight: 0 },
    });
  };

  const onPointerMove = (e: ReactPointerEvent) => {
    const d = dragRef.current;
    const grid = gridRef.current;
    if (!d || !grid) return;
    const rawX = e.clientX - d.startX;
    const rawY = e.clientY - d.startY;
    if (!d.active) {
      if (Math.hypot(rawX, rawY) <= DRAG_THRESHOLD) return;
      setPending(null);
      setReturning(null);
      d.spots = spotsOf(grid);
      const tile = tileElements(grid)[0];
      d.size = {
        width: grid.clientWidth,
        height: grid.clientHeight,
        tileWidth: tile.offsetWidth,
        tileHeight: tile.offsetHeight,
      };
    }
    // Keep it within Basecamp.
    const self = d.spots.get(d.id)!;
    const dx = Math.max(
      -self.x,
      Math.min(d.size.width - d.size.tileWidth - self.x, rawX),
    );
    const dy = Math.max(
      -self.y,
      Math.min(d.size.height - d.size.tileHeight - self.y, rawY),
    );
    update({ ...d, dx, dy, active: true });
  };

  const finish = (commit: boolean) => {
    const d = dragRef.current;
    update(null);
    if (!d?.active) return;
    const to = commit ? dropIndex(d) : ids.indexOf(d.id);
    if (to === ids.indexOf(d.id)) {
      // Glide back to where it was.
      setReturning(d.id);
      setTimeout(() => setReturning(null), GLIDE.duration + 50);
      return;
    }
    setPending({ signature, offsets: offsetsFor(d) });
    window.firn.moveTab(d.id, to);
    // In case the move doesn't happen, don't leave tiles out of place.
    setTimeout(() => setPending(null), 1000);
  };

  if (!tabs.length) return null;
  const offsets = drag?.active
    ? offsetsFor(drag)
    : pending?.signature === signature
      ? pending.offsets
      : null;
  return (
    <div className="basecamp">
      <div
        ref={gridRef}
        className={`basecamp-grid ${drag?.active ? 'is-dragging' : ''}`}
      >
        {tabs.map((tab) => {
          const offset = offsets?.get(tab.id);
          return (
            <BasecampTile
              key={tab.id}
              tab={tab}
              active={tab.id === activeTabId}
              dragged={drag?.active === true && drag.id === tab.id}
              returning={returning === tab.id}
              offset={offset}
              onPointerDown={(e) => onPointerDown(e, tab.id)}
              onPointerMove={onPointerMove}
              onPointerUp={() => finish(true)}
              onPointerCancel={() => finish(false)}
            />
          );
        })}
      </div>
    </div>
  );
}

function BasecampTile({
  tab,
  active,
  dragged,
  returning,
  offset,
  ...handlers
}: {
  tab: TabView;
  active: boolean;
  dragged: boolean;
  returning: boolean;
  offset?: Spot;
  onPointerDown: (e: ReactPointerEvent) => void;
  onPointerMove: (e: ReactPointerEvent) => void;
  onPointerUp: () => void;
  onPointerCancel: () => void;
}) {
  // The active tile is tinted with its icon's own color.
  const color = useIconColor(tab.favicon);
  return (
    <button
      className={[
        'basecamp-tile',
        active && 'is-active',
        color && 'is-tinted',
        !tab.loaded && 'is-unloaded',
        dragged && 'is-dragged',
        returning && 'is-returning',
      ]
        .filter(Boolean)
        .join(' ')}
      style={
        {
          ...(color && { '--pin-rgb': color }),
          ...(offset && {
            transform: `translate(${offset.x}px, ${offset.y}px)`,
          }),
        } as CSSProperties
      }
      data-tile={tab.id}
      title={tabTitle(tab)}
      {...handlers}
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
      <TabSound tab={tab} badge />
    </button>
  );
}

// The grid's tiles, in order.
function tileElements(grid: HTMLElement) {
  return [...grid.querySelectorAll<HTMLElement>('[data-tile]')];
}

// Where each tile is drawn within the grid (moved tiles included).
function spotsOf(grid: HTMLElement | null) {
  const spots = new Map<string, Spot>();
  if (!grid) return spots;
  const box = grid.getBoundingClientRect();
  for (const el of tileElements(grid)) {
    const r = el.getBoundingClientRect();
    spots.set(el.dataset.tile!, { x: r.left - box.left, y: r.top - box.top });
  }
  return spots;
}
