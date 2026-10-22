// No more automatic updates: this is Firn's last version on Electron, and
// the repository's releases will become the Mac app's, so no copy may ask
// for them. The code has no updater left (Electron's autoUpdater or the
// update.electronjs.org address), and Firn logs no update activity while
// still opening normally. Firn is started directly (not through
// Playwright) so its log can be read from the very first line.
const path = require('path');
const fs = require('fs');
const { execSync, spawn } = require('child_process');
const ROOT = path.resolve(__dirname, '../..');
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
const results = [];
const check = (n, ok, x = '') => {
  results.push(ok);
  console.log(
    `${ok ? 'PASS' : 'FAIL'}  ${n}${x !== '' ? '  (' + x + ')' : ''}`,
  );
};
// Every file under src/, for words that mean an update check.
const sources = (dir) =>
  fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    const p = path.join(dir, e.name);
    return e.isDirectory() ? sources(p) : [p];
  });
(async () => {
  const updater = sources(path.join(ROOT, 'src')).filter((f) =>
    /autoUpdater|update\.electronjs|electron-updater|setFeedURL/.test(
      fs.readFileSync(f, 'utf8'),
    ),
  );
  check(
    'no updater left in the code',
    updater.length === 0,
    updater.map((f) => path.relative(ROOT, f)).join(', '),
  );
  execSync('rm -f /root/.config/Firn/session.json');
  fs.writeFileSync(
    '/root/.config/Firn/settings.json',
    JSON.stringify({
      onboarded: true,
      // A current install (not just updated, so no What's new).
      lastVersion: require('../../package.json').version,
      farewellSeen: true,
    }),
  );
  const firn = spawn(
    path.join(ROOT, 'node_modules/electron/dist/electron'),
    ['--no-sandbox', '.'],
    { cwd: ROOT, env: { ...process.env, FIRN_DEBUG: '1' } },
  );
  let out = '';
  firn.stdout.on('data', (d) => (out += d));
  await wait(12000);
  check('Firn does no update check', !out.includes('updates:'));
  check('Firn still opens normally', out.includes('started'));
  firn.kill();
  process.exit(results.every(Boolean) ? 0 : 1);
})().catch((e) => {
  console.log('FAIL  crashed: ' + e.message);
  process.exit(1);
});
