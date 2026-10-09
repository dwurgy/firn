// Building and starting Firn for the demo, with its throwaway profile.
//
// Firn runs from the source code here, the way the end-to-end checks run
// it: a packaged Firn has Electron's debugging hook turned off (see the
// fuses in forge.config.mts), so the demo couldn't drive it.

import { execFileSync, spawn } from 'node:child_process';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import { installDriver } from './director.mjs';
import { launchElectron } from './electron.mjs';

const require = createRequire(import.meta.url);

export const ROOT = path.resolve(import.meta.dirname, '../..');
export const DEMO_DIR = path.join(ROOT, 'demo');
export const PROFILE = path.join(DEMO_DIR, '.profile');
const BUILD = path.join(ROOT, '.vite/build');
const DEV_SERVER = 'http://localhost:5173/';

const wait = (ms) => new Promise((r) => setTimeout(r, ms));

// What every Firn the demo starts gets: demo mode (src/demo.ts) and the
// throwaway profile.
export const demoEnv = (extra = {}) => ({
  ...process.env,
  FIRN_DEMO: '1',
  FIRN_DEMO_PROFILE: PROFILE,
  ...extra,
});

// A Firn that's already open would share the screen (and could sit over
// the window being recorded). Returns a description of it, or ''.
export function runningFirn() {
  const patterns = [
    // An installed Firn (macOS, then Windows/Linux packages).
    'Firn.app/Contents/MacOS/Firn',
    '/Firn$',
    // Firn running from this source folder (npm start).
    `${ROOT}/node_modules/electron`,
    'electron-forge start',
  ];
  for (const pattern of patterns) {
    try {
      const found = execFileSync('pgrep', ['-fl', pattern], {
        encoding: 'utf8',
      }).trim();
      if (found) return found.split('\n')[0];
    } catch {
      // pgrep found nothing.
    }
  }
  return '';
}

// Starts a command in its own process group, so it can be stopped with
// everything it started.
function startGroup(command, args, options) {
  const child = spawn(command, args, {
    cwd: ROOT,
    detached: true,
    stdio: ['ignore', 'pipe', 'pipe'],
    ...options,
  });
  child.stdout.on('data', () => {});
  child.stderr.on('data', () => {});
  return child;
}

async function stopGroup(child) {
  if (!child || child.exitCode !== null) return;
  try {
    process.kill(-child.pid, 'SIGTERM');
  } catch {
    return;
  }
  for (let i = 0; i < 30 && child.exitCode === null; i++) await wait(100);
  try {
    process.kill(-child.pid, 'SIGKILL');
  } catch {
    // Already gone.
  }
}

const builtAfter = (since) =>
  ['main.cjs', 'preload.cjs', 'page-preload.cjs'].every((name) => {
    try {
      return fs.statSync(path.join(BUILD, name)).mtimeMs > since;
    } catch {
      return false;
    }
  });

// Builds Firn's main process (Electron Forge, as `npm start` does), then
// stops the copy Forge opens. That copy is already in demo mode, so it
// only ever sees the throwaway profile.
export async function buildFirn(log) {
  const since = Date.now();
  log('Building Firn…');
  const forge = startGroup('npx', ['electron-forge', 'start'], {
    env: demoEnv(),
  });
  const deadline = Date.now() + 180_000;
  while (!builtAfter(since)) {
    if (forge.exitCode !== null)
      throw new Error('Electron Forge stopped before Firn was built.');
    if (Date.now() > deadline) throw new Error('Building Firn took too long.');
    await wait(250);
  }
  await wait(1500);
  await stopGroup(forge);
}

// Serves Firn's interface (the sidebar and panels) on this computer.
export async function startDevServer(log) {
  try {
    await fetch(DEV_SERVER);
    throw new Error(
      'Something is already using port 5173 (maybe `npm start`). Quit it and run the demo again.',
    );
  } catch (error) {
    if (error instanceof Error && error.message.startsWith('Something'))
      throw error;
  }
  log('Starting Firn’s interface…');
  const vite = startGroup(
    'npx',
    [
      'vite',
      '--config',
      'vite.renderer.config.mts',
      '--port',
      '5173',
      '--strictPort',
    ],
    {},
  );
  for (let i = 0; i < 120; i++) {
    try {
      const response = await fetch(DEV_SERVER);
      if (response.ok) return { stop: () => stopGroup(vite) };
    } catch {
      // Not up yet.
    }
    await wait(250);
  }
  await stopGroup(vite);
  throw new Error('Firn’s interface didn’t start.');
}

export function wipeProfile() {
  fs.rmSync(PROFILE, { recursive: true, force: true, maxRetries: 10 });
  fs.mkdirSync(PROFILE, { recursive: true });
}

// Starts Firn in demo mode and waits for its window and layers.
export async function launchFirn({ glass }) {
  const app = await launchElectron({
    executablePath: require('electron'),
    args: [...(process.platform === 'linux' ? ['--no-sandbox'] : []), '.'],
    cwd: ROOT,
    env: demoEnv(glass ? {} : { FIRN_NO_GLASS: '1' }),
  });
  await installDriver(app);
  const ready = () =>
    app.evaluate(async () => {
      const drive = globalThis.__demoDrive;
      const layers = drive.layers();
      const floating = layers.find((l) => l.url.includes('view=floating'));
      if (!layers.length || !floating) return false;
      const has = (id, selector) =>
        drive.js(
          id,
          `!!document.querySelector(${JSON.stringify(selector)})`,
          2000,
        );
      return (
        (await has(layers[0].id, '[data-testid="new-tab"]')) === true &&
        (await has(floating.id, '#root')) === true
      );
    });
  for (let i = 0; i < 300; i++) {
    if (await ready().catch(() => false)) return { app };
    await wait(100);
  }
  throw new Error('Firn’s window didn’t finish opening.');
}
