import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import type { ForgeConfig } from '@electron-forge/shared-types';
import { MakerSquirrel } from '@electron-forge/maker-squirrel';
import { MakerZIP } from '@electron-forge/maker-zip';
import { MakerDeb, type MakerDebConfig } from '@electron-forge/maker-deb';
import { MakerRpm, type MakerRpmConfig } from '@electron-forge/maker-rpm';
import { VitePlugin } from '@electron-forge/plugin-vite';
import { FusesPlugin } from '@electron-forge/plugin-fuses';
import { FuseV1Options, FuseVersion } from '@electron/fuses';

// The Liquid Glass icon can only be compiled on macOS 26+ with Xcode 26's
// actool (GitHub's Mac build has both). A Mac without them still builds
// Firn, with just the .icns icon, instead of failing.
const canCompileGlassIcon = () => {
  if (process.platform !== 'darwin' || Number(os.release().split('.')[0]) < 25)
    return false;
  try {
    const version = execFileSync('actool', ['--version'], { encoding: 'utf8' });
    const major = /short-bundle-version<\/key>\s*<string>(\d+)/.exec(version);
    return Number(major?.[1]) >= 26;
  } catch {
    return false;
  }
};

// macOS: sign Firn with David's Apple "Developer ID" certificate and have
// Apple notarize it (check it for malware), so Macs open it like any app
// from the web. Only GitHub's Mac build does this: it puts the certificate
// in a keychain of its own (FIRN_MAC_KEYCHAIN) and the App Store Connect
// key in a file (APPLE_API_KEY_PATH), from the repository's secrets (see
// .github/workflows/build.yml). Without them, Firn still builds, with a
// basic ("ad-hoc") signature instead (see hooks.postPackage).
const macKeychain = process.env.FIRN_MAC_KEYCHAIN;
const appleApiKey = process.env.APPLE_API_KEY_PATH;
const appleApiKeyId = process.env.APPLE_API_KEY_ID;
const appleApiIssuer = process.env.APPLE_API_ISSUER;
const signForMac = process.platform === 'darwin' && Boolean(macKeychain);

// Windows: sign Firn with David's certificate from Azure Artifact Signing,
// so Windows (SmartScreen) knows who made it instead of warning about an
// "unknown publisher". Only GitHub's Windows build does this: it signs in
// to Azure (no stored password: GitHub vouches for the build itself) and
// puts Microsoft's signing add-on (the "dlib") and its settings in files
// (FIRN_WINDOWS_SIGN_DLIB, FIRN_WINDOWS_SIGN_METADATA; see
// .github/workflows/build.yml). It signs Firn.exe and its parts, the
// installer's Update.exe, and Firn Setup.exe. Without them, Firn still
// builds, unsigned. (No quotes in the paths: GitHub's folders have no
// spaces, and the installer's signing passes quotes on as they are.)
const windowsDlib = process.env.FIRN_WINDOWS_SIGN_DLIB;
const windowsMetadata = process.env.FIRN_WINDOWS_SIGN_METADATA;
const windowsSign =
  process.platform === 'win32' && windowsDlib && windowsMetadata
    ? {
        // The Windows SDK's signtool (the add-on needs a recent one).
        signToolPath: process.env.FIRN_WINDOWS_SIGNTOOL,
        signWithParams: `/dlib ${windowsDlib} /dmdf ${windowsMetadata}`,
        timestampServer: 'http://timestamp.acs.microsoft.com',
        // SHA-256 only. (The packager and the installer each bring their
        // own copy of the signing package, with its own type for this.)
        hashes: ['sha256'] as never[],
      }
    : undefined;

// Linux: the .rpm and .deb install Firn as /usr/bin/firn with a firn.desktop
// launcher (Network > Web Browser), in sizes the menus and docks pick from.
// The launcher's "--" keeps a crafted link from posing as a Chromium flag,
// as the Windows handler's does (src/defaultBrowser.ts).
const linux = process.platform === 'linux';
const linuxIcons = {
  ...Object.fromEntries(
    [16, 24, 32, 48, 64, 128, 256, 512].map((size) => [
      `${size}x${size}`,
      `./brand/app-icons/firn-app-icon-windows-glacier-${size}.png`,
    ]),
  ),
  scalable: './brand/svg/firn-app-icon-windows-glacier.svg',
};
const linuxPackage = {
  name: 'firn',
  bin: 'firn',
  productName: 'Firn',
  genericName: 'Web Browser',
  homepage: 'https://firnbrowser.com',
  // A size-to-file map works (each lands in /usr/share/icons/hicolor),
  // though Forge's types only know a single file.
  icon: linuxIcons as unknown as string,
  // WebBrowser is a freedesktop.org sub-category Forge's types don't list.
  categories: ['Network', 'WebBrowser'],
  mimeType: [
    'x-scheme-handler/http',
    'x-scheme-handler/https',
    'text/html',
    'application/xhtml+xml',
    'application/pdf',
    'image/svg+xml',
    'image/webp',
  ],
  desktopTemplate: './assets/linux/firn.desktop.ejs',
};

const config: ForgeConfig = {
  packagerConfig: {
    asar: true,
    // Firn's app icon (Glacier). The packager adds the extension for each
    // system: assets/icon.ico on Windows (the Windows icon from
    // brand/app-icons/firn-app-icon-windows-glacier.ico) and
    // assets/icon.icns on macOS (firn-app-icon-macos-glacier.icns).
    // macOS 26+ also gets the Liquid Glass icon, Firn.icon from Icon
    // Composer: the packager compiles it into Assets.car and sets
    // CFBundleIconName, while older Macs keep using the .icns.
    icon: canCompileGlassIcon()
      ? ['./assets/icon', './brand/icon-composer/Firn.icon']
      : './assets/icon',
    // macOS: Firn is a browser. It opens http and https links and web page
    // files, so it can be chosen as the default browser (src/defaultBrowser.ts).
    protocols: [{ name: 'Web page', schemes: ['http', 'https'] }],
    // Linux: lowercase "firn", as Linux commands are and as the .rpm and
    // .deb expect (Windows and macOS keep Firn.exe and Firn.app). The icon
    // goes beside the app too, for the window (appIcon in src/main.ts).
    ...(linux && {
      executableName: 'firn',
      extraResource: ['./assets/icon.png'],
    }),
    // The texts macOS shows the first time a website asks for the camera,
    // the microphone, or the location (Firn asks for each site as well).
    extendInfo: {
      NSCameraUsageDescription:
        'So websites you allow can use your camera, for video calls for example. Firn asks you first for each site.',
      NSMicrophoneUsageDescription:
        'So websites you allow can use your microphone, for calls for example. Firn asks you first for each site.',
      NSLocationUsageDescription:
        'So websites you allow can see where you are, for maps for example. Firn asks you first for each site.',
      NSLocationWhenInUseUsageDescription:
        'So websites you allow can see where you are, for maps for example. Firn asks you first for each site.',
      CFBundleDocumentTypes: [
        {
          CFBundleTypeName: 'Web page',
          CFBundleTypeRole: 'Viewer',
          LSHandlerRank: 'Alternate',
          LSItemContentTypes: ['public.html', 'public.xhtml'],
        },
        // Offered in "Open With" too (as Chrome is), never taking over.
        {
          CFBundleTypeName: 'PDF document',
          CFBundleTypeRole: 'Viewer',
          LSHandlerRank: 'Alternate',
          LSItemContentTypes: ['com.adobe.pdf'],
        },
        {
          CFBundleTypeName: 'Image',
          CFBundleTypeRole: 'Viewer',
          LSHandlerRank: 'Alternate',
          LSItemContentTypes: ['public.svg-image', 'org.webmproject.webp'],
        },
      ],
    },
    // The signature (with the "hardened runtime" Apple requires) uses
    // osx-sign's defaults, the same permissions Chrome asks for: camera,
    // microphone, location, and the few others web pages can use.
    ...(windowsSign && { windowsSign }),
    ...(signForMac && {
      osxSign: { keychain: macKeychain, continueOnError: false },
      ...(appleApiKey &&
        appleApiKeyId &&
        appleApiIssuer && {
          osxNotarize: { appleApiKey, appleApiKeyId, appleApiIssuer },
        }),
    }),
  },
  rebuildConfig: {},
  hooks: {
    // macOS without the Developer ID certificate (a build on your own Mac,
    // for example): give the finished app a basic ("ad-hoc") signature.
    // Apple Silicon Macs refuse to open an app whose signature doesn't
    // cover the whole app ("damaged"). This isn't Apple's approval: such a
    // copy still needs System Settings > Privacy & Security > Open Anyway
    // once. (Needs macOS: only the Mac build runs it.)
    postPackage: async (_config, { platform, outputPaths }) => {
      if (platform !== 'darwin' || process.platform !== 'darwin') return;
      if (signForMac) return;
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
    // Start menu (src/installer.ts), and opens it. Uninstall from Windows'
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
      ...(windowsSign && { windowsSign }),
    }),
    new MakerZIP({}, ['darwin']),
    // Linux: Fedora's .rpm and Debian/Ubuntu's .deb (npm run make:rpm or
    // make:deb; each needs its own tool: rpm-build, or dpkg and fakeroot).
    // Both also require two libraries Firn's program needs that the
    // defaults leave out: sound (ALSA) and printing (CUPS). The .rpm's own
    // spec fixes two things in the stock one (see the file).
    new MakerRpm({
      options: {
        ...linuxPackage,
        license: 'MPL-2.0',
        requires: ['(alsa-lib or libasound2)', '(cups-libs or libcups2)'],
        specTemplate: './assets/linux/firn.spec.ejs',
      } as MakerRpmConfig['options'],
    }),
    new MakerDeb({
      options: {
        ...linuxPackage,
        section: 'web',
        priority: 'optional',
        depends: ['libasound2t64 | libasound2', 'libcups2t64 | libcups2'],
      } as MakerDebConfig['options'],
    }),
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
      // Don't sign the Apple-silicon half of the Mac app on its own: the Mac
      // build joins it with the Intel half, which must match, and the joined
      // app is signed as a whole afterwards (osxSign, or hooks.postPackage).
      resetAdHocDarwinSignature: false,
      [FuseV1Options.RunAsNode]: false,
      [FuseV1Options.EnableCookieEncryption]: true,
      [FuseV1Options.EnableNodeOptionsEnvironmentVariable]: false,
      [FuseV1Options.EnableNodeCliInspectArguments]: false,
      [FuseV1Options.EnableEmbeddedAsarIntegrityValidation]: true,
      [FuseV1Options.OnlyLoadAppFromAsar]: true,
      // Local (file://) pages get Chrome's limits: no reading other local
      // files. Firn's UI loads from firn://app instead (src/main.ts).
      [FuseV1Options.GrantFileProtocolExtraPrivileges]: false,
    }),
  ],
};

export default config;
