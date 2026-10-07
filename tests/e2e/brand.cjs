const { _electron } = require('./playwright.cjs');
const ROOT = require('path').resolve(__dirname, '../..');
const fs = require('fs');
const { execSync } = require('child_process');
const SP = process.env.SP;
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
const results = [];
const check = (n, ok, x = '') => {
  results.push(ok);
  console.log(
    `${ok ? 'PASS' : 'FAIL'}  ${n}${x !== '' ? '  (' + x + ')' : ''}`,
  );
};
(async () => {
  execSync('rm -f /root/.config/Firn/session.json');
  fs.writeFileSync(
    '/root/.config/Firn/settings.json',
    JSON.stringify({ onboarded: true }),
  );
  const app = await _electron.launch({
    args: ['--no-sandbox', '.'],
    cwd: ROOT,
    executablePath: require('path').join(
      ROOT,
      'node_modules/electron/dist/electron',
    ),
  });
  await wait(6000);
  const ui = app.windows().find((w) => w.url().endsWith(':5173/'));
  const fl = app.windows().find((w) => w.url().includes('view=floating'));
  const o = await app.evaluate(({ BrowserWindow }) =>
    BrowserWindow.getAllWindows()[0].getContentBounds(),
  );
  const shot = (n) =>
    execSync(
      `import -window root -crop ${o.width}x${o.height}+${o.x}+${o.y} ${SP}/${n}.png`,
    );
  const fam = (w, sel) =>
    w.evaluate(async (sel) => {
      await document.fonts.ready;
      const e = document.querySelector(sel);
      return e ? getComputedStyle(e).fontFamily.split(',')[0] : null;
    }, sel);
  // close every tab -> empty page
  await ui.evaluate(() => window.firn.clearTabs());
  await wait(300);
  for (let i = 0; i < 5; i++) {
    const ids = await ui.evaluate(
      () => [...document.querySelectorAll('.tab')].length,
    );
    if (!ids) break;
    await ui.keyboard.press('Control+W');
    await wait(400);
  }
  await fl.keyboard.press('Escape').catch(() => {});
  await ui.evaluate(() => window.firn.closeOverlay());
  await wait(800);
  check(
    'empty page title in Fraunces',
    (await fam(ui, '.empty-title')) === 'Fraunces',
    await fam(ui, '.empty-title'),
  );
  shot('brand-empty');

  // First light on the empty page: the welcome's sky and sunrise (the same
  // for every space), and the snow and mark in the space's color.
  const emptyLook = () =>
    ui.evaluate(() => {
      const layers = document.querySelectorAll('.page-area .fl-snow-layer');
      const top = layers[layers.length - 1];
      return {
        bands: top ? top.querySelectorAll('path').length : 0,
        tinted: !!top?.classList.contains('is-tinted'),
        snow: top
          ? getComputedStyle(top.querySelector('path:nth-child(5)')).fill
          : null,
        sky: [
          document.querySelector('.page-area .fl-sky'),
          document.querySelector('.page-area .fl-sun'),
        ]
          .map((e) => (e ? getComputedStyle(e).backgroundImage : ''))
          .join(' | '),
        mark: getComputedStyle(document.querySelector('.empty-mark'))
          .backgroundColor,
        moving: document
          .getAnimations()
          .some(
            (a) =>
              a.playState === 'running' &&
              a.effect?.getTiming().iterations === Infinity,
          ),
      };
    });
  const before = await emptyLook();
  check(
    'empty page: the sky, the sunrise and five snow bands (Glacier, the first space)',
    before.bands === 5 &&
      !before.tinted &&
      before.snow === 'rgb(110, 152, 178)' &&
      before.sky.includes('radial-gradient') &&
      before.mark === 'rgb(127, 156, 176)',
    JSON.stringify(before),
  );
  check('...and nothing moves while it sits there', !before.moving);
  const spaceId = await ui.evaluate(
    () =>
      new Promise((r) => {
        const off = window.firn.onSpacesState((s) => {
          off();
          r(s.activeSpaceId);
        });
        window.firn.ready();
      }),
  );
  await ui.evaluate(
    (id) => window.firn.updateSpace(id, { color: '#8e8fb8' }),
    spaceId,
  );
  await wait(800);
  const after = await emptyLook();
  check(
    "...the snow and the mark follow the space's new color",
    after.tinted &&
      after.snow !== before.snow &&
      after.mark === 'rgb(142, 143, 184)',
    `${before.snow} -> ${after.snow}, mark ${after.mark}`,
  );
  check(
    '...while the sky and the sunrise stay the same',
    after.sky === before.sky,
  );
  for (const [action, name] of [
    ['settings', 'Settings'],
    ['history', 'History'],
    ['passwords', 'Saved passwords'],
  ]) {
    await ui.evaluate((a) => window.firn.runAction(a), action);
    await wait(700);
    const t = await fl.evaluate(
      () => document.querySelector('.sheet-header h2')?.textContent,
    );
    check(
      `${name} title in Fraunces`,
      t === name && (await fam(fl, '.sheet-header h2')) === 'Fraunces',
      t,
    );
    shot(`brand-${action}`);
    await fl.keyboard.press('Escape');
    await wait(400);
  }
  check(
    'tabs and menus keep the system font',
    (await fam(ui, '.space-header-name')) !== 'Fraunces',
    await fam(ui, '.space-header-name'),
  );
  await ui.evaluate(() => window.firn.updateSettings({ theme: 'dark' }));
  await wait(800);
  await ui.evaluate(() => window.firn.closeOverlay());
  await wait(300);
  shot('brand-empty-dark');
  await ui.evaluate(() => window.firn.runAction('settings'));
  await wait(700);
  shot('brand-settings-dark');
  await fl.keyboard.press('Escape');
  await wait(300);
  await ui.evaluate(() => window.firn.updateSettings({ theme: 'system' }));
  await wait(300);
  console.log(
    `\n${results.filter(Boolean).length}/${results.length} checks passed`,
  );
  await app.close();
})().catch((e) => {
  console.log('TEST ERROR', e.message);
  process.exit(1);
});
