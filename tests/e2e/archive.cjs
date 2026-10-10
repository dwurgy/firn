// Archiving old tabs: everyday tabs not looked at for the chosen number of
// days of use (counted from the days Firn was used, not calendar days)
// tidy themselves away into the Archive; pinned and Basecamp tabs, the tab
// on screen, and each space's most recent tab stay. The Archive (Firn menu,
// command bar, Settings) brings one back, in its space, and survives a
// restart.
const ROOT = require('path').resolve(__dirname, '../..');
const fs = require('fs');
const { execSync } = require('child_process');
const SP = process.env.SP;
const DATA = '/root/.config/Firn';
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
const results = [];
const check = (n, ok, x = '') => {
  results.push(ok);
  console.log(
    `${ok ? 'PASS' : 'FAIL'}  ${n}${x !== '' ? '  (' + x + ')' : ''}`,
  );
};

const DAY = 86_400_000;
const now = Date.now();
const dayOf = (t) => {
  const d = new Date(t);
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
};
const page = (name) => `http://127.0.0.1:8765/${name}.html`;
const tab = (id, spaceId, name, order, lastActiveAt, extra = {}) => ({
  id,
  spaceId,
  url: page(name),
  title: `${name[0].toUpperCase()}${name.slice(1)} site`,
  favicon: '',
  pinned: false,
  order,
  lastActiveAt,
  ...extra,
});

// Firn was used on each of the last 10 days; four tabs were last looked at
// 30 days ago (and one 40).
const session = {
  version: 2,
  spaces: [
    { id: 'sp-a', name: 'Personal', icon: 'home', color: '#7f9cb0', order: 0 },
    { id: 'sp-b', name: 'Work', icon: 'work', color: '#8fae8b', order: 1 },
  ],
  tabs: [
    tab('gray', 'sp-a', 'gray', 0, now - 30 * DAY, { basecamp: true }),
    tab('green', 'sp-a', 'green', 1, now - 30 * DAY, { pinned: true }),
    tab('red', 'sp-a', 'red', 2, now),
    tab('blue', 'sp-a', 'blue', 3, now - 30 * DAY),
    tab('mix', 'sp-b', 'mix', 4, now - 30 * DAY),
    tab('long', 'sp-b', 'long', 5, now - 40 * DAY),
  ],
  splits: [],
  window: {
    id: '1',
    activeSpaceId: 'sp-a',
    activeTabId: 'red',
    sidebarWidth: 260,
    sidebarCollapsed: false,
  },
  recentlyClosed: [],
  daysUsed: Array.from({ length: 10 }, (_, i) => dayOf(now - (i + 1) * DAY)),
};

// Started plainly and checked over CDP: Playwright's launcher waits forever
// on restored tabs that haven't loaded yet.
const launch = async () => {
  const { spawn } = require('child_process');
  const p = spawn(
    require('path').join(ROOT, 'node_modules/electron/dist/electron'),
    ['--no-sandbox', '--remote-debugging-port=9222', '.'],
    { cwd: ROOT, stdio: 'ignore' },
  );
  // The first tidy comes 8 seconds after Firn opens.
  await wait(12000);
  const { evalIn } = await require('./cdp.cjs').cdp();
  return {
    p,
    ui: (expr) => evalIn((u) => u.endsWith(':5173/'), expr),
    fl: (expr) => evalIn((u) => u.includes('view=floating'), expr),
  };
};

(async () => {
  fs.writeFileSync(`${DATA}/session.json`, JSON.stringify(session));
  const settings = JSON.parse(fs.readFileSync(`${DATA}/settings.json`, 'utf8'));
  fs.writeFileSync(
    `${DATA}/settings.json`,
    JSON.stringify({ ...settings, archiveAfter: 7 }),
  );

  let { p, ui, fl } = await launch();
  const rows = () =>
    ui(`[...document.querySelectorAll('.space-tabs .tab, .basecamp-tile')].map(
      (t) => t.getAttribute('data-tip') || t.getAttribute('aria-label') || t.textContent.trim())`);
  const after = (await rows()) ?? [];
  check(
    'an everyday tab unused for 7 days of use is tidied away',
    after.length > 0 && !after.some((r) => /blue/i.test(r)),
    after.join(', '),
  );
  check(
    '...the tab on screen, the pinned tab, and Basecamp stay',
    ['red', 'green', 'gray'].every((n) =>
      after.some((r) => new RegExp(n, 'i').test(r)),
    ),
    after.join(', '),
  );

  await ui(`window.firn.runAction('archive')`);
  await wait(800);
  const listed = async () =>
    (await fl(
      `[...document.querySelectorAll('[data-testid="archived-tab"]')].map((r) => r.textContent)`,
    )) ?? [];
  let archived = await listed();
  check(
    'the Archive lists it, and another space’s older tab, by space',
    archived.length === 2 &&
      archived.some((r) => /blue/i.test(r)) &&
      archived.some((r) => /long/i.test(r)),
    archived.join(' | '),
  );
  check(
    '...but not a space’s most recent tab, though just as old',
    !archived.some((r) => /mix/i.test(r)),
  );
  const groups =
    (await fl(
      `[...document.querySelectorAll('.history-day h3')].map((h) => h.textContent)`,
    )) ?? [];
  check(
    '...grouped by space',
    groups.join(',') === 'Personal,Work',
    groups.join(','),
  );
  execSync(`import -window root -crop 1280x820+0+0 ${SP}/archive-panel.png`);

  await fl(
    `[...document.querySelectorAll('[data-testid="archived-tab"]')].find((r) => /blue/i.test(r.textContent))?.click()`,
  );
  await wait(1500);
  const active = await ui(
    `document.querySelector('.space-tabs .tab.is-active')?.textContent ?? null`,
  );
  const overlay = await fl(`!!document.querySelector('.history-sheet')`);
  check(
    'clicking it brings it back, on screen, and the panel closes',
    /blue/i.test(active ?? '') && !overlay,
    `${active}, panel ${overlay}`,
  );

  await ui(`window.firn.runAction('settings')`);
  await wait(800);
  const setting = await fl(`(() => {
    const row = [...document.querySelectorAll('.settings-row')].find((r) =>
      /Archive tabs you haven't used for/.test(r.textContent));
    return row?.querySelector('.dropdown-button')?.textContent ?? null;
  })()`);
  check(
    'Settings: "Archive tabs you haven’t used for" (here 7 days)',
    setting === '7 days',
    setting,
  );

  // After a restart, the Archive is still there, and today counts as a day
  // of use.
  await wait(2000);
  p.kill();
  await wait(2500);
  const saved = JSON.parse(fs.readFileSync(`${DATA}/session.json`, 'utf8'));
  check(
    'it’s saved: the Archive, and today as a day Firn was used',
    saved.archive?.length === 1 &&
      /long/.test(saved.archive[0].url) &&
      saved.daysUsed?.includes(dayOf(Date.now())),
    JSON.stringify({
      archive: saved.archive?.map((a) => a.url),
      last: saved.daysUsed?.slice(-1),
    }),
  );
  ({ p, ui, fl } = await launch());
  await ui(`window.firn.runAction('archive')`);
  await wait(800);
  archived = await listed();
  check(
    '...and back after a restart',
    archived.length === 1,
    archived.join(' | '),
  );
  p.kill();

  console.log(
    `\n${results.filter(Boolean).length}/${results.length} checks passed`,
  );
})().catch((e) => {
  console.log('FAIL  TEST ERROR', e.message);
  process.exit(1);
});
