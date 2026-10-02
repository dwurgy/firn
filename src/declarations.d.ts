/// <reference types="@electron-forge/plugin-vite/forge-vite-env" />
declare module '*.css';
declare module '*.svg' {
  const url: string;
  export default url;
}

interface Window {
  firn: import('./types').FirnBridge;
}
