// What's new: shown once, the first time Firn opens after an update (with
// the notes since the version before), never on a fresh install, and
// anytime from the Firn menu or the command bar.
const { _electron } = require('./playwright.cjs');
const ROOT = require('path').resolve(__dirname, '../..');
const fs = require('fs');
const { execSync } = require('child_process');
const SP = process.env.SP;
const SETTINGS = '/root/.config/Firn/settings.json';
const VERSION = require('../../package.json').version;
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
const results = [];
const check = (n, ok, x = '') => {
  results.push(ok);
  console.log(
    `${ok ? 'PASS' : 'FAIL'}  ${n}${x !== '' ? '  (' + x + ')' : ''}`,
  );
};

// Starts Firn with these settings (and no saved tabs).
const launch = async (settings) => {
  execSync('rm -f /root/.config/Firn/session.json');
  if (settings) fs.writeFileSync(SETTINGS, JSON.stringify(settings));
  else fs.rmSync(SETTINGS, { force: true });
  const app = await _electron.launch({
    args: ['--no-sandbox', '.'],
    cwd: ROOT,
    executablePath: require('path').join(
      ROOT,
      'node_modules/electron/dist/electron',
    ),
  });
  await wait(6500);
  const fl = app.windows().find((w) => w.url().includes('view=floating'));
  const ui = app.windows().find((w) => w.url().endsWith(':5173/'));
  return { app, fl, ui };
};
const shown = (fl) =>
  fl.evaluate(() => {
    const sheet = document.querySelector('.whats-new-sheet');
    if (!sheet) return null;
    return {
      versions: [...sheet.querySelectorAll('.whats-new-version')].map(
        (v) => v.textContent,
      ),
      headline: sheet.querySelector('.whats-new-headline')?.textContent,
      bold: sheet.querySelectorAll('li strong').length,
      focused: document.activeElement?.textContent,
    };
  });
const lastVersion = () =>
  JSON.parse(fs.readFileSync(SETTINGS, 'utf8')).lastVersion;

(async () => {
  // 1. Updated from an older version: the notes since then, newest first.
  let { app, fl, ui } = await launch({ onboarded: true, lastVersion: '0.0.9' });
  let w = await shown(fl);
  check(
    "after an update, What's new opens by itself",
    !!w && w.versions[0] === `Firn ${VERSION}`,
    JSON.stringify(w),
  );
  check(
    '...with every version since the one before, newest first',
    w?.versions.includes('Firn 0.1.0') && w.versions.length >= 2,
    w?.versions.join(', '),
  );
  check(
    '...in plain words: the headline, and the bold names in the lists',
    !!w?.headline && w.bold > 0,
    w?.headline,
  );
  check('..."Got it" takes the keyboard', w?.focused === 'Got it');
  check(
    "...and this version is noted, so it won't show again",
    lastVersion() === VERSION,
  );
  const o = await app.evaluate(({ BrowserWindow }) =>
    BrowserWindow.getAllWindows()[0].getContentBounds(),
  );
  execSync(
    `import -window root -crop ${o.width}x${o.height}+${o.x}+${o.y} ${SP}/whats-new.png`,
  );
  await fl.click('.whats-new-sheet .sheet-button');
  await wait(500);
  check('"Got it" closes it', (await shown(fl)) === null);
  await app.close();

  // 2. The next start: nothing.
  ({ app, fl, ui } = await launch(
    JSON.parse(fs.readFileSync(SETTINGS, 'utf8')),
  ));
  check('the next start is quiet', (await shown(fl)) === null);

  // 3. From the Firn menu (and the command bar): this version's notes.
  await app.evaluate(({ Menu }) => {
    Menu.buildFromTemplate = (t) => {
      globalThis.__menu = t;
      return { popup() {} };
    };
  });
  await ui.click('.sidebar-bottom .firn-menu-button');
  await wait(300);
  await app.evaluate(() =>
    globalThis.__menu.find((i) => i.label === "What's new").click(),
  );
  await wait(500);
  w = await shown(fl);
  check(
    "the Firn menu's What's new shows this version's notes",
    w?.versions.join(',') === `Firn ${VERSION}`,
    JSON.stringify(w?.versions),
  );
  await fl.keyboard.press('Escape');
  await wait(400);
  check('Esc closes it', (await shown(fl)) === null);
  await ui.evaluate(() => window.firn.runAction('whats-new'));
  await wait(500);
  check(
    "...and so does the command bar's",
    (await shown(fl))?.versions[0] === `Firn ${VERSION}`,
  );
  await app.close();

  // 4. Updated from 0.1.0 (which didn't keep track of versions yet).
  ({ app, fl } = await launch({ onboarded: true }));
  w = await shown(fl);
  check(
    "updated from before Firn kept track: just this version's notes",
    w?.versions.join(',') === `Firn ${VERSION}`,
    JSON.stringify(w?.versions),
  );
  await app.close();

  // 5. A fresh install: the welcome, not What's new (and never later).
  ({ app, fl } = await launch(null));
  const welcome = await fl.evaluate(() => !!document.querySelector('.welcome'));
  check(
    'a fresh install gets the welcome instead',
    welcome && (await shown(fl)) === null,
  );
  check('...and its version is noted right away', lastVersion() === VERSION);
  await app.close();

  console.log(
    `\n${results.filter(Boolean).length}/${results.length} checks passed`,
  );
})().catch((e) => {
  console.log('TEST ERROR', e.message);
  process.exit(1);
});
