// On the Firn article: Shift+click a link to preview it in Lookout, scroll
// it a little, and close it.
import { floating, web } from '../lib/director.mjs';

export default {
  name: 'lookout',
  seed: 'tabs',
  async setup(d) {
    await d.placeCursor(900, 700);
  },
  async run(d) {
    // The first ordinary article link that's on screen. (Wikipedia wraps
    // paragraphs in sections, and some are hidden, so any shown one.)
    const link = web('#mw-content-text p a[href^="/wiki/"]:not([href*=":"])', {
      url: '/wiki/Firn',
      inView: true,
    });
    await d.click(link, { shift: true });
    // The preview: the web page on screen that isn't the article.
    const preview = web('body', { notUrl: '/wiki/Firn' });
    await d.waitFor(preview);
    await d.settle(2500);
    await d.step();
    await d.scroll(preview, 320);
    await d.step();
    await d.still();
    await d.scroll(preview, 200);
    await d.step();
    await d.click(floating('[data-testid="lookout-close"]'));
    await d.pause(400);
  },
};
