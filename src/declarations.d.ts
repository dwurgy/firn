/// <reference types="@electron-forge/plugin-vite/forge-vite-env" />
declare module '*.css';
// The key for Google Safe Browsing, added when Firn is built (see
// vite.main.config.mts); empty if none was given.
declare const __FIRN_SAFE_BROWSING_KEY__: string;
declare module '*.svg' {
  const url: string;
  export default url;
}

interface Window {
  firn: import('./types').FirnBridge;
}
