// Dragging a tab out of the sidebar onto the page opens it in split view
// (see "Dragging a tab into split view" in src/tabs.ts). The sidebar's
// drags (tabs, and Basecamp tiles) use this to tell when the pointer has
// left the sidebar for the page, and to report it.

// How far past the sidebar's edge the pointer goes before it counts as
// over the page (so a drag that just brushes the edge stays a reorder).
const PAST_EDGE = 16;

// Whether the pointer is over the page; if so, Firn is told where.
export function dragOverPage(
  e: { clientX: number },
  tabId: string,
  from: Element | null,
) {
  const sidebar = from?.closest<HTMLElement>('.sidebar');
  if (!sidebar) return false;
  // Its resting edge (not where it's drawn: the peeking sidebar slides out
  // of the way while a tab is over the page).
  const edge = sidebar.offsetLeft + sidebar.offsetWidth;
  const over = e.clientX > edge + PAST_EDGE;
  if (over) window.firn.dragToSplit(tabId, e.clientX);
  return over;
}
