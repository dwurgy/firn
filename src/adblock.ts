// Built-in ad and tracker blocking (Settings > Block ads and trackers, on
// by default), with Ghostery's open-source blocker (@ghostery/adblocker).
//
// The lists are the standard public ones (EasyList, EasyPrivacy, and uBlock
// Origin's), downloaded from Ghostery's public GitHub repository about once
// a day and kept on this computer, so blocking works offline too. Fetching
// them sends nothing about the person or what they browse; every check
// happens here. Only network blocking: ads and trackers simply never load.
// (Nothing runs inside pages, so a page may show an empty space where an
// ad was.)

import fs from 'node:fs';
import {
  adsAndTrackingLists,
  fetchLists,
  FiltersEngine,
  Request,
} from '@ghostery/adblocker';

// How old the lists may get before Firn fetches fresh ones, and how often
// it looks.
const REFRESH_AFTER_MS = 24 * 60 * 60 * 1000;
const CHECK_EVERY_MS = 60 * 60 * 1000;
// Only what network blocking needs (no hiding of page elements).
const CONFIG = {
  loadCosmeticFilters: false,
  loadGenericCosmeticsFilters: false,
  loadExtendedSelectors: false,
  loadCSPFilters: false,
  loadNetworkFilters: true,
  loadExceptionFilters: true,
  enableCompression: true,
};

// Electron's names for kinds of requests, in the lists' words.
const REQUEST_TYPES: Record<string, string> = {
  mainFrame: 'main_frame',
  subFrame: 'sub_frame',
  xhr: 'xmlhttprequest',
  webSocket: 'websocket',
  cspReport: 'csp_report',
};

type Fetch = typeof fetch;

export class AdBlocker {
  private engine: FiltersEngine | null = null;
  private timer: NodeJS.Timeout | undefined;
  private refreshing = false;

  // `file`: where the lists are kept (prepared, ready to use). `testList`:
  // a list to use instead of downloading any (for the end-to-end checks).
  constructor(
    private file: string,
    private log: (message: string) => void,
    private testList?: string,
    private fetchImpl: Fetch = fetch,
  ) {}

  // Loads the kept lists, and keeps them fresh. Safe to call again.
  start() {
    if (this.engine || this.timer) return;
    if (this.testList !== undefined) {
      this.engine = FiltersEngine.parse(this.testList, CONFIG);
      this.log('ad blocking: using the test list');
      return;
    }
    try {
      this.engine = FiltersEngine.deserialize(fs.readFileSync(this.file));
      this.log('ad blocking: lists loaded');
    } catch {
      // None kept yet (or from an older version of the blocker).
    }
    void this.refreshIfOld();
    this.timer = setInterval(() => void this.refreshIfOld(), CHECK_EVERY_MS);
  }

  // Whether a request a page makes should be stopped. `pageUrl` is the
  // address of the page making it (for "third-party" rules).
  shouldBlock(url: string, type: string, pageUrl: string) {
    if (!this.engine) return false;
    const request = Request.fromRawDetails({
      url,
      sourceUrl: pageUrl,
      type: (REQUEST_TYPES[type] ?? type) as Request['type'],
    });
    return this.engine.match(request).match;
  }

  private async refreshIfOld() {
    if (this.refreshing) return;
    let age = Infinity;
    try {
      age = Date.now() - fs.statSync(this.file).mtimeMs;
    } catch {
      // Never fetched.
    }
    if (this.engine && age < REFRESH_AFTER_MS) return;
    this.refreshing = true;
    try {
      const lists = await fetchLists(this.fetchImpl, adsAndTrackingLists);
      const engine = FiltersEngine.parse(lists.join('\n'), CONFIG);
      this.engine = engine;
      const temp = `${this.file}.tmp`;
      fs.writeFileSync(temp, engine.serialize());
      fs.renameSync(temp, this.file);
      this.log('ad blocking: lists updated');
    } catch (error) {
      // No internet, or GitHub having a bad moment: the kept lists stay in
      // use, and Firn tries again later.
      this.log(`ad blocking: couldn't update the lists (${String(error)})`);
    } finally {
      this.refreshing = false;
    }
  }
}
