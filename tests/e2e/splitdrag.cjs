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

  // Swinging back to the left half: the page glides across, through
  // places in between, rather than jumping.
  await app.evaluate(({ BrowserWindow }) => {
    const win = BrowserWindow.getAllWindows()[0];
    const xs = (globalThis.__glideXs = []);
    const timer = setInterval(() => {
      const view = win.contentView.children.find(
        (v) => v.webContents && v.webContents.getURL().includes('blue.html'),
      );
      if (view) xs.push(view.getBounds().x);
    }, 10);
    setTimeout(() => clearInterval(timer), 900);
  });
  await ui.mouse.move(leftHalf, area.middle, { steps: 4 });
  await wait(1000);
  const xs = await app.evaluate(() => globalThis.__glideXs);
  const from = xs[0];
  const to = xs[xs.length - 1];
  const between = new Set(
    xs.filter((x) => x !== from && x !== to && (x - from) * (x - to) < 0),
  );
  check(
    '...and the page glides between the halves (no jump)',
    to > from && between.size >= 3,
    `${from} → ${to}, ${between.size} places in between`,
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

  // With the sidebar hidden: dragging out of the peeking sidebar. It stays
  // out while the button is held, steps aside over the page (so the page
  // and the card can be seen), comes back over it, and goes once the tab
  // is dropped.
  const warp = (x, y) =>
    execSync(`python3 ${__dirname}/warp.py ${Math.round(x)} ${Math.round(y)}`);
  await open('two.html');
  await open('styled.html');
  await ui.evaluate(() => window.firn.toggleSidebar());
  await wait(800);
  const pk = app.windows().find((w) => w.url().includes('view=peek'));
  const peekOut = () =>
    pk.evaluate(() =>
      document.querySelector('.peek').classList.contains('is-shown'),
    );
  const peekLayer = () =>
    app.evaluate(
      ({ BrowserWindow }) =>
        !!BrowserWindow.getAllWindows()[0].contentView.children.find(
          (v) =>
            v.webContents?.getURL().includes('view=peek') && v.getVisible(),
        ),
    );
  const wide = await ui.evaluate(() => {
    const r = document.querySelector('.page-area').getBoundingClientRect();
    return { left: r.left, right: r.right, middle: (r.top + r.bottom) / 2 };
  });
  const wideRight = wide.left + (wide.right - wide.left) * 0.75;
  warp(o.x + 12, o.y + wide.middle);
  await wait(600);
  check('the sidebar hidden, it peeks', await peekOut());
  const two = await center(
    pk.locator('.space-tabs .tab[data-kind="everyday"]', {
      hasText: 'Page Two',
    }),
  );
  // The peek's layer is only as wide as the sidebar, and the test's mouse
  // can't go past its edge (a real one keeps reporting to it while the
  // button is held), so moves beyond it are sent as the page's own
  // pointer events.
  const pkMove = async (x, y) => {
    for (let i = 1; i <= 8; i++)
      await pk.evaluate(
        ([x, y]) =>
          dispatchEvent(
            new PointerEvent('pointermove', {
              clientX: x,
              clientY: y,
              pointerId: 1,
              buttons: 1,
            }),
          ),
        [two.x + ((x - two.x) * i) / 8, y],
      );
  };
  warp(o.x + two.x, o.y + two.y);
  await pk.mouse.move(two.x, two.y);
  await pk.mouse.down();
  await pk.mouse.move(two.x + 60, two.y, { steps: 4 });
  // Out over the page (the real pointer too, which the peek watches).
  warp(o.x + wideRight, o.y + wide.middle);
  await pkMove(wideRight, wide.middle);
  await wait(700);
  c = await card();
  check(
    'dragged out of the peeking sidebar: the card shows over the page',
    c?.side === 'right' && /Page Two/.test(c.title),
    JSON.stringify(c),
  );
  check(
    '...and the peeking sidebar steps aside, but stays for the drag',
    !(await peekOut()) && (await peekLayer()),
  );
  warp(o.x + 120, o.y + wide.middle);
  await pkMove(120, wide.middle);
  await wait(500);
  check(
    'back over it: it comes back, and the card goes',
    (await peekOut()) && !(await card()),
    `out ${await peekOut()}, card ${JSON.stringify(await card())}, layer ${await peekLayer()}`,
  );
  warp(o.x + wideRight, o.y + wide.middle);
  await pkMove(wideRight, wide.middle);
  await wait(500);
  await pk.evaluate(() =>
    dispatchEvent(new PointerEvent('pointerup', { pointerId: 1 })),
  );
  await pk.mouse.up();
  await wait(1000);
  check(
    'letting go: the two side by side',
    (await names()) === 'styled|two',
    await names(),
  );
  check(
    '...and the peeking sidebar goes',
    !(await peekOut()) && !(await peekLayer()),
  );
  execSync(
    `import -window root -crop ${o.width}x${o.height}+${o.x}+${o.y} ${SP}/splitdrag-peek.png`,
  );

  console.log(
    `\n${results.filter(Boolean).length}/${results.length} checks passed`,
  );
  await app.close();
})().catch((e) => {
  console.log('TEST ERROR', e.message);
  process.exit(1);
});
