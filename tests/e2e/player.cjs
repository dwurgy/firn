// The mini player: shown while a tab that isn't on screen plays sound (in
// any space); pause and play; click it to go to the tab.
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
  const open = async (page) => {
    await ui.click('.new-tab');
    await wait(300);
    await fl.keyboard.type(`127.0.0.1:8765/${page}`);
    await fl.keyboard.press('Enter');
    await wait(1500);
  };
  // In one of the test pages (its own page, not Firn's).
  const inPage = (page, code) =>
    app.evaluate(
      async ({ webContents }, [page, code]) => {
        const web = webContents
          .getAllWebContents()
          .find((w) => w.getURL().endsWith(`/${page}`));
        return web && web.executeJavaScript(code);
      },
      [page, code],
    );
  const pageMuted = (page) =>
    app.evaluate(
      ({ webContents }, page) =>
        webContents
          .getAllWebContents()
          .find((w) => w.getURL().endsWith(`/${page}`))
          .isAudioMuted(),
      page,
    );
  const player = () =>
    ui.evaluate(() => {
      const p = document.querySelector('.mini-player:not(.is-leaving)');
      return p
        ? {
            title: p.querySelector('.mini-player-title').textContent,
            site: p.querySelector('.mini-player-site').textContent,
            button: p.querySelector('.mini-player-toggle').dataset.tip,
          }
        : null;
    });
  const activeTitle = () =>
    ui.evaluate(
      () =>
        document.querySelector('.tab.is-active .tab-title')?.textContent ?? '',
    );
  const shot = (name) =>
    execSync(
      `import -window root -crop 400x${o.height}+${o.x}+${o.y} ${SP}/${name}.png`,
    );

  await open('music.html');
  await wait(1000);
  check(
    'no player for sound in the tab on screen',
    (await player()) === null,
    JSON.stringify(await player()),
  );

  await open('red.html');
  await wait(800);
  let p = await player();
  check(
    'a tab playing sound off screen shows the player',
    p?.title === 'Music' && p.site === '127.0.0.1' && p.button === 'Pause',
    JSON.stringify(p),
  );
  shot('player');

  await ui.click('.mini-player-toggle');
  await wait(800);
  p = await player();
  check(
    'Pause pauses the page (its audio element)',
    (await inPage('music.html', "document.querySelector('audio').paused")) ===
      true && !(await pageMuted('music.html')),
  );
  check(
    '...and the player stays, offering Play',
    p?.button === 'Play',
    JSON.stringify(p),
  );
  // Chromium says the sound stopped only after a moment: still paused.
  await wait(3500);
  check(
    '...even once the sound has stopped',
    (await player())?.button === 'Play',
  );
  shot('player-paused');

  await ui.click('.mini-player-toggle');
  await wait(800);
  check(
    'Play plays it again',
    (await inPage('music.html', "document.querySelector('audio').paused")) ===
      false && (await player())?.button === 'Pause',
  );

  await ui.click('.mini-player-tab');
  await wait(800);
  check(
    'clicking the player goes to the tab, and the player leaves',
    (await activeTitle()) === 'Music' && (await player()) === null,
    await activeTitle(),
  );

  // Sound made by the page's own code (Web Audio) can't be paused: the
  // player mutes it instead.
  await inPage('music.html', "document.querySelector('audio').pause()");
  await open('sound.html');
  await open('green.html');
  await wait(800);
  p = await player();
  check(
    "sound from a page's own code shows the player too",
    p?.title === 'Sound',
    JSON.stringify(p),
  );
  await ui.click('.mini-player-toggle');
  await wait(800);
  check(
    '...and Pause mutes it (nothing to pause)',
    (await pageMuted('sound.html')) && (await player())?.button === 'Play',
  );
  await ui.click('.mini-player-toggle');
  await wait(800);
  check(
    '...and Play turns the sound back on',
    !(await pageMuted('sound.html')) && (await player())?.button === 'Pause',
  );

  // Another space: the player still shows, and takes you back there.
  await ui.evaluate(() => window.firn.newSpace());
  await wait(1200);
  p = await player();
  check(
    'in another space, the player still shows',
    p?.title === 'Sound',
    JSON.stringify(p),
  );
  shot('player-space');
  const spaceBefore = await ui.evaluate(
    () => document.querySelector('.space-header')?.textContent ?? '',
  );
  await ui.click('.mini-player-tab');
  await wait(1200);
  const spaceAfter = await ui.evaluate(
    () => document.querySelector('.space-header')?.textContent ?? '',
  );
  check(
    '...and clicking it goes back to that space and tab',
    spaceAfter !== spaceBefore && (await activeTitle()) === 'Sound',
    `${spaceBefore} -> ${spaceAfter}, ${await activeTitle()}`,
  );

  console.log(
    `\n${results.filter(Boolean).length}/${results.length} checks passed`,
  );
  await app.close();
})().catch((e) => {
  console.log('TEST ERROR', e.message);
  process.exit(1);
});
