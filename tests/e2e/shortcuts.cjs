// Keyboard shortcuts: Settings' page lists every shortcut, grouped, with
// its keys as key caps (Ctrl here; ⌘ on a Mac), and nothing can be
// changed there. The page and Firn's keys share one list
// (src/shortcuts.ts): every key shown on the page, for Windows and Mac,
// is checked to do what the page says, and a few are pressed for real.
const { _electron } = require('./playwright.cjs');
const ROOT = require('path').resolve(__dirname, '../..');
const { execSync, execFileSync } = require('child_process');
const SP = process.env.SP;
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
const results = [];
const check = (n, ok, x = '') => {
  results.push(ok);
  console.log(
    `${ok ? 'PASS' : 'FAIL'}  ${n}${x !== '' ? '  (' + x + ')' : ''}`,
  );
};

// Every key shown on the page, pressed (in pretend), is the shortcut the
// page says, on both kinds of computer.
const roundTrip = execFileSync(
  process.execPath,
  [
    '--experimental-strip-types',
    '--no-warnings',
    '--input-type=module',
    '-e',
    `
    import { matchShortcut, shortcutsToShow } from ${JSON.stringify(`${ROOT}/src/shortcuts.ts`)};
    const out = [];
    for (const platform of ['win32', 'darwin']) {
      const mac = platform === 'darwin';
      for (const { shortcuts } of shortcutsToShow(platform))
        for (const s of shortcuts)
          for (const caps of s.keys) {
            const held = { control: false, meta: false, alt: false, shift: false };
            let key = '';
            for (const cap of caps) {
              if (cap === 'Ctrl' || cap === '⌃') held.control = true;
              else if (cap === '⌘' || cap === 'Win') held.meta = true;
              else if (cap === 'Alt' || cap === '⌥') held.alt = true;
              else if (cap === 'Shift' || cap === '⇧') held.shift = true;
              else key = cap;
            }
            const names = { '←': 'ArrowLeft', '→': 'ArrowRight', Esc: 'Escape' };
            key = names[key] ?? (/^\\d – \\d$/.test(key) ? key[0] : key);
            const code = /^\\d$/.test(key) ? 'Digit' + key : '';
            const hit = matchShortcut({ key, code, ...held }, platform);
            out.push({ platform, id: s.id, caps: caps.join('+'), ok: hit?.id === s.id, got: hit?.id });
          }
    }
    console.log(JSON.stringify(out));
    `,
  ],
  { encoding: 'utf8' },
);
const trips = JSON.parse(roundTrip);
const wrong = trips.filter((t) => !t.ok);
check(
  'every key on the page does what the page says (Windows and Mac)',
  trips.length > 40 && wrong.length === 0,
  `${trips.length} keys; wrong: ${JSON.stringify(wrong)}`,
);

(async () => {
  execSync('rm -f /root/.config/Firn/session.json');
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
  const overlay = () =>
    fl.evaluate(() =>
      document.querySelector('.shortcuts-sheet')
        ? 'shortcuts'
        : document.querySelector('.command-bar, [data-testid="command-input"]')
          ? 'command'
          : document.querySelector('.history-sheet, [aria-label="History"]')
            ? 'history'
            : document.querySelector('[aria-label="Settings"], .settings-sheet')
              ? 'settings'
              : 'none',
    );

  await ui.click('body');
  await key(',');
  await wait(600);
  await fl.click('[data-testid="show-shortcuts"]');
  await wait(600);
  const page = await fl.evaluate(() => {
    const sheet = document.querySelector('.shortcuts-sheet');
    if (!sheet) return null;
    return {
      groups: [...sheet.querySelectorAll('.shortcuts-group h3')].map(
        (h) => h.textContent,
      ),
      rows: sheet.querySelectorAll('.shortcut-row').length,
      caps: [...sheet.querySelectorAll('.key-cap')].map((k) => k.textContent),
      newTab: sheet.querySelector('[data-testid="shortcut-new-tab"]')
        ?.textContent,
      editable: sheet.querySelectorAll('input, select, [contenteditable]')
        .length,
      focused: document.activeElement?.textContent,
    };
  });
  check(
    'Settings > Keyboard shortcuts: the page, grouped',
    page?.groups.join(',') === 'Tabs,Spaces,Pages,Firn' && page.rows > 20,
    JSON.stringify(page && { groups: page.groups, rows: page.rows }),
  );
  check(
    '...keys as key caps, in Windows words (Ctrl, not ⌘)',
    page.caps.includes('Ctrl') &&
      !page.caps.includes('⌘') &&
      /New tab.*Ctrl.*T/.test(page.newTab),
    page.newTab,
  );
  check('...nothing to change there', page.editable === 0);
  check('...and Done takes the keyboard', page.focused === 'Done');
  execSync(
    `import -window root -crop ${o.width}x${o.height}+${o.x}+${o.y} ${SP}/shortcuts-light.png`,
  );
  await fl.evaluate(() =>
    document.querySelector('.shortcuts-body').scrollTo(0, 99999),
  );
  await wait(300);
  execSync(
    `import -window root -crop ${o.width}x${o.height}+${o.x}+${o.y} ${SP}/shortcuts-light-end.png`,
  );
  await fl.keyboard.press('Escape');
  await wait(500);
  check('Esc closes it', (await overlay()) === 'none', await overlay());

  // From the command bar.
  await key('T');
  await wait(500);
  check('Ctrl+T opens the command bar', (await overlay()) === 'command');
  await fl.keyboard.type('shortcuts');
  await wait(400);
  await fl.click('.result-title:has-text("Keyboard shortcuts")');
  await wait(600);
  check(
    'typing "shortcuts" there opens the page',
    (await overlay()) === 'shortcuts',
    await overlay(),
  );
  await fl.keyboard.press('Escape');
  await wait(400);

  // A few for real, through the shared list.
  const sidebarX = () =>
    app.evaluate(({ BrowserWindow }) => {
      const v = BrowserWindow.getAllWindows()[0].contentView.children.find(
        (v) =>
          v.getVisible() &&
          !/5173/.test(v.webContents?.getURL() ?? '') &&
          v.getBounds().width > 300,
      );
      return v ? v.getBounds().x : null;
    });
  const before = await sidebarX();
  await ui.click('body');
  await key('S');
  await wait(700);
  const after = await sidebarX();
  check(
    'Ctrl+S hides the sidebar',
    before > 100 && after < 20,
    `${before} → ${after}`,
  );
  await key('S');
  await wait(700);
  await key('H');
  await wait(600);
  check(
    'Ctrl+H opens history',
    (await overlay()) === 'history',
    await overlay(),
  );
  await fl.keyboard.press('Escape');
  await wait(400);

  // Dark, for a look.
  await app.evaluate(({ nativeTheme }) => (nativeTheme.themeSource = 'dark'));
  await wait(500);
  await ui.click('body');
  await key(',');
  await wait(600);
  await fl.click('[data-testid="show-shortcuts"]');
  await wait(700);
  execSync(
    `import -window root -crop ${o.width}x${o.height}+${o.x}+${o.y} ${SP}/shortcuts-dark.png`,
  );

  console.log(
    `\n${results.filter(Boolean).length}/${results.length} checks passed`,
  );
  await app.close();
})().catch((e) => {
  console.log('FAIL  TEST ERROR', e.message);
  process.exit(1);
});
