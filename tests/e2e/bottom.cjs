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
  await app.evaluate(({ Menu }) => {
    Menu.buildFromTemplate = (t) => {
      globalThis.__menu = t;
      return { popup() {} };
    };
  });
  const ui = app.windows().find((w) => w.url().endsWith(':5173/'));
  const o = await app.evaluate(({ BrowserWindow }) =>
    BrowserWindow.getAllWindows()[0].getContentBounds(),
  );
  const shot = (n, h = o.height) =>
    execSync(
      `import -window root -crop 300x${h}+${o.x}+${o.y + o.height - h} ${SP}/${n}.png`,
    );
  // a few spaces
  await ui.evaluate(() => {
    window.firn.newSpace();
  });
  await wait(500);
  await ui.keyboard.press('Escape');
  await ui.evaluate(() => {
    window.firn.newSpace();
  });
  await wait(500);
  await ui.keyboard.press('Escape');
  await wait(500);
  const geo = await ui.evaluate(() => {
    const r = (s) => document.querySelector(s)?.getBoundingClientRect();
    const btn = r('.sidebar-bottom .firn-menu-button'),
      side = r('.sidebar'),
      dots = [...document.querySelectorAll('.space-switcher .space-dot')].map(
        (d) => d.getBoundingClientRect(),
      );
    const mid = (dots[0].left + dots.at(-1).right) / 2;
    return {
      inTop: !!document.querySelector('.sidebar-top .firn-menu-button'),
      btnLeft: btn && Math.round(btn.left - side.left),
      btnBottom: btn && Math.round(side.bottom - btn.bottom),
      dotsMid: Math.round(mid - side.left),
      sideMid: Math.round(side.width / 2),
      sameRow:
        btn &&
        Math.abs(
          (btn.top + btn.bottom) / 2 - (dots[0].top + dots[0].bottom) / 2,
        ) < 2,
    };
  });
  check('the Firn button is no longer in the top row', geo.inTop === false);
  check(
    'it sits at the bottom-left, in line with the space icons',
    geo.btnLeft !== undefined && geo.btnLeft < 20 && geo.sameRow,
    JSON.stringify(geo),
  );
  check(
    'the space icons stay centered in the sidebar',
    Math.abs(geo.dotsMid - geo.sideMid) <= 3,
    `${geo.dotsMid} vs ${geo.sideMid}`,
  );
  await ui.click('.sidebar-bottom .firn-menu-button');
  await wait(300);
  const items = await app.evaluate(() =>
    globalThis.__menu?.map((i) => i.label).filter(Boolean),
  );
  check(
    'clicking it opens the Firn menu',
    items?.includes('Settings') && items.includes('History'),
    items?.join(', '),
  );
  shot('bottom-row', 120);
  execSync(`import -window root -crop 300x90+${o.x}+${o.y} ${SP}/top-row.png`);
  // macOS look: room for the traffic lights
  await ui.evaluate(() => {
    document.documentElement.dataset.platform = 'darwin';
  });
  await wait(300);
  execSync(
    `import -window root -crop 300x90+${o.x}+${o.y} ${SP}/top-row-mac.png`,
  );
  const fits = await ui.evaluate(() => {
    const t = document.querySelector('.sidebar-top');
    return t.scrollWidth <= t.clientWidth;
  });
  check('on macOS the top row fits beside the traffic lights', fits);
  await ui.evaluate(() => window.firn.setSidebarWidth(224));
  await wait(500);
  const fits200 = await ui.evaluate(() => {
    const t = document.querySelector('.sidebar-top');
    return t.scrollWidth <= t.clientWidth;
  });
  check('...even at the narrowest macOS sidebar (224px)', fits200);
  execSync(
    `import -window root -crop 264x90+${o.x}+${o.y} ${SP}/top-row-mac-200.png`,
  );
  shot('bottom-row-200', 120);
  console.log(
    `\n${results.filter(Boolean).length}/${results.length} checks passed`,
  );
  await app.close();
})().catch((e) => {
  console.log('TEST ERROR', e.message);
  process.exit(1);
});
