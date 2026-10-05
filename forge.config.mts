import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import type { ForgeConfig } from '@electron-forge/shared-types';
import { MakerSquirrel } from '@electron-forge/maker-squirrel';
import { MakerZIP } from '@electron-forge/maker-zip';
import { MakerDeb } from '@electron-forge/maker-deb';
import { MakerRpm } from '@electron-forge/maker-rpm';
import { VitePlugin } from '@electron-forge/plugin-vite';
import { FusesPlugin } from '@electron-forge/plugin-fuses';
import { FuseV1Options, FuseVersion } from '@electron/fuses';

const config: ForgeConfig = {
  packagerConfig: {
    asar: true,
    // Firn's app icon (Glacier). The packager adds the extension for each
    // system: assets/icon.ico on Windows (the Windows icon from
    // brand/app-icons/firn-app-icon-windows-glacier.ico) and
    // assets/icon.icns on macOS (firn-app-icon-macos-glacier.icns).
    icon: './assets/icon',
  },
  rebuildConfig: {},
  hooks: {
    // macOS: give the finished app a basic ("ad-hoc") signature. Apple
    // Silicon Macs refuse to open an app whose signature doesn't cover the
    // whole app ("damaged"). This isn't Apple's paid approval: until Firn is
    // notarized, people still confirm it once in System Settings > Privacy
    // & Security > Open Anyway. (Needs macOS: only the Mac build runs it.)
    postPackage: async (_config, { platform, outputPaths }) => {
      if (platform !== 'darwin' || process.platform !== 'darwin') return;
      for (const folder of outputPaths)
        for (const name of fs.readdirSync(folder))
          if (name.endsWith('.app'))
            execFileSync('codesign', [
              '--force',
              '--deep',
              '--sign',
              '-',
              path.join(folder, name),
            ]);
    },
  },
  makers: [
    // The Windows installer: "Firn Setup.exe". No wizard: it installs in a
    // few seconds (showing Firn's mark while it does), adds Firn to the
    // Start menu and the desktop, and opens it. Uninstall from Windows'
    // Settings > Apps. (No .msi: that's for company-wide installs.)
    new MakerSquirrel({
      setupIcon: './assets/icon.ico',
      // The icon Windows' installed-apps list shows: the installer fetches
      // it once, while installing (from Firn's public repository).
      iconUrl:
        'https://raw.githubusercontent.com/dwurgy/firn/main/assets/icon.ico',
      setupExe: 'Firn Setup.exe',
      loadingGif: './assets/installing.gif',
      noMsi: true,
    }),
    new MakerZIP({}, ['darwin']),
    new MakerRpm({}),
    new MakerDeb({}),
  ],
  plugins: [
    new VitePlugin({
      // `build` can specify multiple entry builds, which can be Main process, Preload scripts, Worker process, etc.
      // If you are familiar with Vite configuration, it will look really familiar.
      build: [
        {
          // `entry` is just an alias for `build.lib.entry` in the corresponding file of `config`.
          entry: 'src/main.ts',
          config: 'vite.main.config.mts',
          target: 'main',
        },
        {
          entry: 'src/preload.ts',
          config: 'vite.preload.config.mts',
          target: 'preload',
        },
        {
          // Inside web pages, for saved passwords (src/page-preload.ts).
          entry: 'src/page-preload.ts',
          config: 'vite.preload.config.mts',
          target: 'preload',
        },
      ],
      renderer: [
        {
          name: 'main_window',
          config: 'vite.renderer.config.mts',
        },
      ],
    }),
    // Fuses are used to enable/disable various Electron functionality
    // at package time, before code signing the application
    new FusesPlugin({
      version: FuseVersion.V1,
      [FuseV1Options.RunAsNode]: false,
      [FuseV1Options.EnableCookieEncryption]: true,
      [FuseV1Options.EnableNodeOptionsEnvironmentVariable]: false,
      [FuseV1Options.EnableNodeCliInspectArguments]: false,
      [FuseV1Options.EnableEmbeddedAsarIntegrityValidation]: true,
      [FuseV1Options.OnlyLoadAppFromAsar]: true,
    }),
  ],
};

export default config;
