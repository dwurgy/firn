// Personal space: the pointer runs down the vertical tabs, opens a new tab,
// and searches for "three sisters oregon".
import { floating, ui } from '../lib/director.mjs';

const tab = (nth) =>
  ui('[data-testid="tab"][data-kind="everyday"]', { nth, at: [0.4, 0.5] });

export default {
  name: 'tabs-overview',
  seed: 'tabs',
  async setup(d) {
    await d.placeCursor(150, 640);
  },
  async run(d) {
    for (let i = 0; i < 3; i++) {
      await d.hover(tab(i));
      await d.pause(300);
    }
    await d.click(ui('[data-testid="new-tab"]'));
    await d.waitFor(floating('[data-testid="command-input"]'));
    await d.step();
    await d.type(
      floating('[data-testid="command-input"]'),
      'three sisters oregon',
    );
    await d.step();
    await d.press(floating('[data-testid="command-input"]'), 'Enter');
    await d.pause(500);
    await d.settle(2500);
    await d.still();
  },
};
