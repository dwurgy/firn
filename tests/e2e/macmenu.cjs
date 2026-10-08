// The Mac menu bar. Shown here on Linux with FIRN_MAC_MENU=1: its menus,
// the Edit menu's copy and paste, and its choices doing what they say.
const { _electron } = require('./playwright.cjs');
const ROOT = require('path').resolve(__dirname, '../..');
const fs = require('fs');
const { execSync } = require('child_process');
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
    env: { ...process.env, FIRN_MAC_MENU: '1' },
    executablePath: require('path').join(
      ROOT,
      'node_modules/electron/dist/electron',
    ),
  });
  await wait(6000);
  const fl = app.windows().find((w) => w.url().includes('view=floating'));
  const menus = await app.evaluate(({ Menu }) =>
    Menu.getApplicationMenu().items.map((m) => ({
      label: m.label,
      items: (m.submenu?.items ?? []).map((i) =>
        i.type === 'separator' ? '—' : i.label || i.role,
      ),
    })),
  );
  const labels = menus.map((m) => m.label).join('|');
  check(
    'the menus: Firn, File, Edit, View, Window, Help',
    labels === 'Firn|File|Edit|View|Window|Help',
    labels,
  );
  const firn = menus[0]?.items.join('|') ?? '';
  check(
    'the Firn menu starts with About and Settings…, ends with Quit',
    firn.startsWith('About Firn|—|Settings…') && firn.endsWith('Quit Firn'),
    firn,
  );
  const edit = menus[2]?.items.join('|') ?? '';
  check(
    'the Edit menu has undo, cut, copy, paste and select all',
    ['Undo', 'Cut', 'Copy', 'Paste', 'Select All'].every((l) =>
      edit.includes(l),
    ),
    edit,
  );
  const file = menus[1]?.items.join('|') ?? '';
  check(
    'the File menu is short: new tab, reopen, close tab',
    file === 'New Tab|Reopen Closed Tab|—|Close Tab',
    file,
  );

  const item = (menu, label) =>
    app.evaluate(
      ({ Menu }, [menu, label]) => {
        const i = Menu.getApplicationMenu()
          .items.find((m) => m.label === menu)
          .submenu.items.find((i) => i.label === label);
        return { role: i.role, accelerator: i.accelerator };
      },
      [menu, label],
    );
  const hide = await item('Firn', 'Hide Firn');
  check(
    "Hide Firn is the Mac's own Hide (Cmd+H)",
    hide.role === 'hide',
    JSON.stringify(hide),
  );
  const history = await item('View', 'History');
  check(
    'History is Cmd+Y, like Safari and Chrome',
    history.accelerator === 'Cmd+Y',
    JSON.stringify(history),
  );

  const click = (menu, label) =>
    app.evaluate(
      ({ Menu }, [menu, label]) =>
        Menu.getApplicationMenu()
          .items.find((m) => m.label === menu)
          .submenu.items.find((i) => i.label === label)
          .click(),
      [menu, label],
    );
  await click('Firn', 'Settings…');
  await wait(800);
  check(
    'Firn > Settings… opens Settings',
    await fl.evaluate(() => !!document.querySelector('.settings-sheet')),
  );

  const ui = app.windows().find((w) => w.url().endsWith(':5173/'));
  const tabCount = () =>
    ui.evaluate(() => document.querySelectorAll('.tab').length);
  const before = await tabCount();
  await click('Help', 'Firn Website');
  await wait(1500);
  check('Help > Firn Website opens a new tab', (await tabCount()) > before);

  await app.close();
  process.exit(results.every(Boolean) ? 0 : 1);
})().catch((e) => {
  console.log('FAIL  crashed: ' + e.message);
  process.exit(1);
});
