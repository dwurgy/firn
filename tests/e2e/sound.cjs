// Sound in tabs: a speaker on any tab playing sound; clicking it mutes the
// tab (and again turns it back on); it goes away once the sound stops.
const { _electron } = require('./playwright.cjs');
const ROOT = require('path').resolve(__dirname, '../..');
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
  for (const page of ['red.html', 'sound.html']) {
    await ui.click('.new-tab');
    await wait(300);
    await fl.keyboard.type(`127.0.0.1:8765/${page}`);
    await fl.keyboard.press('Enter');
    await wait(1500);
  }
  // In the page with the sound (its own page, not Firn's).
  const inSoundPage = (code) =>
    app.evaluate(async ({ webContents }, code) => {
      const web = webContents
        .getAllWebContents()
        .find((w) => w.getURL().endsWith('/sound.html'));
      return web && web.executeJavaScript(code);
    }, code);
  const soundPageMuted = () =>
    app.evaluate(({ webContents }) =>
      webContents
        .getAllWebContents()
        .find((w) => w.getURL().endsWith('/sound.html'))
        .isAudioMuted(),
    );
  // Each tab row: its title and its speaker, if any.
  const rows = () =>
    ui.evaluate(() =>
      [...document.querySelectorAll('.tab[data-kind="everyday"]')].map(
        (row) => {
          const s = row.querySelector('.tab-sound');
          return {
            title: row.querySelector('.tab-title').textContent,
            sound: s ? s.dataset.tip : '',
            named: s ? s.getAttribute('aria-label') : '',
            muted: !!s && s.classList.contains('is-muted'),
          };
        },
      ),
    );
  const soundRow = async () => (await rows()).find((r) => r.title === 'Sound');

  await wait(1500);
  let r = await rows();
  check(
    'a tab playing sound shows a speaker',
    (await soundRow())?.sound === 'Mute tab',
    JSON.stringify(r),
  );
  check(
    '...and a quiet tab shows none',
    r.find((t) => t.title !== 'Sound')?.sound === '',
    JSON.stringify(r),
  );
  execSync(`import -window root -crop 300x340+${o.x}+${o.y} ${SP}/sound.png`);

  // Hovering the row: the speaker steps aside for the close button.
  const soundSel = '.tab:has(.tab-sound)';
  // Like a person: the pointer crosses the row first (the speaker steps
  // aside as it does), then clicks the speaker.
  const clickSpeaker = async () => {
    await ui.hover(`${soundSel} .tab-title`);
    await wait(400);
    await ui.click(`${soundSel} .tab-sound`, { timeout: 5000 });
  };
  await ui.hover(soundSel);
  await wait(400);
  const overlap = await ui.evaluate((sel) => {
    const row = document.querySelector(sel);
    const a = row.querySelector('.tab-sound').getBoundingClientRect();
    const b = row.querySelector('.tab-close').getBoundingClientRect();
    return a.right > b.left;
  }, soundSel);
  check('on hover, the speaker steps aside for the close button', !overlap);
  execSync(
    `import -window root -crop 300x340+${o.x}+${o.y} ${SP}/sound-hover.png`,
  );

  // Work in the other tab, then mute the sound from there.
  await ui.click('.tab:not(:has(.tab-sound))[data-kind="everyday"]', {
    timeout: 5000,
  });
  await wait(400);
  await clickSpeaker();
  await wait(500);
  check(
    'clicking the speaker mutes the tab',
    (await soundRow())?.muted && (await soundPageMuted()),
    JSON.stringify(await soundRow()),
  );
  await ui.mouse.move(600, 600);
  await wait(400);
  execSync(
    `import -window root -crop 300x340+${o.x}+${o.y} ${SP}/sound-muted.png`,
  );
  check(
    '...and it stays, crossed out, to turn the sound back on',
    (await soundRow())?.sound === 'Unmute tab' &&
      (await soundRow())?.named === 'Unmute tab',
    JSON.stringify(await soundRow()),
  );
  const active = await ui.evaluate(
    () =>
      document.querySelector('.tab.is-active .tab-title')?.textContent ?? '',
  );
  check(
    '...without switching to it (or closing it)',
    active !== 'Sound' && (await rows()).length === r.length,
    active,
  );
  await clickSpeaker();
  await wait(500);
  check(
    'clicking it again turns the sound back on',
    (await soundRow())?.sound === 'Mute tab' && !(await soundPageMuted()),
  );

  await inSoundPage('stop()');
  // Chromium waits a moment after the sound stops before saying so.
  await wait(4000);
  check(
    'once the sound stops, the speaker goes away',
    (await soundRow())?.sound === '',
    JSON.stringify(await soundRow()),
  );

  // In Basecamp: a small badge in the tile's corner does the same.
  await ui
    .locator('.tab[data-kind="everyday"]', { hasText: 'Sound' })
    .click({ timeout: 5000 });
  await wait(300);
  await ui.evaluate(() => window.firn.runAction('basecamp'));
  await wait(500);
  await inSoundPage('play()');
  await wait(1500);
  const badge = '.basecamp-tile .tab-sound.is-badge';
  check(
    'a Basecamp tile playing sound shows a small speaker badge',
    (await ui.locator(badge).count()) === 1,
  );
  execSync(
    `import -window root -crop 300x200+${o.x}+${o.y} ${SP}/sound-basecamp.png`,
  );
  await ui.click(badge, { timeout: 5000 });
  await wait(500);
  check(
    '...and clicking it mutes the tab',
    (await soundPageMuted()) &&
      (await ui.locator(`${badge}.is-muted`).count()) === 1,
  );

  console.log(
    `\n${results.filter(Boolean).length}/${results.length} checks passed`,
  );
  await app.close();
})().catch((e) => {
  console.log('TEST ERROR', e.message);
  process.exit(1);
});
