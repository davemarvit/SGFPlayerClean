# Quiet Go screensaver prototype

Branch: `codex/native-sgf-screensaver`. This is separate from the main application;
it does not change the app's preferences, login, saved games, or analysis cache.

## Try the installed build

- Preview app: `/Users/Dave/Applications/SGF Screensaver Preview.app`
- Native screensaver: `/Users/Dave/Library/Screen Savers/Quiet Go.saver`
- In **System Settings → Screen Saver**, select **Quiet Go** (under Other) and use
  Preview. This last step exercises Apple's actual sandboxed screensaver host.

The preview app loads the very same `.saver` bundle, rather than a second renderer.
Close its window or press Command-Q to exit. The prototype is silent, advances a
move every approximately 1.5 seconds, holds the final position for seven seconds,
and cycles through the playlist. It uses the normal SGF parser and replay engine,
including setup, captures, passes and the first variation/main line.

For this first experiment, the build copied 80 recent SGFs from
`/Users/Dave/Go/Games` into its own `Contents/Resources/Games` folder. It scans that
folder on creation. These are copies, not live links; edits/additions to the source
folder require rebuilding the prototype. Originals are untouched. Bundling the
folder avoids the separate security-scoped folder-selection problem in Apple's
sandboxed host. Folder selection, 3D, lids, shuffling and other options are deferred.
Don't edit the installed bundle's contents: that invalidates its signature.

## Build and test

Requires Xcode command-line tools on Apple Silicon. This prototype currently
builds arm64 only, with a minimum deployment target of macOS 14.

```sh
python3 Screensaver/build.py --games-folder /path/to/SGFs --output /tmp/quiet-go \
  --identity 'Developer ID Application: Your Name (TEAMID)'
python3 Screensaver/test.py --library '/tmp/quiet-go/Quiet Go.saver/Contents/Resources/Games'
'/tmp/quiet-go/SGF Screensaver Preview.app/Contents/MacOS/SaverPreview' --test
```

`--limit` controls the maximum number of source SGFs copied (default 80); newest
files are selected first. Empty or >2 MB files are omitted. The manifest includes
original paths and content hashes. The builder verifies signatures but does not
install anything or change the selected system screensaver. Without `--identity`,
it uses ad-hoc signing for development. The local installed build is signed with
the owner's Developer ID certificate, without notarization or any upload.

The playlist tests run with networking denied. The host tests load the real signed
bundle, advance real timers, render at full and preview sizes, stop/resume and
check independent instances. Test images are written to `/private/tmp/sgf-saver-*`.
The shared engine uses a tiny module-local playback-settings adapter, not the main
app's preference/audio services. Neither OGSClient nor KataGo is linked. The saver
owns no repeating timers: animation follows ScreenSaverView's lifecycle. Late
frame callbacks after stop are ignored. A distributed system stop notification
also pauses playback, without terminating Apple's shared host process.

## Verification status and previous attempt

The installed old SGF saver had literal `$(EXECUTABLE_NAME)` in its Info.plist.
Both earlier test saver bundles failed code-sign verification. This prototype
uses an explicit executable/principal-class name and a verified signature.
Old saver bundles and main-app backups were retained.

Native integration remains to be verified by selecting Quiet Go in Settings.
Launching ScreenSaverEngine directly from the terminal was rejected by macOS's
launch constraints for Apple's engine (not by rejection of our bundle). Opening
the engine through Launch Services worked, but the historical `-module` argument
did not select/load Quiet Go on macOS 15.7.3. There are no Quiet Go playback logs
from the system host yet. This environment has no Accessibility permission to
select it in Settings. No wallpaper, lock, idle-timeout or selected-saver settings
were edited, and no security protections were disabled.

The documented native integration is Apple's ScreenSaverView:
https://developer.apple.com/documentation/screensaver/screensaverview

Relevant current host lifecycle/sandbox limitations are documented by the author
of ScreenSaverMinimal (reference only; no source copied into this prototype):
https://github.com/AerialScreensaver/ScreenSaverMinimal

Diagnostics: Console filter `subsystem:com.davemarvit.SGFPlayer.QuietSaver`.
Successful native activation should show View initialized, Loaded game, Started,
and increasing Move entries from Apple's legacyScreenSaver host, not SaverPreview.

Final offline validation on 2026-10-16: all 80 copied games replayed to completion
(18,234 moves; zero unsupported/empty records). Playlist regression fixtures and
the signed-bundle preview-host tests pass. The small-preview caption fits without
clipping. All test processes were closed after verification.
