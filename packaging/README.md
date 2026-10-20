# Packaging Firn for Linux

Firn's Fedora and Debian packages come from Electron Forge itself; Arch and
Void have recipes of their own here.

## Fedora, Nobara, and openSUSE (.rpm)

```bash
sudo dnf install rpm-build
npm ci
npm run make:rpm
sudo dnf install ./out/make/rpm/x64/firn-*.rpm
```

The spec is `assets/linux/firn.spec.ejs`: the stock one from
electron-installer-redhat, changed so it builds with RPM 4.20+ and keeps
`chrome-sandbox` setuid.

## Debian and Ubuntu (.deb)

```bash
sudo apt install dpkg fakeroot   # on Fedora: sudo dnf install dpkg
npm ci
npm run make:deb
sudo apt install ./out/make/deb/x64/firn_*.deb
```

## Arch Linux (AUR)

`arch/PKGBUILD` builds from a release tag and installs to `/opt/firn`, with
the Electron Forge builds (so Firn's fuses, like cookie encryption, stay on).

```bash
cd packaging/arch
updpkgsums
makepkg -si
makepkg --printsrcinfo > .SRCINFO   # before publishing to the AUR
```

## Void Linux

`void/srcpkgs/firn` is an xbps-src template (glibc only: Electron has no musl
build). Copy it into a void-packages checkout:

```bash
cp -r packaging/void/srcpkgs/firn ~/void-packages/srcpkgs/
cd ~/void-packages
xgensum -i firn
./xbps-src pkg firn
sudo xbps-install --repository hostdir/binpkgs firn
```

## Default browser

Each package installs `firn.desktop`. To make Firn the default browser:

```bash
xdg-settings set default-web-browser firn.desktop
```
