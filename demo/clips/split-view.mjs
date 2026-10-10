// In Weekend, drag crl-2026 out of the sidebar onto the page's right
// half: the tab stays under the pointer, the wind map glides over to make
// room, and letting go opens the two side by side. Then ease the divider
// over a little.
import { ui, web } from '../lib/director.mjs';

// The window is 1440×900 inside, the sidebar 260 wide: the page's right
// half is around here.
const RIGHT_HALF = { x: 1140, y: 470 };

export default {
  name: 'split-view',
  seed: 'tabs',
  // Opens on the wind map in Weekend.
  start: { space: 'Weekend', tab: 0 },
  async setup(d) {
    await d.placeCursor(700, 600);
  },
  async run(d) {
    const tab = ui('[data-testid="tab"][data-kind="everyday"]', {
      nth: 1,
      at: [0.4, 0.5],
    });
    await d.dragTo(tab, RIGHT_HALF.x, RIGHT_HALF.y, 1600);
    await d.waitFor(ui('[data-testid="split-divider"]'));
    await d.settle(2500);
    await d.pause(1000);
    await d.still();
    await d.drag(ui('[data-testid="split-divider"]'), -90, 0);
    await d.step();
    // Off the divider (so its hover label fades), then the still. (Onto
    // the page's area: the wind map is all canvas, with no element that
    // has a size.)
    await d.hover(web(':page', { notUrl: 'crl-2026', at: [0.6, 0.6] }));
    await d.step();
    await d.still();
  },
};
