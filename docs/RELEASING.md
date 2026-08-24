# Releasing

Players run `FlatWorld.exe`. On every launch it asks the GitHub Releases API for
the newest release of `biroman/rpg-this`, and if the tag is higher than the
version baked into the build it downloads, installs and relaunches itself. So
"shipping an update" and "creating a GitHub release" are the same action.

## Every time you want players on a new build

```powershell
.\tools\release.ps1
```

That is the whole loop. It bumps the patch version (`0.1.0` → `0.1.1`), exports,
zips, commits everything pending, tags, pushes and creates the release.

Variants:

```powershell
.\tools\release.ps1 0.2.0                      # explicit version
.\tools\release.ps1 -Notes "New rocket physics" # hand-written release notes
.\tools\release.ps1 -DryRun                     # show what would happen, change nothing
```

Without `-Notes` the release notes are generated from the commits since the last
tag.

## One-time setup

1. **Export templates.** In Godot: *Editor → Manage Export Templates → Download
   and Install*. ~1 GB, only needed once per Godot version.
2. **GitHub CLI.** `gh auth login` (already done on this machine).
3. **Godot on PATH**, or point the script at it:
   `$env:GODOT = 'C:\path\to\Godot_v4.7-stable_win64.exe'`

## How a player gets the game the first time

Send them <https://github.com/biroman/rpg-this/releases/latest>, tell them to
download `FlatWorld-windows.zip`, right-click → *Extract All*, and run
`FlatWorld.exe`. They never download anything manually again.

Extract somewhere writable — Desktop or Documents. Inside `C:\Program Files` the
self-update needs admin rights and will silently fall back to the old version.

## Moving parts

| Piece | Role |
| --- | --- |
| [`scenes/boot/boot.gd`](../scenes/boot/boot.gd) | Boot scene. Checks, downloads, stages, relaunches. |
| [`export_presets.cfg`](../export_presets.cfg) | The `Windows Desktop` preset the script exports. |
| [`tools/release.ps1`](../tools/release.ps1) | The release command. |
| [`tools/PLAY-ME-FIRST.txt`](../tools/PLAY-ME-FIRST.txt) | Bundled into the ZIP for the player. |
| `application/config/version` in `project.godot` | The build's own version, stamped by the script. |

The updater compares the release `tag_name` (`v0.2.0`) to
`application/config/version` (`0.2.0`). Never edit that setting by hand — the
release script owns it, and a mismatch means players either never update or
update in a loop.

## Failure behaviour

Every error path in the updater falls through to "just start the game": no
network, no releases yet, GitHub rate limit (60 anonymous requests/hour), a
corrupt download, a locked install folder. A broken update must never stop
someone from playing.

## Rolling back a bad build

```powershell
gh release delete v0.2.1 --repo biroman/rpg-this --cleanup-tag --yes
```

Players who already updated stay on the bad build until you release a *higher*
version — the updater only ever moves forward. So the real fix is to ship
`v0.2.2`, not to delete `v0.2.1`.

## Notes

- The game is unsigned, so Windows SmartScreen warns on the *first* manually
  downloaded copy. Self-installed updates are written by the game itself and do
  not carry the mark-of-the-web, so the warning never comes back.
- Each update is a full ~50 MB download. If that ever becomes annoying, ship
  `FlatWorld.pck` as a second release asset and have the updater grab only that
  when `FlatWorld.exe` is unchanged — the engine binary only changes when you
  upgrade Godot.
- `export_presets.cfg` is committed on purpose: the release needs it. Keep
  signing credentials out of it if you ever enable code signing.
