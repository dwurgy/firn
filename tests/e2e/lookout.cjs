const { _electron } = require('./playwright.cjs');
const ROOT = require('path').resolve(__dirname, '../..');
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
const results = [];
const check = (n, ok, x = '') => {
  results.push(ok);
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${n}${x ? '  (' + x + ')' : ''}`);
};
(async () => {
  require('child_process').execSync(
    'rm -f /root/.config/Firn/session.json /root/.config/firn/session.json',
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
  const find = (v) =>
    app
      .windows()
      .find((w) =>
        v ? w.url().includes('view=' + v) : w.url().endsWith(':5173/'),
      );
  const ui = find(),
    fl = find('floating');
  await ui.click('.new-tab');
  await wait(300);
  await fl.keyboard.type('127.0.0.1:8765/glance.html');
  await fl.keyboard.press('Enter');
  await wait(1500);
  const page = () => app.windows().find((w) => w.url().includes('glance.html'));
  const views = () =>
    app.evaluate(({ BrowserWindow }) =>
      BrowserWindow.getAllWindows()[0]
        .contentView.children.filter(
          (c) => c.webContents && /8765/.test(c.webContents.getURL()),
        )
        .map((c) => ({
          url: c.webContents.getURL().replace(/.*8765\//, ''),
          id: c.webContents.id,
          visible: c.getVisible(),
          b: c.getBounds(),
        })),
    );
  const tabsNow = () =>
    ui.evaluate(() =>
      [...document.querySelectorAll('[data-kind=everyday][data-item]')].map(
        (t) =>
          (t.classList.contains('is-active') ? '*' : '') +
          t.querySelector('.tab-title').textContent,
      ),
    );
  const before = await tabsNow();
  const area = (await views()).find((v) => v.url === 'glance.html').b;
  // 1. Shift+click opens Lookout
  await page().click('#link', { modifiers: ['Shift'] });
  await wait(120);
  const ghost = await fl.evaluate(
    () => !!document.querySelector('.lookout .lookout-panel'),
  );
  check('Shift+click opens Lookout (backdrop and panel appear)', ghost);
  await wait(500);
  let v = await views();
  const g = v.find((x) => x.url === 'two.html');
  check(
    'the link loads in a floating panel over the page',
    g &&
      g.visible &&
      g.b.width < area.width &&
      g.b.x > area.x &&
      g.b.y > area.y,
    JSON.stringify(g && g.b) + ' in ' + JSON.stringify(area),
  );
  check(
    'the tab underneath stays as it was',
    (await tabsNow()).join() === before.join() &&
      v.find((x) => x.url === 'glance.html').visible,
    (await tabsNow()).join(),
  );
  await ui.screenshot({ path: process.env.SP + '/glance-ui.png' });
  require('child_process').execSync(
    `import -window root ${process.env.SP}/glance-open.png`,
  );
  // 2. Esc closes
  const gp = app.windows().find((w) => w.url().includes('two.html'));
  await app.evaluate(({ webContents }) => {
    const w = webContents
      .getAllWebContents()
      .find((c) => c.getURL().includes('two.html'));
    w.sendInputEvent({ type: 'keyDown', keyCode: 'Escape' });
    w.sendInputEvent({ type: 'keyUp', keyCode: 'Escape' });
  });
  await wait(450);
  v = await views();
  check(
    'Esc closes it',
    !v.some((x) => x.url === 'two.html') &&
      !(await fl.evaluate(() => !!document.querySelector('.lookout'))),
    v.map((x) => x.url).join(),
  );
  // 3. click outside closes
  await page().click('#link2', { modifiers: ['Shift'] });
  await wait(600);
  await fl.mouse.click(area.x + 20, area.y + area.height - 10);
  await wait(450);
  v = await views();
  check(
    'clicking outside the panel closes it',
    !v.some((x) => x.url === 'long.html'),
    v.map((x) => x.url).join(),
  );
  // 4. Open as tab keeps the same page
  await page().click('#link2', { modifiers: ['Shift'] });
  await wait(700);
  const lp = app.windows().find((w) => w.url().includes('long.html'));
  await lp.evaluate(() => window.scrollTo(0, 1200));
  await wait(200);
  const gid = (await views()).find((x) => x.url === 'long.html').id;
  await fl.click('.lookout-button[title="Open as tab"]');
  await wait(600);
  v = await views();
  const t = await tabsNow();
  const adopted = v.find((x) => x.url === 'long.html');
  check(
    '"Open as tab" makes it the active tab',
    t[0] === '*Long page' && t.length === before.length + 1,
    t.join(),
  );
  check(
    '...the very same page (scroll position kept), filling the page area',
    adopted &&
      adopted.id === gid &&
      adopted.b.width === area.width &&
      adopted.b.height === area.height &&
      (await lp.evaluate(() => scrollY)) >= 1100,
    JSON.stringify(adopted && adopted.b),
  );
  check(
    '...and Lookout is gone',
    !(await fl.evaluate(() => !!document.querySelector('.lookout'))),
  );
  // 5. ordinary click and popups still work as before
  await ui.locator('[data-item]', { hasText: 'Glance test' }).click();
  await wait(500);
  const winsBefore = await app.evaluate(
    ({ BrowserWindow }) => BrowserWindow.getAllWindows().length,
  );
  await page().click('#popup');
  await wait(1200);
  const winsAfter = await app.evaluate(
    ({ BrowserWindow }) => BrowserWindow.getAllWindows().length,
  );
  check(
    'a real popup (sign-in window) still opens as a window, not Lookout',
    winsAfter === winsBefore + 1 &&
      !(await fl.evaluate(() => !!document.querySelector('.lookout'))),
    `${winsBefore} -> ${winsAfter}`,
  );
  await page().click('#link');
  await wait(800);
  check(
    'an ordinary click still opens the link in the tab',
    (await tabsNow()).some((x) => x === '*Page Two'),
    (await tabsNow()).join(),
  );
  console.log(
    `\n${results.filter(Boolean).length}/${results.length} checks passed`,
  );
  await app.close();
})().catch((e) => {
  console.error('TEST ERROR', e);
  process.exit(1);
});
