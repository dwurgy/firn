// Automatic updates, on Windows and macOS.
//
// How it works: an installed Firn asks update.electronjs.org (a free
// service run by the Electron project for open-source apps) whether
// Firn's GitHub releases have a newer version. It sends only Firn's
// version and the kind of computer (e.g. "win32-x64" or "darwin-arm64"),
// nothing about the person or what they browse. If there is one, it's
// downloaded quietly in the background (by Squirrel: the installer tool
// behind "Firn Setup.exe" on Windows, and macOS's own updater for apps
// like Firn); the next time Firn is opened, it's the new version. No
// questions, nothing to click.
//
// On a Mac, the download is the release's Mac zip (one app for Apple-chip
// and Intel Macs, "Firn-darwin-universal-<version>.zip": the service hands
// it to both). macOS only accepts it because it's signed with the same
// Developer ID as the Firn already there. Linux packages are updated by
// the system, so Linux is skipped.

import { app, autoUpdater } from 'electron';
import fs from 'node:fs';
import path from 'node:path';

const REPOSITORY = 'dwurgy/firn';
// Wait a little after Firn opens (the installer finishes its own work in
// the first seconds after an install), then look again every few hours.
const FIRST_CHECK_MS = 60 * 1000;
const CHECK_EVERY_MS = 4 * 60 * 60 * 1000;

// Where Firn asks: one address per version and kind of computer.
export const updateFeedUrl = (
  version: string,
  platform: string,
  arch: string,
) =>
  `https://update.electronjs.org/${REPOSITORY}/${platform}-${arch}/${version}`;

// Why this copy can't update itself, or null if it can. On Windows, only a
// copy installed by "Firn Setup.exe" (it has the installer's Update.exe in
// the folder above it, not one unzipped by hand); on a Mac, only one in
// the Applications folder (macOS won't let an app opened straight from
// Downloads replace itself); never a copy run from the source code.
const whyNoUpdates = (): string | null => {
  if (!app.isPackaged) return 'run from the source code';
  if (process.platform === 'win32')
    return fs.existsSync(
      path.join(path.dirname(process.execPath), '..', 'Update.exe'),
    )
      ? null
      : 'not installed by Firn Setup.exe';
  if (process.platform === 'darwin')
    return app.isInApplicationsFolder()
      ? null
      : 'not in the Applications folder';
  return 'updated by the system';
};

export const startUpdates = (log: (message: string) => void) => {
  const why = whyNoUpdates();
  if (why) {
    log(`updates: off (${why})`);
    return;
  }
  const feed = updateFeedUrl(app.getVersion(), process.platform, process.arch);
  autoUpdater.setFeedURL({ url: feed });
  log(`updates: asking ${feed}`);

  let timer: NodeJS.Timeout | undefined;
  const check = () => {
    try {
      autoUpdater.checkForUpdates();
    } catch (error) {
      log(`updates: couldn't check (${String(error)})`);
    }
  };
  // No internet, or GitHub having a bad moment, isn't worth bothering
  // anyone about: Firn simply tries again at the next check.
  autoUpdater.on('error', (error) =>
    log(`updates: couldn't check (${error.message})`),
  );
  autoUpdater.on('update-not-available', () => log('updates: up to date'));
  autoUpdater.on('update-available', () => log('updates: downloading'));
  autoUpdater.on('update-downloaded', (_event, _notes, name) => {
    // It's ready for the next time Firn opens; no need to keep asking.
    log(`updates: ${name || 'new version'} ready for the next start`);
    if (timer) clearInterval(timer);
  });

  setTimeout(() => {
    check();
    timer = setInterval(check, CHECK_EVERY_MS);
  }, FIRST_CHECK_MS);
};
