// Saves the session to disk and loads it back, so closing and reopening Firn
// brings everything back as it was. The file lives in Firn's own data folder
// (on Windows: %APPDATA%\Firn\session.json).
//
// Writes go to a temporary file first and are then swapped in, so a crash
// mid-write can never leave a half-written, unreadable session behind.

import fs from 'node:fs';
import path from 'node:path';
import { app } from 'electron';
import type { SavedSession } from './types';

const SESSION_VERSION = 1;

const sessionPath = () => path.join(app.getPath('userData'), 'session.json');

export function loadSession(): SavedSession | null {
  try {
    const data = JSON.parse(fs.readFileSync(sessionPath(), 'utf8'));
    if (data?.version !== SESSION_VERSION || !Array.isArray(data.tabs)) {
      return null;
    }
    return data as SavedSession;
  } catch {
    // No session yet (first run) or an unreadable file: start fresh.
    return null;
  }
}

export function saveSession(session: Omit<SavedSession, 'version'>) {
  const file = sessionPath();
  const temp = `${file}.tmp`;
  try {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(
      temp,
      JSON.stringify({ version: SESSION_VERSION, ...session }),
    );
    fs.renameSync(temp, file);
  } catch (error) {
    console.error('[Firn] Could not save the session:', error);
  }
}

// Collects many changes into one write a moment later, so busy moments
// (pages loading, tabs being dragged) don't write the file over and over.
export class SaveScheduler {
  private timer: ReturnType<typeof setTimeout> | undefined;

  constructor(
    private save: () => void,
    private delayMs = 800,
  ) {}

  schedule() {
    clearTimeout(this.timer);
    this.timer = setTimeout(() => this.flush(), this.delayMs);
  }

  // Saves right away (e.g. when the window closes).
  flush() {
    clearTimeout(this.timer);
    this.timer = undefined;
    this.save();
  }

  cancel() {
    clearTimeout(this.timer);
  }
}
