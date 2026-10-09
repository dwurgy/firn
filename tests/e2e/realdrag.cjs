// Dragging a tab from the sidebar onto the page opens it in split view:
// over the page, the page makes room on one half and a card shows where
// the tab will open; back over the sidebar, nothing changes; let go, and
// the two are side by side. A Basecamp tile or a pinned tab joins as a
// copy (the tile and the pin stay). A tab opens on a click, not on the
// press, so a drag leaves the page on screen as it is.
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
  });
  await wait(6000);
  const ui = app.windows().find((w) => w.url().endsWith(':5173/'));
  const fl = app.windows().find((w) => w.url().includes('view=floating'));
  const o = await app.evaluate(({ BrowserWindow }) =>
    BrowserWindow.getAllWindows()[0].getContentBounds(),
  );
  const open = async (page) => {
    await ui.click('.new-tab');
    await wait(300);
    await fl.keyboard.type(`127.0.0.1:8765/${page}`);
    await fl.keyboard.press('Enter');
    await wait(1200);
  };
  // The web pages shown, left to right: which page, and where.
  const shownPages = () =>
    app.evaluate(({ BrowserWindow }) => {
      const win = BrowserWindow.getAllWindows()[0];
      return win.contentView.children
        .filter((v) => v.webContents && v.getVisible())
        .map((v) => ({ url: v.webContents.getURL(), ...v.getBounds() }))
        .filter((v) => v.url.includes(':8765/') && v.width > 0)
        .sort((a, b) => a.x - b.x)
        .map((v) => ({
          page: v.url.split('/').pop().replace('.html', ''),
          x: v.x,
          width: v.width,
        }));
    });
  const names = async () => (await shownPages()).map((p) => p.page).join('|');
  const card = () =>
    ui.evaluate(() => {
      const c = document.querySelector('.drop-card');
      if (!c) return null;
      const r = c.getBoundingClientRect();
      const area = document.querySelector('.page-area').getBoundingClientRect();
      return {
        side: r.left - area.left < area.width / 4 ? 'left' : 'right',
        title: c.getAttribute('aria-label') ?? '',
      };
    });
  const active = () =>
    ui.evaluate(
      () =>
        document.querySelector('.space-tabs .tab.is-active')?.textContent ?? '',
    );
  const rowOf = (title) =>
    ui.locator('.space-tabs .tab[data-kind="everyday"]', { hasText: title });
  const center = async (locator) => {
    const b = await locator.boundingBox();
    return { x: b.x + b.width / 2, y: b.y + b.height / 2 };
  };
  // The page area's left and right halves, in the window.
  const area = await ui.evaluate(() => {
    const r = document.querySelector('.page-area').getBoundingClientRect();
    return { left: r.left, right: r.right, middle: (r.top + r.bottom) / 2 };
  });
  const leftHalf = area.left + (area.right - area.left) * 0.25;
  const rightHalf = area.left + (area.right - area.left) * 0.75;

  const xm = (...a) =>
    execSync(`python3 ${__dirname}/xmouse.py ${a.join(' ')}`);
  const realDrag = async (from, to, steps = 20) => {
    xm('move', Math.round(o.x + from.x), Math.round(o.y + from.y));
    await wait(200);
    xm('down');
    await wait(100);
    for (let i = 1; i <= steps; i++) {
      xm(
        'move',
        Math.round(o.x + from.x + ((to.x - from.x) * i) / steps),
        Math.round(o.y + from.y + ((to.y - from.y) * i) / steps),
      );
      await wait(25);
    }
    await wait(600);
  };
  await open('red.html');
  await open('blue.html');
  const red = await center(rowOf('Red'));
  // The carried tab: drawn by the floating layer (in front of the page),
  // with the point it was grabbed at under the pointer.
  const carried = () =>
    fl.evaluate(() => {
      const c = document.querySelector('.carried-tab:not(.is-let-go)');
      if (!c) return null;
      const r = c.getBoundingClientRect();
      return {
        left: Math.round(r.left),
        top: Math.round(r.top),
        title: c.textContent,
      };
    });
  const floatingShown = () =>
    app.evaluate(
      ({ BrowserWindow }) =>
        !!BrowserWindow.getAllWindows()[0].contentView.children.find(
          (v) =>
            v.webContents?.getURL().includes('view=floating') && v.getVisible(),
        ),
    );
  const redBox = await rowOf('Red').boundingBox();
  const grab = { x: red.x - redBox.x, y: red.y - redBox.y };
  // Partway, still over the sidebar: pulled sideways, it's carried.
  const mid = { x: red.x + 90, y: red.y + 6 };
  await realDrag(red, mid, 8);
  let held = await carried();
  check(
    'real mouse: pulled sideways, the tab is carried under the mouse',
    held &&
      /Red/.test(held.title) &&
      Math.abs(held.left - (mid.x - grab.x)) <= 2 &&
      Math.abs(held.top - (mid.y - grab.y)) <= 2,
    JSON.stringify({ held, expect: [mid.x - grab.x, mid.y - grab.y] }),
  );
  check(
    '...and its place in the sidebar waits, faded',
    await ui.evaluate(() => !!document.querySelector('.tab.is-carried-away')),
  );
  execSync(
    `import -window root -crop ${o.width}x${o.height}+${o.x}+${o.y} ${SP}/realdrag-carried.png`,
  );
  for (let i = 1; i <= 12; i++) {
    xm(
      'move',
      Math.round(o.x + mid.x + ((leftHalf - mid.x) * i) / 12),
      Math.round(o.y + mid.y + ((area.middle - mid.y) * i) / 12),
    );
    await wait(25);
  }
  await wait(600);
  held = await carried();
  check(
    'real mouse: over the page, it stays under the mouse, in front',
    held &&
      Math.abs(held.left - (leftHalf - grab.x)) <= 2 &&
      Math.abs(held.top - (area.middle - grab.y)) <= 2 &&
      (await floatingShown()),
    JSON.stringify(held),
  );
  check(
    'real mouse: tab row over the page shows the card',
    !!(await card()),
    JSON.stringify(await card()) + ' ' + JSON.stringify(await shownPages()),
  );
  execSync(
    `import -window root -crop ${o.width}x${o.height}+${o.x}+${o.y} ${SP}/realdrag-over.png`,
  );
  xm('up');
  await wait(1000);
  check(
    '...let go, it fades and the floating layer goes',
    !(await carried()) && !(await floatingShown()),
  );
  check(
    'real mouse: dropped, side by side',
    (await names()) === 'red|blue',
    await names(),
  );
  await open('green.html');
  await ui.evaluate(() => window.firn.runAction('basecamp'));
  await wait(600);
  await open('gray.html');
  const tile = await center(ui.locator('.basecamp-tile').first());
  await realDrag(tile, { x: leftHalf, y: area.middle });
  check(
    'real mouse: tile over the page shows the card',
    !!(await card()),
    JSON.stringify(await card()),
  );
  xm('up');
  await wait(1000);
  console.log(
    `\n${results.filter(Boolean).length}/${results.length} checks passed`,
  );
  await app.close();
})().catch((e) => {
  console.log('TEST ERROR', e.message);
  process.exit(1);
});
