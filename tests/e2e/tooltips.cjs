// Hover labels: Firn's own (not the system's tooltips), after a short
// pause, inside the sidebar, and only where they add something (not a tab
// name that's already fully shown).
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
  const top = app.windows().find((w) => w.url().includes('view=topbar'));
  const o = await app.evaluate(({ BrowserWindow }) =>
    BrowserWindow.getAllWindows()[0].getContentBounds(),
  );
  for (const page of ['red.html', 'longtitle.html']) {
    await ui.click('.new-tab');
    await wait(300);
    await fl.keyboard.type(`127.0.0.1:8765/${page}`);
    await fl.keyboard.press('Enter');
    await wait(1200);
  }
  const tip = () =>
    ui.evaluate(() => {
      const t = document.querySelector('.firn-tip');
      const r = t.getBoundingClientRect();
      const s = document.querySelector('.sidebar').getBoundingClientRect();
      return {
        shown: t.classList.contains('is-shown'),
        text: t.textContent,
        inside: r.left >= s.left && r.right <= s.right,
        lines: Math.round((r.height - 10) / 16),
        below: r.top,
      };
    });

  const titles = await Promise.all(
    [ui, fl].map((w) =>
      w.evaluate(() => document.querySelectorAll('[title]').length),
    ),
  );
  check(
    "no system tooltips in the sidebar or panels (each label is Firn's)",
    titles.every((n) => n === 0),
    titles.join(','),
  );
  const named = await ui.evaluate(() => {
    const b = document.querySelector('.space-add');
    return b && `${b.dataset.tip}|${b.getAttribute('aria-label')}`;
  });
  check(
    '...and icon buttons keep their name for screen readers',
    named === 'New space|New space',
    named,
  );

  await ui.hover('.space-add');
  await wait(150);
  const early = await tip();
  await wait(600);
  const t1 = await tip();
  check(
    'hovering a button: its label fades in after a short pause',
    !early.shown && t1.shown && t1.text === 'New space' && t1.inside,
    JSON.stringify([early.shown, t1]),
  );
  execSync(
    `import -window root -crop 300x200+${o.x}+${o.y + o.height - 200} ${SP}/tooltip-button.png`,
  );
  await ui.mouse.move(500, 400);
  await wait(300);
  check('...and goes away when the pointer leaves', !(await tip()).shown);

  await ui.hover('.space-tabs .tab:has-text("Red site")');
  await wait(800);
  check(
    'a tab whose name is fully shown: no label repeating it',
    !(await tip()).shown,
  );
  await ui.hover('.space-tabs .tab:not(:has-text("Red site"))');
  await wait(800);
  const t2 = await tip();
  check(
    'a tab whose name is cut off: the full name, wrapped inside the sidebar',
    t2.shown && t2.text.length > 60 && t2.inside && t2.lines <= 2,
    JSON.stringify(t2),
  );
  execSync(
    `import -window root -crop 300x220+${o.x}+${o.y + Math.round(t2.below) - 80} ${SP}/tooltip-tab.png`,
  );
  await ui.mouse.down();
  await wait(100);
  check('pressing puts the label away', !(await tip()).shown);
  await ui.mouse.up();

  const native = await top.evaluate(
    () => document.querySelectorAll('[title]').length,
  );
  check(
    "the slim top bar keeps the system's tooltips (no room for Firn's)",
    native > 0,
    native,
  );
  console.log(
    `\n${results.filter(Boolean).length}/${results.length} checks passed`,
  );
  await app.close();
})().catch((e) => {
  console.log('TEST ERROR', e.message);
  process.exit(1);
});
