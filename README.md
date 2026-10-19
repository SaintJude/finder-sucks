# Finder Sucks

A dual-pane file manager for macOS 14 (Sonoma) or later, on Apple silicon and Intel Macs.

## Installing on a Mac

1. Open `FinderSucks-<version>.dmg` and drag **Finder Sucks** onto **Applications**.
2. The first time you open it, macOS will say it can't verify the developer, because the app
   isn't notarized by Apple. To allow it:
   - Try to open the app once, then click **Done** on the warning.
   - Go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway**
     next to the message about Finder Sucks.
   - Or, in Terminal: `xattr -dr com.apple.quarantine "/Applications/Finder Sucks.app"`
3. Optional: to stop the per-folder permission prompts (Desktop, Documents, Downloads, and
   so on), add the app under **System Settings → Privacy & Security → Full Disk Access**.

## Building

Requires Xcode.

```sh
./scripts/install.sh     # build and install into /Applications on this Mac
./scripts/build-app.sh   # build only: build/Finder Sucks.app and build/FinderSucks-<version>.dmg
```

Set `VERSION=0.2.0` to stamp a version number on the build. `swift run` launches a debug
build without making an app bundle.

To regenerate the icon (`Resources/AppIcon.icns`), run `swift scripts/make-icon.swift`.

### Signed and notarized builds

With an Apple Developer account ($99/year), other Macs open the app with no warning:

```sh
xcrun notarytool store-credentials finder-sucks   # one time: Apple ID + app-specific password
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE=finder-sucks ./scripts/build-app.sh
```
