// Ad and tracker blocking: on by default, "Allow ads on this site" from the
// page's right-click menu (and back), and the switch in Settings. Uses a
// tiny test list ("/adserver/") instead of downloading the real ones.
const { _electron } = require('./playwright.cjs');
const ROOT = require('path').resolve(__dirname, '../..');
const fs = require('fs');
const { execSync } = require('child_process');
const SETTINGS = '/root/.config/Firn/settings.json';
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
    SETTINGS,
    JSON.stringify({
      onboarded: true,
      lastVersion: require('../../package.json').version,
    }),
  );
  const app = await _electron.launch({
    args: ['--no-sandbox', '.'],
    cwd: ROOT,
    executablePath: require('path').join(
      ROOT,
      'node_modules/electron/dist/electron',
    ),
    env: { ...process.env, FIRN_AD_BLOCK_TEST_LIST: '/adserver/\n' },
  });
  await wait(6000);
  await app.evaluate(({ Menu }) => {
    Menu.buildFromTemplate = (t) => {
      globalThis.__menu = t;
      return { popup() {} };
    };
  });
  const ui = app.windows().find((w) => w.url().endsWith(':5173/'));
  const fl = app.windows().find((w) => w.url().includes('view=floating'));
  await ui.click('.new-tab');
  await wait(300);
  await fl.keyboard.type('127.0.0.1:8765/ads.html');
  await fl.keyboard.press('Enter');
  await wait(1500);
  const pg = () => app.windows().find((w) => w.url().includes('ads.html'));
  const loaded = async () => {
    await wait(600);
    return pg().evaluate(() => ({ ...window.loaded }));
  };
  const menu = async () => {
    await app.evaluate(() => {
      globalThis.__menu = null;
    });
    await pg().click('p', { button: 'right' });
    await wait(400);
    return app.evaluate(() =>
      (globalThis.__menu ?? []).map((i) =>
        i.type === 'separator' ? '—' : i.label,
      ),
    );
  };
  const choose = (label) =>
    app.evaluate(
      (_, label) => globalThis.__menu.find((i) => i.label === label).click(),
      label,
    );
  const saved = () => JSON.parse(fs.readFileSync(SETTINGS, 'utf8'));

  let l = await loaded();
  check(
    'on by default: the ad is blocked, the rest of the page loads',
    l.ad === 'blocked' && l.plain === 'loaded',
    JSON.stringify(l),
  );
  let items = await menu();
  check(
    'the page\'s right-click menu offers "Allow ads on this site"',
    items.join('|') === 'Back|Forward|Reload|—|Allow ads on this site',
    items.join(' | '),
  );
  await choose('Allow ads on this site');
  await wait(1200);
  l = await loaded();
  check(
    '...which reloads the page with its ads',
    l.ad === 'loaded' && l.plain === 'loaded',
    JSON.stringify(l),
  );
  check(
    '...and is remembered for the site',
    saved().adsAllowedSites?.join(',') === '127.0.0.1',
    JSON.stringify(saved().adsAllowedSites),
  );
  const siteButton = await ui.evaluate(
    () => !!document.querySelector('.sidebar .site-button'),
  );
  check("the address bar's site button shows it's allowed", siteButton);
  await app.evaluate(() => {
    globalThis.__menu = null;
  });
  await ui.click('.sidebar .site-button');
  await wait(400);
  const site = await app.evaluate(() =>
    (globalThis.__menu ?? []).map((i) => i.label).filter(Boolean),
  );
  check(
    '...and its menu can block them again',
    site.includes('Ads and trackers'),
    site.join(' | '),
  );
  items = await menu();
  check(
    'the page menu now offers "Block ads on this site"',
    items.at(-1) === 'Block ads on this site',
    items.join(' | '),
  );
  await choose('Block ads on this site');
  await wait(1200);
  l = await loaded();
  check(
    '...which blocks them again',
    l.ad === 'blocked' && !saved().adsAllowedSites?.length,
    JSON.stringify(l),
  );

  // The switch in Settings.
  await ui.evaluate(() => window.firn.updateSettings({ adBlocking: false }));
  await wait(300);
  await pg().reload();
  l = await loaded();
  check(
    'Settings > Block ads and trackers: Off lets everything load',
    l.ad === 'loaded',
    JSON.stringify(l),
  );
  items = await menu();
  check(
    "...and the page menu doesn't offer it then",
    !items.some((i) => i?.includes('ads')),
    items.join(' | '),
  );
  await ui.evaluate(() => window.firn.updateSettings({ adBlocking: true }));
  await wait(300);
  await pg().reload();
  l = await loaded();
  check('...and On blocks again', l.ad === 'blocked', JSON.stringify(l));
  await ui.evaluate(() => window.firn.runAction('settings'));
  await wait(600);
  const row = await fl.evaluate(
    () =>
      [...document.querySelectorAll('.settings-row')]
        .find((r) => r.textContent.includes('Block ads and trackers'))
        ?.querySelector('.is-on')?.textContent ?? null,
  );
  check('Settings shows "Block ads and trackers: On"', row === 'On', row);
  console.log(
    `\n${results.filter(Boolean).length}/${results.length} checks passed`,
  );
  await app.close();
})().catch((e) => {
  console.log('TEST ERROR', e.message);
  process.exit(1);
});
