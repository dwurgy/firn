const { _electron } = require('./playwright.cjs');
const ROOT = require('path').resolve(__dirname, '../..');
const fs = require('fs');
const http = require('http');
const crypto = require('crypto');
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
const sha = (s) => crypto.createHash('sha256').update(s).digest();
// The stand-in for Google: lists hold the first 4 bytes of these codes.
const DANGER = {
  'scam.test/': 'SOCIAL_ENGINEERING',
  'lookalike.test/': 'SOCIAL_ENGINEERING',
  'malware.test/': 'MALWARE',
};
const LISTED_ONLY = ['innocent.test/']; // the start matches, the full code doesn't
const lists = { SOCIAL_ENGINEERING: [], MALWARE: [], UNWANTED_SOFTWARE: [] };
for (const [e, t] of Object.entries(DANGER))
  lists[t].push(sha(e).subarray(0, 4));
lists.SOCIAL_ENGINEERING.push(sha(LISTED_ONLY[0]).subarray(0, 4));
const sorted = (a) => [...a].sort(Buffer.compare);
const sb = { updates: [], finds: [] };
const sbServer = http
  .createServer((req, res) => {
    let body = '';
    req.on('data', (d) => (body += d));
    req.on('end', () => {
      const json = JSON.parse(body || '{}');
      res.setHeader('Content-Type', 'application/json');
      if (req.url.startsWith('/v4/threatListUpdates:fetch?key=testkey')) {
        sb.updates.push(json);
        res.end(
          JSON.stringify({
            minimumWaitDuration: '1800s',
            listUpdateResponses: json.listUpdateRequests.map((r) => {
              const pre = sorted(lists[r.threatType]);
              return {
                threatType: r.threatType,
                threatEntryType: 'URL',
                platformType: r.platformType,
                responseType: 'FULL_UPDATE',
                additions: pre.length
                  ? [
                      {
                        compressionType: 'RAW',
                        rawHashes: {
                          prefixSize: 4,
                          rawHashes: Buffer.concat(pre).toString('base64'),
                        },
                      },
                    ]
                  : [],
                newClientState: 'state-' + r.threatType,
                checksum: {
                  sha256: crypto
                    .createHash('sha256')
                    .update(Buffer.concat(pre))
                    .digest('base64'),
                },
              };
            }),
          }),
        );
      } else if (req.url.startsWith('/v4/fullHashes:find?key=testkey')) {
        sb.finds.push({ raw: body, json });
        const asked = json.threatInfo.threatEntries.map((e) =>
          Buffer.from(e.hash, 'base64').toString('hex'),
        );
        const matches = Object.entries(DANGER)
          .filter(([e]) =>
            asked.includes(sha(e).subarray(0, 4).toString('hex')),
          )
          .map(([e, t]) => ({
            threatType: t,
            platformType: 'ANY_PLATFORM',
            threatEntryType: 'URL',
            threat: { hash: sha(e).toString('base64') },
            cacheDuration: '300s',
          }));
        res.end(JSON.stringify({ matches, negativeCacheDuration: '300s' }));
      } else {
        res.statusCode = 404;
        res.end('{}');
      }
    });
  })
  .listen(8766);
// The pretend sites (*.test all come here).
const hits = [];
const site = http
  .createServer((req, res) => {
    hits.push(req.headers.host + req.url);
    res.setHeader('Content-Type', 'text/html');
    if (req.headers.host.startsWith('home.test'))
      return res.end(
        '<title>Home</title><a id="l" href="http://lookalike.test/">a link</a>',
      );
    res.end(`<title>${req.headers.host}</title><h1>${req.headers.host}</h1>`);
  })
  .listen(8767);
const hit = (h) => hits.some((x) => x.startsWith(h));

(async () => {
  execSync(
    'rm -rf /root/.config/Firn/session.json /root/.config/Firn/safe-browsing',
  );
  fs.writeFileSync(
    '/root/.config/Firn/settings.json',
    JSON.stringify({ onboarded: true }),
  );
  const app = await _electron.launch({
    args: [
      '--no-sandbox',
      '--host-resolver-rules=MAP *.test 127.0.0.1:8767',
      '.',
    ],
    cwd: ROOT,
    executablePath: require('path').join(
      ROOT,
      'node_modules/electron/dist/electron',
    ),
    env: {
      ...process.env,
      FIRN_SAFE_BROWSING_KEY: 'testkey',
      FIRN_SAFE_BROWSING_API: 'http://127.0.0.1:8766/v4',
    },
  });
  await wait(6000);
  const ui = app.windows().find((w) => w.url().endsWith(':5173/'));
  const fl = app.windows().find((w) => w.url().includes('view=floating'));
  const go = async (u) => {
    await ui.evaluate((u) => window.firn.navigate(u), u);
    await wait(1500);
  };
  const warning = () =>
    fl.evaluate(() => {
      const c = document.querySelector('.danger-card');
      return c ? c.querySelector('h1').textContent : null;
    });
  const tabUrls = () =>
    app.evaluate(({ webContents }) =>
      webContents
        .getAllWebContents()
        .map((w) => w.getURL())
        .filter((u) => u.includes('.test') || u.includes('8765')),
    );
  const bounds = () =>
    app.evaluate(({ BrowserWindow }) => {
      const w = BrowserWindow.getAllWindows()[0];
      return w.contentView.children.map((v) => ({
        b: v.getBounds(),
        url: v.webContents?.getURL?.() ?? '',
        vis: v.getVisible(),
      }));
    });

  check(
    'the lists are downloaded: three, starting fresh',
    sb.updates.length === 1 &&
      sb.updates[0].listUpdateRequests.length === 3 &&
      sb.updates[0].listUpdateRequests.every((r) => r.state === ''),
    JSON.stringify(sb.updates[0]?.listUpdateRequests.map((r) => r.threatType)),
  );
  check(
    '...and kept on this computer',
    fs.existsSync('/root/.config/Firn/safe-browsing/state.json') &&
      fs.statSync('/root/.config/Firn/safe-browsing/SOCIAL_ENGINEERING.bin')
        .size === 12,
    fs.readdirSync('/root/.config/Firn/safe-browsing').join(','),
  );

  await go('http://127.0.0.1:8765/red.html');
  await go('http://safe.test/hello');
  check(
    "an ordinary site opens, checked on this computer only (Google isn't asked)",
    hit('safe.test') && sb.finds.length === 0 && (await warning()) === null,
    `finds=${sb.finds.length}`,
  );

  await go('http://scam.test/');
  check(
    'a scam site: a warning covers the tab',
    (await warning()) === 'This site may be a scam',
    await warning(),
  );
  check('...and the site never loaded', !hit('scam.test'), hits.join(' '));
  const sent = sb.finds[0];
  const entries = sent?.json.threatInfo.threatEntries.map(
    (e) => Buffer.from(e.hash, 'base64').length,
  );
  check(
    'Google was asked with only a 4-byte code, never the address',
    !!sent && entries.every((n) => n === 4) && !/scam|\.test/.test(sent.raw),
    JSON.stringify(entries),
  );
  const text = await fl.evaluate(() =>
    document.querySelector('.danger-card').innerText.replace(/\n+/g, ' | '),
  );
  check(
    'it says which site, in plain words, with "Go back" and "Visit anyway"',
    text.includes('Firn stopped scam.test from opening.') &&
      text.includes('Go back') &&
      text.includes('Visit anyway') &&
      text.includes('Advisory provided by Google'),
    text,
  );
  const bs = await bounds();
  const fb = bs.find((v) => v.url.includes('view=floating')).b;
  const pb = bs.find((v) => v.url.includes('scam.test'))?.b;
  check(
    'the warning sits exactly over the page',
    !!pb && JSON.stringify(fb) === JSON.stringify(pb),
    JSON.stringify({ fb, pb }),
  );
  const o = await app.evaluate(({ BrowserWindow }) =>
    BrowserWindow.getAllWindows()[0].getContentBounds(),
  );
  execSync(
    `import -window root -crop ${o.width}x${o.height}+${o.x}+${o.y} ${SP}/sb-warning.png`,
  );
  await fl.click('.danger-back');
  await wait(1500);
  const nav1 = await ui.evaluate(
    () => document.querySelector('.address-input').value,
  );
  check(
    '"Go back" returns to the page before',
    (await warning()) === null && nav1.includes('safe.test'),
    nav1,
  );

  await go('http://scam.test/');
  check(
    'going there again: warned again (remembered, Google not asked again)',
    (await warning()) === 'This site may be a scam' && sb.finds.length === 1,
    `finds=${sb.finds.length}`,
  );
  // another tab hides it; coming back shows it
  await ui.evaluate(() => window.firn.openUrl('http://safe.test/two'));
  await wait(1500);
  check(
    'switching to another tab puts the warning away',
    (await warning()) === null,
  );
  console.log(
    'tabs:',
    JSON.stringify(
      await ui.evaluate(() =>
        [...document.querySelectorAll('.tab')].map((t) => t.textContent),
      ),
    ),
  );
  await ui.locator('.tab', { hasText: 'scam' }).first().click();
  await wait(1000);
  check(
    '...and it comes back with its tab',
    (await warning()) === 'This site may be a scam',
    await warning(),
  );
  await fl.click('.danger-visit');
  await wait(1500);
  check(
    '"Visit anyway" opens it',
    (await warning()) === null && hit('scam.test'),
    hits.filter((h) => h.includes('scam')).join(),
  );

  await go('http://innocent.test/');
  check(
    "a site whose code only starts the same way opens (Google says it's fine)",
    hit('innocent.test') && (await warning()) === null && sb.finds.length === 2,
    `finds=${sb.finds.length}`,
  );

  const before = await ui.evaluate(
    () => document.querySelectorAll('.tab').length,
  );
  await ui.evaluate(() => window.firn.openUrl('http://malware.test/'));
  await wait(1500);
  check(
    'malware in a new tab: "may harm your computer"',
    (await warning()) === 'This site may harm your computer',
    await warning(),
  );
  await fl.click('.danger-back');
  await wait(1000);
  const after = await ui.evaluate(
    () => document.querySelectorAll('.tab').length,
  );
  check(
    '"Go back" with nowhere to go back to closes the tab',
    after === before && (await warning()) === null,
    `${before} -> ${after}`,
  );

  // Lookout
  await go('http://home.test/');
  const home = app.windows().find((w) => w.url().includes('home.test'));
  await home.click('#l', { modifiers: ['Shift'] });
  await wait(1500);
  check(
    'a dangerous link previewed in Lookout: Lookout closes, the warning shows',
    (await warning()) === 'This site may be a scam' && !hit('lookalike.test'),
    await warning(),
  );
  await fl.click('.danger-back');
  await wait(800);
  const nav2 = await ui.evaluate(
    () => document.querySelector('.address-input').value,
  );
  check(
    '..."Go back" leaves you on your page',
    (await warning()) === null && nav2.includes('home.test'),
    nav2,
  );

  // Settings
  await ui.evaluate(() => window.firn.runAction('settings'));
  await wait(600);
  const row = await fl.evaluate(() =>
    [...document.querySelectorAll('.settings-row')]
      .map((r) => r.innerText.replace(/\n+/g, ' | '))
      .find((t) => t.startsWith('Scam')),
  );
  check(
    'Settings: "Scam and malware warnings" On / Off',
    !!row &&
      row.includes('Checked on this computer, with Google Safe Browsing.') &&
      row.includes('On') &&
      row.includes('Off'),
    row,
  );
  execSync(
    `import -window root -crop ${o.width}x${o.height}+${o.x}+${o.y} ${SP}/sb-settings.png`,
  );
  await fl.evaluate(() =>
    [...document.querySelectorAll('.settings-row')]
      .find((r) => r.innerText.startsWith('Scam'))
      .querySelectorAll('button')[1]
      .click(),
  );
  await wait(400);
  await fl.keyboard.press('Escape');
  await wait(300);
  const n = sb.finds.length;
  await go('http://malware.test/');
  check(
    "turned off: no warning, and Google isn't asked",
    hit('malware.test') && (await warning()) === null && sb.finds.length === n,
  );
  await ui.evaluate(() => window.firn.updateSettings({ safeBrowsing: true }));
  await wait(300);
  console.log(
    `\n${results.filter(Boolean).length}/${results.length} checks passed`,
  );
  await app.close();
  sbServer.close();
  site.close();
})().catch((e) => {
  console.log('TEST ERROR', e.message);
  process.exit(1);
});
