// Firn's own hover labels, in place of the system's tooltips (Windows'
// square boxes, macOS's pale ones): a small rounded label that fades in
// below what's hovered.
//
// Buttons keep their plain `title="…"` in the code; this moves each one to
// `data-tip` as it appears (so the system's tooltip never shows) and gives
// it an aria-label if it has none, so screen readers still name it.
//
// A label can't draw outside its own layer: in the sidebar it stays inside
// the sidebar (wrapping a long name) instead of spilling over the page.
// The slim top bar has no room under its buttons, so it keeps the system's
// tooltips (not installed there).

const SHOW_AFTER_MS = 500;
// Moving straight from one labelled thing to the next shows its label at
// once, the way system tooltips do.
const QUICK_FOR_MS = 400;
const GAP = 6;
const MARGIN = 8;

export function installTooltips(view: string) {
  const adopt = (el: Element) => {
    const title = el.getAttribute('title');
    if (title === null) return;
    el.removeAttribute('title');
    if (!title) return;
    el.setAttribute('data-tip', title);
    if (!el.hasAttribute('aria-label') && !el.textContent?.trim())
      el.setAttribute('aria-label', title);
  };
  const adoptAll = (root: ParentNode) =>
    root.querySelectorAll('[title]').forEach(adopt);
  adoptAll(document);
  new MutationObserver((changes) => {
    for (const change of changes) {
      if (change.type === 'attributes') adopt(change.target as Element);
      else
        change.addedNodes.forEach((node) => {
          if (node instanceof Element) {
            adopt(node);
            adoptAll(node);
          }
        });
    }
  }).observe(document.documentElement, {
    subtree: true,
    childList: true,
    attributes: true,
    attributeFilter: ['title'],
  });

  const tip = document.createElement('div');
  tip.className = 'firn-tip';
  tip.setAttribute('role', 'tooltip');
  tip.setAttribute('aria-hidden', 'true');
  document.body.append(tip);

  let target: Element | null = null;
  let timer = 0;
  let hiddenAt = 0;
  let pressed = false;

  // The area a label may use: the sidebar column in the sidebar's layers
  // (the page covers the rest), the whole layer elsewhere.
  const bounds = (el: Element) => {
    const box = { left: 0, top: 0, right: innerWidth, bottom: innerHeight };
    if (view === 'floating') return box;
    const sidebar =
      el.closest('.sidebar') ?? document.querySelector('.sidebar');
    if (!sidebar) return box;
    const r = sidebar.getBoundingClientRect();
    return {
      left: Math.max(0, r.left),
      top: Math.max(0, r.top),
      right: Math.min(innerWidth, r.right),
      bottom: Math.min(innerHeight, r.bottom),
    };
  };

  // A row whose name is fully shown needs no label repeating it; one cut
  // off ("DatHost User Login & Acc…") does.
  const repeatsVisibleText = (el: Element, text: string) => {
    const shown = [el, ...el.querySelectorAll('*')].find(
      (e) => e.childElementCount === 0 && e.textContent?.trim() === text,
    );
    return !!shown && shown.scrollWidth <= shown.clientWidth;
  };

  const place = (el: Element) => {
    const area = bounds(el);
    const r = el.getBoundingClientRect();
    tip.style.maxWidth = `${Math.max(0, area.right - area.left - MARGIN * 2)}px`;
    const w = tip.offsetWidth;
    const h = tip.offsetHeight;
    const centre = r.left + r.width / 2;
    const left = Math.min(
      Math.max(centre - w / 2, area.left + MARGIN),
      area.right - MARGIN - w,
    );
    // Below, or above when there's no room below.
    let top = r.bottom + GAP;
    if (top + h > area.bottom - MARGIN) top = r.top - GAP - h;
    tip.style.left = `${Math.round(left)}px`;
    tip.style.top = `${Math.round(Math.max(area.top + MARGIN, top))}px`;
  };

  const show = (el: Element) => {
    const text = el.getAttribute('data-tip');
    if (!text || !el.isConnected) return;
    tip.textContent = text;
    tip.classList.add('is-placing');
    place(el);
    tip.classList.remove('is-placing');
    tip.classList.add('is-shown');
  };

  const hide = () => {
    clearTimeout(timer);
    if (tip.classList.contains('is-shown')) hiddenAt = performance.now();
    tip.classList.remove('is-shown');
    target = null;
  };

  document.addEventListener('pointerover', (e) => {
    const el = (e.target as Element).closest?.('[data-tip]') ?? null;
    if (el === target) return;
    hide();
    if (!el || pressed) return;
    if (repeatsVisibleText(el, el.getAttribute('data-tip') ?? '')) return;
    target = el;
    const quick = performance.now() - hiddenAt < QUICK_FOR_MS;
    timer = window.setTimeout(() => show(el), quick ? 0 : SHOW_AFTER_MS);
  });
  document.addEventListener('pointerout', (e) => {
    const to = (e.relatedTarget as Element | null)?.closest?.('[data-tip]');
    if (target && to !== target) hide();
  });
  // Clicking, dragging, typing, or scrolling puts the label away.
  document.addEventListener(
    'pointerdown',
    () => {
      pressed = true;
      hide();
      hiddenAt = 0;
    },
    true,
  );
  document.addEventListener('pointerup', () => (pressed = false), true);
  document.addEventListener('keydown', hide, true);
  document.addEventListener('wheel', hide, { capture: true, passive: true });
  document.addEventListener('scroll', hide, true);
  window.addEventListener('blur', hide);
  document.documentElement.addEventListener('pointerleave', hide);
}
