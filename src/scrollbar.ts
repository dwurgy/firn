// Firn's own scrollbar for web pages, like Zen's: it floats over the page
// (no strip of the page is given up for it), a soft thumb sits on top of the
// content with a see-through background, and hovering it darkens and widens
// the thumb and shows a faint track. It can be dragged, and clicking above
// or below the thumb moves a page.
//
// It replaces the page's main scrollbar only. Smaller scrolling areas inside
// pages keep a thin, rounded scrollbar (styled below).
//
// The script runs in an "isolated world": it shares the page's layout but
// not its JavaScript, so a website can't interfere with it or read it. Its
// pieces live in a closed shadow root, so the site's styles can't reach them.

// Hides the page's own main scrollbar (ours replaces it) and gives inner
// scrolling areas a thin, rounded one. "!important" in the user stylesheet
// outranks a site's own scrollbar styling.
export const SCROLLBAR_CSS = `
html { scrollbar-width: none !important; }
html::-webkit-scrollbar { display: none !important; }
body, body * { scrollbar-width: auto !important; scrollbar-color: auto !important; }
body::-webkit-scrollbar, body *::-webkit-scrollbar { width: 12px !important; height: 12px !important; background: transparent !important; }
body ::-webkit-scrollbar-track { background: transparent !important; border: none !important; box-shadow: none !important; }
body ::-webkit-scrollbar-corner { background: transparent !important; }
body ::-webkit-scrollbar-button { display: none !important; }
body ::-webkit-scrollbar-thumb {
  background-color: rgba(128, 128, 128, 0.45) !important;
  background-image: none !important;
  border: 3.5px solid transparent !important;
  border-radius: 12px !important;
  background-clip: padding-box !important;
  box-shadow: none !important;
  min-height: 40px !important;
}
body ::-webkit-scrollbar-thumb:hover { background-color: rgba(110, 110, 110, 0.7) !important; border-width: 2px !important; }
`;

// A separate isolated world just for the scrollbar.
export const SCROLLBAR_WORLD_ID = 1999;

export const SCROLLBAR_SCRIPT = `
(() => {
  if (window.__firnScrollbar) return;
  window.__firnScrollbar = true;

  const host = document.createElement('div');
  host.style.cssText =
    'position:fixed;top:0;right:0;bottom:0;width:14px;z-index:2147483647;' +
    'pointer-events:none;display:none;';
  const root = host.attachShadow({ mode: 'closed' });
  root.innerHTML = \`
    <style>
      .bar { position: absolute; inset: 4px 0; pointer-events: auto; }
      .track {
        position: absolute; inset: 0 2px; border-radius: 6px;
        background: rgba(128, 128, 128, 0); transition: background 150ms ease-out;
      }
      .thumb {
        position: absolute; right: 4px; width: 6px; border-radius: 6px;
        background: rgba(128, 128, 128, 0.5);
        box-shadow: 0 0 0 0.5px rgba(255, 255, 255, 0.35);
        transition: width 150ms ease-out, right 150ms ease-out,
          background 150ms ease-out;
      }
      .bar:hover .track, .bar.dragging .track { background: rgba(128, 128, 128, 0.14); }
      .bar:hover .thumb, .bar.dragging .thumb {
        width: 9px; right: 2.5px; background: rgba(105, 105, 105, 0.8);
      }
    </style>
    <div class="bar"><div class="track"></div><div class="thumb"></div></div>
  \`;
  const bar = root.querySelector('.bar');
  const thumb = root.querySelector('.thumb');
  const MIN_THUMB = 32;

  const scroller = () => document.scrollingElement || document.documentElement;
  let geometry = null;

  // The full check (can the page scroll at all, how big is the thumb) runs
  // when the page changes size; while scrolling only the thumb moves, so
  // scrolling never makes the page work out its styles again.
  const measure = () => {
    const el = scroller();
    const view = window.innerHeight;
    const total = el.scrollHeight;
    const scrollable = total - view > 1 && !document.fullscreenElement &&
      getComputedStyle(document.documentElement).overflowY !== 'hidden' &&
      getComputedStyle(document.body || document.documentElement).overflowY !== 'hidden';
    if (!scrollable) { host.style.display = 'none'; geometry = null; return; }
    host.style.display = 'block';
    const room = view - 8; // the bar is inset 4px top and bottom
    const size = Math.max(MIN_THUMB, Math.round(room * (view / total)));
    thumb.style.height = size + 'px';
    geometry = { size, travel: room - size, maxScroll: total - view, top: 0 };
    position();
  };

  const position = () => {
    if (!geometry) return;
    const ratio = Math.min(1, Math.max(0, scroller().scrollTop / geometry.maxScroll));
    const top = Math.round(ratio * geometry.travel);
    if (top === geometry.top && thumb.style.transform) return;
    geometry.top = top;
    thumb.style.transform = 'translateY(' + top + 'px)';
  };

  let frame = 0;
  let full = false;
  const schedule = (needsMeasure) => {
    full = full || needsMeasure;
    if (frame) return;
    frame = requestAnimationFrame(() => {
      frame = 0;
      const doMeasure = full;
      full = false;
      if (doMeasure) measure(); else position();
    });
  };
  const update = () => schedule(true);
  const onScroll = () => schedule(false);

  // Dragging the thumb.
  let drag = null;
  thumb.addEventListener('pointerdown', (e) => {
    if (e.button !== 0 || !geometry) return;
    e.preventDefault(); e.stopPropagation();
    thumb.setPointerCapture(e.pointerId);
    drag = { y: e.clientY, start: scroller().scrollTop };
    bar.classList.add('dragging');
  });
  thumb.addEventListener('pointermove', (e) => {
    if (!drag || !geometry || geometry.travel <= 0) return;
    const ratio = geometry.maxScroll / geometry.travel;
    scroller().scrollTop = drag.start + (e.clientY - drag.y) * ratio;
  });
  const endDrag = () => { drag = null; bar.classList.remove('dragging'); };
  thumb.addEventListener('pointerup', endDrag);
  thumb.addEventListener('pointercancel', endDrag);
  thumb.addEventListener('lostpointercapture', endDrag);

  // Clicking the track above or below the thumb moves a page.
  bar.addEventListener('pointerdown', (e) => {
    if (e.button !== 0 || !geometry || e.target === thumb) return;
    e.preventDefault();
    const y = e.clientY - 4;
    const page = window.innerHeight * 0.9;
    scroller().scrollBy({ top: y < geometry.top ? -page : page, behavior: 'smooth' });
  });

  addEventListener('scroll', onScroll, { passive: true });
  addEventListener('resize', update);
  document.addEventListener('fullscreenchange', update);
  const watchSize = new ResizeObserver(update);
  const attach = () => {
    document.documentElement.appendChild(host);
    watchSize.observe(document.documentElement);
    if (document.body) watchSize.observe(document.body);
    update();
  };
  attach();
  // Some sites replace the page's body or remove unknown elements; put the
  // scrollbar back if that happens.
  new MutationObserver(() => {
    if (!host.isConnected) attach();
    else update();
  }).observe(document.documentElement, { childList: true });
  // Content can grow without resizing the window (e.g. infinite scroll).
  setInterval(update, 1000);
})();
`;
