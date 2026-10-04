import fs from 'node:fs';
import { defineConfig } from 'vite';

// The key for Google Safe Browsing (scam and malware warnings), built into
// Firn: from FIRN_SAFE_BROWSING_KEY, or from safe-browsing-key.txt next to
// this file. That file is never committed (see .gitignore). Without a key,
// Firn simply doesn't warn.
function safeBrowsingKey() {
  if (process.env.FIRN_SAFE_BROWSING_KEY)
    return process.env.FIRN_SAFE_BROWSING_KEY.trim();
  try {
    return fs.readFileSync('safe-browsing-key.txt', 'utf8').trim();
  } catch {
    return '';
  }
}

// https://vitejs.dev/config
export default defineConfig({
  define: {
    __FIRN_SAFE_BROWSING_KEY__: JSON.stringify(safeBrowsingKey()),
  },
});
