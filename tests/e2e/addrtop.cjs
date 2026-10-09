const { _electron } = require('./playwright.cjs');
const ROOT = require('path').resolve(__dirname, '../..');
const fs = require('fs');
const { execSync } = require('child_process');
const SP = process.env.SP;
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
const warp = (x, y) => execSync(`python3 ${__dirname}/warp.py ${x} ${y}`);
const results = [];
const check = (n, ok, x = '') => {
  results.push(ok);
  console.log(
    `${ok ? 'PASS' : 'FAIL'}  ${n}${x !== '' ? '  (' + x + ')' : ''}`,
  );
};
(async () => {
  execSync(
    'rm -f /root/.config/Firn/session.json /root/.config/Firn/settings.json',
  );
  require('fs').writeFileSync(
    '/root/.config/Firn/settings.json',
    JSON.stringify({
      onboarded: true,
      // A current install (not just updated, so no What's new).
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
  const tb = app.windows().find((w) => w.url().includes('view=topbar'));
  const o = await app.evaluate(({ BrowserWindow }) =>
    BrowserWindow.getAllWindows()[0].getContentBounds(),
  );
  warp(o.x + 700, o.y + 400);
  const ev = (type, keyCode, modifiers) =>
    app.evaluate(
      ({ webContents }, a) => {
        const w =
          webContents.getFocusedWebContents() ||
          webContents.getAllWebContents()[0];
        w.sendInputEvent(a);
      },
      { type, keyCode, modifiers },
    );
  const key = async (k) => {
    await ev('keyDown', 'Control', ['control']);
    await ev('keyDown', k, ['control']);
    await ev('keyUp', k, ['control']);
    await ev('keyUp', 'Control', []);
  };
  await ui.click('.new-tab');
  await wait(300);
  await fl.keyboard.type('127.0.0.1:8765/red.html');
  await fl.keyboard.press('Enter');
  await wait(1500);
  const layout = () =>
    app.evaluate(({ BrowserWindow }) => {
      const kids = BrowserWindow.getAllWindows()[0].contentView.children;
      const page = kids.find(
        (c) => /8765/.test(c.webContents.getURL()) && c.getVisible(),
      );
      const bar = kids.find((c) =>
        c.webContents.getURL().includes('view=topbar'),
      );
      const peek = kids.find((c) =>
        c.webContents.getURL().includes('view=peek'),
      );
      return {
        page: page?.getBounds(),
        bar: { ...bar.getBounds(), visible: bar.getVisible() },
        peek: { ...peek.getBounds(), visible: peek.getVisible() },
      };
    });
  const sideAddr = () =>
    ui.evaluate(() => {
      const a = document.querySelector('.sidebar .address');
      return a ? getComputedStyle(a).display !== 'none' : false;
    });
  let L = await layout();
  check(
    'by default the address bar is in the sidebar, no top bar',
    (await sideAddr()) && !L.bar.visible && L.page.y === 8,
    JSON.stringify(L),
  );
  // Where the top row's buttons are in the sidebar: they stay there.
  const spots = (sel) =>
    `[...document.querySelectorAll('${sel} button')].map((b) => { const r = b.getBoundingClientRect(); return (b.title || b.dataset.tip || '').split(' ')[0] + '@' + Math.round(r.x) + ',' + Math.round(r.y); }).join(' ')`;
  const rowSpots = await ui.evaluate(spots('.sidebar-top'));
  await ui.evaluate(() => window.firn.updateSettings({ addressBar: 'top' }));
  await wait(60);
  // While the page is still gliding down, the bar is already all there, so
  // the buttons moving up from the sidebar never blink out.
  const early = await layout();
  check(
    'switching: the bar is all there at once, while the page glides down',
    early.bar.visible && early.bar.height === 48 && early.page.y < 48,
    JSON.stringify(early),
  );
  await wait(640);
  L = await layout();
  check(
    '"At the top": the top bar stays, 48px, across the whole window, the page below it',
    L.bar.visible &&
      L.bar.height === 48 &&
      L.bar.x === 0 &&
      L.bar.width === o.width &&
      L.page.y === 48,
    JSON.stringify(L),
  );
  check("...and the sidebar's address bar steps aside", !(await sideAddr()));
  const box = await tb.evaluate(() => {
    const a = document.querySelector('.top-bar-address');
    const r = a.getBoundingClientRect();
    return {
      x: r.x,
      w: r.width,
      y: r.y,
      h: r.height,
      input: a.querySelector('.address-input').value,
      buttons: document.querySelectorAll('.top-bar-window button').length,
      nav: [...document.querySelectorAll('.top-bar-nav button')].map(
        (b) => b.title,
      ),
      navEnd: document.querySelector('.top-bar-nav').getBoundingClientRect()
        .right,
    };
  });
  const pageCenter = L.page.x + L.page.width / 2 - L.bar.x;
  check(
    '...with the same address bar: same width as in the sidebar (244px), centered over the page',
    box.w === 244 &&
      Math.abs(box.x + box.w / 2 - pageCenter) <= 1 &&
      box.input === '127.0.0.1:8765/red.html',
    JSON.stringify({ box, pageCenter }),
  );
  check('...and the window buttons on the right', box.buttons === 3);
  const barSpots = await tb.evaluate(spots('.top-bar-nav'));
  check(
    'the sidebar button, back, forward, and reload stay exactly where they were in the sidebar',
    barSpots === rowSpots && rowSpots.split(' ').length === 4,
    `${rowSpots} | ${barSpots}`,
  );
  check(
    "...and the sidebar's top row moved up into it, on the left: sidebar button, back, forward, reload",
    box.nav.join('|') === 'Hide sidebar (Ctrl+S)|Back|Forward|Reload' &&
      box.navEnd < box.x,
    JSON.stringify(box.nav),
  );
  const side = await ui.evaluate(() => ({
    topRow: !!document.querySelector('.sidebar .sidebar-top'),
    firstTop: Math.round(
      [...document.querySelector('.sidebar').children]
        .map((c) => c.getBoundingClientRect())
        .find((r) => r.height > 0).top,
    ),
  }));
  check(
    'the sidebar has no top row of its own, and starts below the bar, level with the page',
    !side.topRow && side.firstTop === 48,
    JSON.stringify(side),
  );
  execSync(
    `import -window root -crop ${o.width}x${o.height}+${o.x}+${o.y} ${SP}/addr-top.png`,
  );
  // macOS look: the traffic lights stay at the bar's left, the buttons after
  // them, and the address bar never runs into them.
  const mac = await tb.evaluate(async () => {
    document.documentElement.dataset.platform = 'darwin';
    await new Promise((r) => setTimeout(r, 300));
    const nav = document
      .querySelector('.top-bar-nav button')
      .getBoundingClientRect();
    const addr = document
      .querySelector('.top-bar-address')
      .getBoundingClientRect();
    return { navLeft: nav.left, navEnd: nav.right, addrLeft: addr.left };
  });
  execSync(
    `import -window root -crop ${o.width}x60+${o.x}+${o.y} ${SP}/addr-top-mac.png`,
  );
  check(
    'on macOS the buttons sit after the traffic lights, clear of the address bar',
    mac.navLeft === 84 && mac.navEnd + 12 <= mac.addrLeft,
    JSON.stringify(mac),
  );
  await tb.evaluate(() => {
    document.documentElement.dataset.platform = 'linux';
  });
  warp(o.x + 700, o.y + 500);
  await wait(1500);
  check(
    "the bar doesn't go away when the mouse leaves",
    (await layout()).bar.visible,
  );
  await key('L');
  await wait(400);
  const focused = await app.evaluate(
    ({ webContents }) => webContents.getFocusedWebContents()?.getURL() ?? '',
  );
  check(
    'Ctrl+L focuses the address bar at the top',
    focused.includes('view=topbar') &&
      (await tb.evaluate(() =>
        document.activeElement?.classList.contains('address-input'),
      )),
    focused,
  );
  await tb.keyboard.type('127.0.0.1:8765/green.html');
  await tb.keyboard.press('Enter');
  await wait(1500);
  check(
    'typing there goes to the page',
    (await ui.evaluate(
      () => document.querySelector('.tab.is-active .tab-title')?.textContent,
    )) === 'Green site',
  );
  await key('S');
  await wait(600);
  L = await layout();
  const box2 = await tb.evaluate(() => {
    const r = document
      .querySelector('.top-bar-address')
      .getBoundingClientRect();
    return { x: r.x, w: r.width };
  });
  check(
    'hiding the sidebar: the bar stays across the window, the address follows the page',
    L.bar.x === 0 &&
      Math.abs(box2.x + box2.w / 2 - (L.page.x + L.page.width / 2 - L.bar.x)) <=
        1,
    JSON.stringify({ L, box2 }),
  );
  check(
    '...and the buttons still stay exactly where they were',
    (await tb.evaluate(spots('.top-bar-nav'))).replace('Keep', 'Hide') ===
      rowSpots,
  );
  check(
    "...and the bar's sidebar button now offers to bring it back",
    (await tb.evaluate(
      () => document.querySelector('.top-bar-nav button').title,
    )) === 'Keep sidebar open (Ctrl+S)',
  );
  // The left edge, up in the bar (on the way to the traffic lights): no peek.
  warp(o.x + 2, o.y + 20);
  await wait(500);
  check(
    'the left edge up in the bar does not bring the sidebar out',
    !(await layout()).peek.visible,
  );
  warp(o.x + 2, o.y + 300);
  await wait(600);
  L = await layout();
  const pk = app.windows().find((w) => w.url().includes('view=peek'));
  const peekPanel = await pk.evaluate(() => ({
    topRow: !!document.querySelector('.sidebar .sidebar-top'),
    top: Math.round(
      document.querySelector('.sidebar').getBoundingClientRect().top,
    ),
  }));
  check(
    'below the bar, it peeks out under the bar, its panel level with the page, without a top row',
    L.peek.visible &&
      L.peek.y === 40 &&
      L.peek.y + peekPanel.top === L.page.y &&
      !peekPanel.topRow,
    JSON.stringify({ peek: L.peek, peekPanel }),
  );
  execSync(
    `import -window root -crop ${o.width}x${o.height}+${o.x}+${o.y} ${SP}/addr-top-peek.png`,
  );
  // The bar's sidebar button keeps it open.
  await tb.click('.top-bar-nav button');
  await wait(800);
  L = await layout();
  check(
    "...and the bar's sidebar button keeps it open",
    L.page.x === 260 && !L.peek.visible,
    JSON.stringify(L),
  );
  await key('S');
  await wait(600);
  await key('S');
  await wait(600);
  await app.evaluate(({ BrowserWindow }) =>
    BrowserWindow.getAllWindows()[0].setFullScreen(true),
  );
  await wait(1500);
  const fsOn = await app.evaluate(({ BrowserWindow }) =>
    BrowserWindow.getAllWindows()[0].isFullScreen(),
  );
  L = await layout();
  if (fsOn)
    check('fullscreen hides the bar', !L.bar.visible, JSON.stringify(L));
  await app.evaluate(({ BrowserWindow }) =>
    BrowserWindow.getAllWindows()[0].setFullScreen(false),
  );
  await wait(1500);
  L = await layout();
  if (fsOn)
    check(
      '...and it comes back after',
      L.bar.visible && L.page.y === 48,
      JSON.stringify(L),
    );
  else console.log('(fullscreen not available here; skipped)');
  check(
    'the choice is saved',
    JSON.parse(fs.readFileSync('/root/.config/Firn/settings.json', 'utf8'))
      .addressBar === 'top',
  );
  // Settings shows the choice
  await key(',');
  await wait(500);
  const seg = await fl.evaluate(() =>
    [...document.querySelectorAll('.segmented')].map((s) =>
      [...s.querySelectorAll('button')]
        .map((b) => b.textContent + (b.classList.contains('is-on') ? '*' : ''))
        .join('|'),
    ),
  );
  check(
    'settings shows "Address bar: In the sidebar / At the top"',
    seg.includes('In the sidebar|At the top*'),
    seg.join(' ; '),
  );
  await fl.click('.segmented button:has-text("In the sidebar")');
  await wait(800);
  await fl.keyboard.press('Escape');
  await wait(500);
  L = await layout();
  check(
    'back to "In the sidebar": the bar goes, the page moves up, the sidebar address and top row return',
    !L.bar.visible &&
      L.page.y === 8 &&
      (await sideAddr()) &&
      (await ui.evaluate(
        () => !!document.querySelector('.sidebar .sidebar-top'),
      )),
    JSON.stringify(L),
  );
  warp(o.x + 700, o.y + 2);
  await wait(600);
  L = await layout();
  check(
    '...and the top edge still slides the bar down',
    L.bar.visible && L.bar.height === 40 && L.page.y === 40,
    JSON.stringify(L),
  );
  console.log(
    `\n${results.filter(Boolean).length}/${results.length} checks passed`,
  );
  await app.close();
})();
