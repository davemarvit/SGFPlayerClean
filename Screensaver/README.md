# Quiet Go — integrated SGF Player screensaver

Quiet Go is built and bundled with the main application. Open the app's gear
button, then **Screensaver**, to choose a folder, turn playback on/off, refresh
the library, preview it, or open macOS Screen Saver settings. Select **Quiet Go**
in macOS once to use it while idle. The in-app toggle controls Quiet Go playback;
it does not change the Mac's idle timeout, lock policy, wallpaper or other savers.

A game advances approximately every 1.5 seconds. Its final position remains for
seven seconds, then another game plays. A shuffled queue includes every game
before reshuffling and avoids immediate repeats across cycles (a one-game library
necessarily repeats). Playback continues indefinitely. It is silent, uses the
normal SGF parser/replay engine, and handles setup, captures, passes and main-line
variations. The 2D renderer includes separate soft stone shadows.

Two wooden capture lids sit to the right of the board: captured black stones above,
captured white stones below. Their piles and badges read the replay engine's current
capture totals and clear with each new game. They reuse the main app's seeded pile
layout and stone/lid assets: positions remain stable as captures accumulate, while
different lids and games get different arrangements. This uses cached settled
positions rather than a continuously running physics simulation. The complete
board/lid layout fits small previews and tall or wide displays.

The first frame stays quiet while macOS starts animation and the saver checks its
configuration. A choose-folder message is shown only after an actual missing or
invalid configuration is detected. Disabled playback and unreadable libraries
still report their real state.

The builder packages the existing Go-board app icon as `QuietGo.icns` and creates
`thumbnail.png` (90×58) and `thumbnail@2x.png` (180×116), matching the native resources
in Apple's installed Random.saver. These supply System Settings' thumbnail and
the saver/preview application's icon. Close and reopen System Settings after an
update if its gallery is still cached.

## Folder and settings storage

The selected folder is independent of the app's Review library. Subfolders are
included; hidden files, packages and symlinked files are excluded. Empty,
unsupported, and >2 MB SGFs are skipped and counted in the UI. There is no 80-game
limit. Originals are never modified. Folder selection creates validated playback
copies in `~/Library/Application Support/SGFPlayerScreensaver/Libraries/<UUID>`.
Configuration is in that directory's parent, `configuration.json`.

Copies let the screensaver work with the app closed, even when the source folder
is on an unavailable volume or in a location protected by macOS privacy rules.
They refresh when the main app opens and when Refresh is pressed. Newly added
source games become available after that refresh; this is not a live folder watch.

A complete generation is published atomically; the previous generation is kept
until the following successful refresh. Empty/unreadable replacement folders and
copy failures leave the previous configuration/library intact. Import excludes
its own playback cache to prevent recursive copying. The current screensaver
notices enablement/folder-generation changes within approximately one second.

The screensaver resolves the real user's home through the POSIX account database
(`getpwuid_r`); even `NSHomeDirectoryForUser` redirects into the system host's
container. On the tested macOS 15.7.3 host, legacyScreenSaver has a read-only
filesystem exception for `/`; it can read this ordinary Application Support
library. The saver never opens the original source folder or reuses another app's
app-scoped bookmark. Only the main app retains the source bookmark for refresh.

## Packaging and implementation

The Xcode Build Screensaver phase calls `Screensaver/build.py`, embedding:

- `Contents/Resources/Screensaver/Quiet Go.saver`
- `Contents/Resources/Screensaver/SGF Screensaver Preview.app`

The Preview button opens that companion app, which loads the same native bundle.
The installer copies the pre-signed bundle to `~/Library/Screen Savers/Quiet Go.saver`;
changing a folder never modifies/re-signs an executable. Enabling playback and
main-app launch update the installed module from the bundled version. The current
builder targets arm64/macOS 14+, chooses an available Developer ID identity, and
falls back to ad-hoc signing on development machines without one. A content
fingerprint avoids unnecessary recompilation. No games are embedded in the signed
bundles, and nothing is uploaded or notarized by these scripts.

The shared replay engine gets a module-local settings adapter. Main app preferences,
OGS, KataGo and sound services are not linked into the saver. ScreenSaverView owns
animation timing; late callbacks after stop are ignored. The distributed system
stop notification also pauses playback without killing Apple's shared host.

```sh
python3 Screensaver/build.py --output /tmp/quiet-go
python3 Screensaver/test.py
```

`Tests/MainRelease/ScreensaverSettings.swift` tests importing, installation,
enablement, failed replacement and settings rendering against the Release build.
It writes an isolated configuration-root path to `/private/tmp/sgf-integrated-fixture-path`.
The preview executable accepts `--test --configuration-root <that path>` for
signed-bundle rendering, timing, stop/restart, enablement and folder-change tests.
Source-folder access and all networking can be denied during this test.
`Screensaver/test.py --library <prepared-library>` additionally replays every SGF.

Diagnostics: Console filter `subsystem:com.davemarvit.SGFPlayer.QuietSaver`.
Native activation logs come from Apple's legacyScreenSaver process; preview-host
logs come from SaverPreview. Native selection is done in System Settings: the old
ScreenSaverEngine `-module` argument does not select a module on this Mac.
The installed bundle was also tested in Apple's actual host: three display views
each found all 692 prepared games, advanced through moves and stopped normally.

References:
- https://developer.apple.com/documentation/screensaver/screensaverview
- https://github.com/AerialScreensaver/ScreenSaverMinimal

Earlier failed bundles and the previous main app are retained in the dated
Integrated-screensaver backup. Prior backups remain intact.
The later Screensaver-cleanup backup also archives MinimalTest.saver,
TestScreensaver.saver and SGFPlayerScreensaver.saver outside the installed
screensaver directories, removing the failed attempts from the chooser.
