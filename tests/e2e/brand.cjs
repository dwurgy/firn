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
