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
        title: c.querySelector('.drop-card-title')?.textContent ?? '',
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

  await open('red.html');
  await open('blue.html');
  check(
    'blue is on screen to start',
    (await names()) === 'blue',
    await names(),
  );

  // A press alone doesn't switch tabs; the click (letting go) does.
  const red = await center(rowOf('Red'));
  await ui.mouse.move(red.x, red.y);
  await ui.mouse.down();
  await wait(300);
  check(
    'pressing a tab doesn’t open it yet',
    (await names()) === 'blue',
    await names(),
  );
  await ui.mouse.up();
  await wait(400);
  check(
    'letting go (a click) opens it',
    (await names()) === 'red',
    await names(),
  );
  await ui.click('.space-tabs .tab[data-kind="everyday"] >> text=Blue');
  await wait(400);

  // Drag red out over the page's left half.
  await ui.mouse.move(red.x, red.y);
  await ui.mouse.down();
  await ui.mouse.move(red.x + 60, red.y, { steps: 4 });
  await ui.mouse.move(leftHalf, area.middle, { steps: 8 });
  await wait(500);
  let pages = await shownPages();
  let c = await card();
  check(
    'over the left half: a card shows where red would open',
    c?.side === 'left' && /Red/.test(c.title),
    JSON.stringify(c),
  );
  check(
    '...and the page on screen moves over to the right half',
    pages.length === 1 &&
      pages[0].page === 'blue' &&
      pages[0].x > area.left + (area.right - area.left) * 0.4,
    JSON.stringify(pages),
  );
  check('...without opening red', /Blue/.test(await active()), await active());
  execSync(
    `import -window root -crop ${o.width}x${o.height}+${o.x}+${o.y} ${SP}/splitdrag-left.png`,
  );

  await ui.mouse.move(rightHalf, area.middle, { steps: 8 });
  await wait(400);
  c = await card();
  pages = await shownPages();
  check(
    'over the right half: the card and the page swap sides',
    c?.side === 'right' &&
      pages[0]?.page === 'blue' &&
      pages[0].x + pages[0].width < area.left + (area.right - area.left) * 0.6,
    JSON.stringify({ c, pages }),
  );

  await ui.mouse.move(120, area.middle, { steps: 8 });
  await wait(400);
  pages = await shownPages();
  check(
    'back over the sidebar: the page fills its place again',
    !(await card()) &&
      pages.length === 1 &&
      pages[0].width > (area.right - area.left) * 0.9,
    JSON.stringify(pages),
  );

  await ui.mouse.move(rightHalf, area.middle, { steps: 8 });
  await wait(300);
  await ui.mouse.up();
  await wait(800);
  check(
    'letting go: blue and red side by side, red on the right',
    (await names()) === 'blue|red' && !(await card()),
    await names(),
  );
  const row = await ui.evaluate(() =>
    [...document.querySelectorAll('.space-tabs .split-row .tab-title')]
      .map((t) => t.textContent)
      .join('|'),
  );
  check(
    '...one row in the sidebar for both',
    /Blue/.test(row) && /Red/.test(row),
    row,
  );
  execSync(
    `import -window root -crop ${o.width}x${o.height}+${o.x}+${o.y} ${SP}/splitdrag-done.png`,
  );

  // A Basecamp tile: a copy joins, the tile stays.
  await open('green.html');
  await ui.evaluate(() => window.firn.runAction('basecamp'));
  await wait(600);
  await open('gray.html');
  const everydayBefore = await ui
    .locator('.space-tabs .tab[data-kind="everyday"]')
    .count();
  const tile = await center(ui.locator('.basecamp-tile').first());
  await ui.mouse.move(tile.x, tile.y);
  await ui.mouse.down();
  await ui.mouse.move(tile.x + 40, tile.y + 10, { steps: 4 });
  await ui.mouse.move(leftHalf, area.middle, { steps: 8 });
  await wait(400);
  c = await card();
  check(
    'a Basecamp tile can be dragged in too',
    c?.side === 'left' && /Green/.test(c.title),
    JSON.stringify(c),
  );
  await ui.mouse.up();
  await wait(1500);
  check(
    '...a copy of it opens beside the page',
    (await names()) === 'green|gray',
    await names(),
  );
  const tiles = await ui.locator('.basecamp-tile').count();
  const everydayAfter = await ui
    .locator(
      '.space-tabs .split-row, .space-tabs .tab[data-kind="everyday"]:not(.split-row)',
    )
    .count();
  check('...and the tile stays in Basecamp', tiles === 1, `${tiles} tile(s)`);
  check(
    '...the copy sits with the everyday tabs, in the split row',
    /Green/.test(
      await ui.evaluate(() =>
        [...document.querySelectorAll('.space-tabs .split-row')]
          .map((r) => r.textContent)
          .join(' / '),
      ),
    ),
    `${everydayBefore} → ${everydayAfter} rows`,
  );

  // A pinned tab: a copy joins, the pin stays.
  await open('mix.html');
  await ui.evaluate(() => window.firn.runAction('pin'));
  await wait(600);
  await ui.click('.space-tabs .tab[data-kind="everyday"] >> text=Red');
  await wait(600);
  const pin = await center(
    ui.locator('.space-tabs .tab[data-kind="pinned"]').first(),
  );
  await ui.mouse.move(pin.x, pin.y);
  await ui.mouse.down();
  await ui.mouse.move(pin.x + 60, pin.y, { steps: 4 });
  await ui.mouse.move(rightHalf, area.middle, { steps: 8 });
  await wait(400);
  await ui.mouse.up();
  await wait(1500);
  const pinnedNow = await ui
    .locator('.space-tabs .tab[data-kind="pinned"]')
    .count();
  check(
    'a pinned tab dropped on the page: a copy opens beside it',
    (await names()).endsWith('|mix') && pinnedNow === 1,
    `${await names()}, ${pinnedNow} pinned`,
  );

  console.log(
    `\n${results.filter(Boolean).length}/${results.length} checks passed`,
  );
  await app.close();
})().catch((e) => {
  console.log('TEST ERROR', e.message);
  process.exit(1);
});
