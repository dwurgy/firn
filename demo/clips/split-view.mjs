// Right-click a tab > "Split view with current tab", then ease the divider
// over a little. (Firn starts split view from a tab's right-click menu; it
// has no drag-a-tab-into-split.)
import { ui, web } from '../lib/director.mjs';

export default {
  name: 'split-view',
  seed: 'tabs',
  async setup(d) {
    await d.placeCursor(700, 600);
  },
  async run(d) {
    // "Sisters, Oregon", beside the Firn article on screen.
    const tab = ui('[data-testid="tab"][data-kind="everyday"]', {
      nth: 1,
      at: [0.4, 0.5],
    });
    await d.click(tab, { button: 'right' });
    await d.chooseMenuItem('Split view with current tab');
    await d.waitFor(ui('[data-testid="split-divider"]'));
    await d.settle(2500);
    await d.pause(1000);
    await d.still();
    await d.drag(ui('[data-testid="split-divider"]'), -90, 0);
    await d.step();
    // Off the divider (so its hover label fades), then the still.
    await d.hover(web('body', { notUrl: 'Sisters', at: [0.6, 0.6] }));
    await d.step();
    await d.still();
  },
};
