# Source cleanup — October 16, 2026

The current source is `/Users/Dave/SGFPlayerClean`, branch `main`. The installed
app remains `/Users/Dave/Applications/SGFPlayerClean.app`. This cleanup changes
source organization only; it does not update the installed app or user settings.

## Retired folders

| Former location | Reason and preservation |
| --- | --- |
| `~/SGFPlayer` | Older, separate implementation. Full verified ZIP includes its Git history, builds, experiments and uncommitted notes. |
| `~/SGFPlayerClean_backup_phase1.3` | Historical source snapshot. Full verified ZIP retained. |
| `~/SGFPlayerScreensaverPrototype` | Clean prototype checkout, entirely merged into main. Verified source ZIP and all-branches Git bundle retained; removed with Git's worktree command. |
| `~/Documents/SGF PLayer/SGFPlayerClean-review` | Clean retired review checkout, entirely merged into main. Verified source ZIP and Git bundle retained; removed with Git's worktree command. |

Archives are in the dated Cleanup folder under
`~/Documents/SGF PLayer/Source Archives`. Its `manifest.json` records source/archive
sizes and archive hashes. Per-folder file manifests record SHA-256 checksums;
regular file contents and symbolic-link targets were compared with the originals
before removing them. The all-branches bundle also preserves local commits that
have not been pushed. This cleanup does not publish anything to GitHub.

`REDUNDANT_BACKUP`, `SGFPlayerClean/HIDDEN_OLD`, and the stray Xcode project backup
were unused by the build and are archived outside the working tree. Their previous
versions also remain in Git history. The obsolete Swift-package exclusion for
HIDDEN_OLD was removed. Finder's `.DS_Store` files are no longer tracked, but their
local contents were preserved. Rebuildable `.build` caches were discarded.

The current app and saver have no symlinks into the retired folders; build scripts
and saved app/screensaver settings were checked for dependencies on those paths.
Normal app data, analysis caches, SGF originals, model resources and all previous
application backups are retained. Historical documentation and test suites remain
available in the active source tree.

## Recovery

Restore a retired source folder from its ZIP if needed. For a complete repository,
clone `SGFPlayerClean-all-branches.bundle` with Git; it includes every local branch
and the full history, including the final cleanup commit. The archives' `START HERE.txt` provides
the exact current app/source paths and an inventory.
