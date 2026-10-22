// The goodbye card (src/farewell.ts): shown once, the first time this version
// opens (after the welcome on a fresh install, instead of What's new on an
// update), never again, and anytime from the Firn menu. Its button opens the
// address in src/farewell.ts in a new tab. (Linux runs the Windows/Linux
// words; the Mac words are picked by the same line in Farewell.tsx.)
const { _electron } = require('./playwright.cjs');
const ROOT = require('path').resolve(__dirname, '../..');
const fs = require('fs');
const { execSync } = require('child_process');
const SP = process.env.SP;
const SETTINGS = '/root/.config/Firn/settings.json';
const VERSION = require('../../package.json').version;
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
const results = [];
const check = (n, ok, x = '') => {
  results.push(ok);
  console.log(
    `${ok ? 'PASS' : 'FAIL'}  ${n}${x !== '' ? '  (' + x + ')' : ''}`,
  );
};

const launch = async (settings) => {
  execSync('rm -f /root/.config/Firn/session.json');
  if (settings) fs.writeFileSync(SETTINGS, JSON.stringify(settings));
  else fs.rmSync(SETTINGS, { force: true });
  const app = await _electron.launch({
    args: ['--no-sandbox', '.'],
    cwd: ROOT,
    executablePath: require('path').join(
      ROOT,
      'node_modules/electron/dist/electron',
    ),
  });
  await wait(6500);
  const fl = app.windows().find((w) => w.url().includes('view=floating'));
  const ui = app.windows().find((w) => w.url().endsWith(':5173/'));
  return { app, fl, ui };
};
const shown = (fl) =>
  fl.evaluate(() => {
    const card = document.querySelector('[data-testid="farewell"]');
    if (!card) return null;
    return {
      title: card.querySelector('h2')?.textContent,
      paragraphs: [...card.querySelectorAll('.whats-new-body p')].map(
        (p) => p.textContent,
      ),
      buttons: [...card.querySelectorAll('.sheet-footer button')].map(
        (b) => b.textContent,
      ),
      whatsNew: !!document.querySelector('.whats-new-sheet'),
    };
  });
const seen = () => JSON.parse(fs.readFileSync(SETTINGS, 'utf8')).farewellSeen;

(async () => {
  // 1. An updated install: the card, instead of What's new.
  let { app, fl, ui } = await launch({
    onboarded: true,
    lastVersion: '0.0.9',
  });
  let w = await shown(fl);
  check(
    "after an update, the goodbye card opens by itself (not What's new)",
    !!w && !w.whatsNew,
    JSON.stringify(w?.title),
  );
  check(
    '...with the Windows/Linux words and its two buttons',
    w?.title === 'This is the last Firn for Windows.' &&
      w.paragraphs.length === 4 &&
      w.paragraphs[3] === '— David' &&
      w.buttons.includes('Read why') &&
      w.buttons.includes('Close'),
    JSON.stringify(w?.buttons),
  );
  check('...and it is noted as seen right away', seen() === true);
  execSync(`import -window root -crop 1000x700+0+0 ${SP}/farewell.png || true`);
  await fl.click('[data-testid="farewell"] .is-quiet');
  await wait(500);
  check('"Close" closes it', (await shown(fl)) === null);
  await app.close();

  // 2. The next start: quiet.
  ({ app, fl, ui } = await launch(
    JSON.parse(fs.readFileSync(SETTINGS, 'utf8')),
  ));
  check('the next start is quiet', (await shown(fl)) === null);

  // 3. The Firn menu reopens it; Esc closes it.
  await app.evaluate(({ Menu }) => {
    Menu.buildFromTemplate = (t) => {
      globalThis.__menu = t;
      return { popup() {} };
    };
  });
  await ui.click('.sidebar-bottom .firn-menu-button');
  await wait(300);
  await app.evaluate(() =>
    globalThis.__menu.find((i) => i.label === 'A note from David').click(),
  );
  await wait(500);
  check('"A note from David" in the Firn menu reopens it', !!(await shown(fl)));
  await fl.keyboard.press('Escape');
  await wait(400);
  check('Esc closes it', (await shown(fl)) === null);

  // 4. The link button: closes the card, opens the address in a new tab.
  await app.evaluate(() =>
    globalThis.__menu.find((i) => i.label === 'A note from David').click(),
  );
  await wait(500);
  const before = await app.evaluate(
    ({ webContents }) => webContents.getAllWebContents().length,
  );
  await fl.click('[data-testid="farewell-link"]');
  await wait(1500);
  const after = await app.evaluate(
    ({ webContents }) => webContents.getAllWebContents().length,
  );
  const tabs = await ui.evaluate(
    () => document.querySelectorAll('.tab-row, [data-testid^="tab"]').length,
  );
  check('"Read why" closes the card', (await shown(fl)) === null);
  check(
    '...and opens the address in a new tab',
    after > before,
    `${before} -> ${after}, ${tabs} rows`,
  );
  await app.close();

  // 5. A fresh install: the welcome first, the card right after it.
  ({ app, fl } = await launch(null));
  check(
    'a fresh install gets the welcome first, not the card',
    (await fl.evaluate(() => !!document.querySelector('.welcome'))) &&
      (await shown(fl)) === null,
  );
  check('...and the card is not marked seen yet', seen() !== true);
  await app.close();

  console.log(
    `\n${results.filter(Boolean).length}/${results.length} checks passed`,
  );
})().catch((e) => {
  console.log('TEST ERROR', e.message);
  process.exit(1);
});
