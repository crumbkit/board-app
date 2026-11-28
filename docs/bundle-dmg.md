# Building Board.dmg

`bin/dmg [board-ref]` builds a disk image for installing Board.app, and
with it `board`, on another Mac. The ref goes to `bin/bundle`.

## What it does

1. Runs `bin/bundle`, then `bin/project`, so the app carries the release.
2. Archives Board-macOS and exports it for Developer ID. Xcode fetches the
   provisioning profile the iCloud entitlements need.
3. Signs every Mach-O file in `Contents/Resources/board`, which today are
   `bin/board` and `bin/board-sign`, with the Developer ID certificate
   the export used, the hardened runtime and a timestamp, then signs the
   app again with its exported entitlements.
4. Checks the exported app: it passes `codesign --verify --deep --strict`,
   and each bundled executable has the Developer ID authority and the
   hardened runtime.
5. Puts the app and an `/Applications` link in a compressed image, and signs
   the image.
6. Notarises the image and staples the ticket to it, when the notarytool
   keychain profile works. It prints the submission id as notarytool
   reports it, and stops when Apple has not answered within 45 minutes.
7. Mounts the image and checks it: the app passes `codesign --verify --deep
   --strict` and `bin/board --version` runs. When notarised, `spctl` accepts
   the image and the app.
8. Copies the app out of the image to a scratch folder and runs its
   `install`, without `--hooks` as Board.app runs it, into a scratch home
   with a scratch git identity and a stub `claude` that lists nothing. The
   output goes to `.build/dmg/install.log`. The check fails unless the
   install exits 0 and ends with `is installed.`, the scratch config names
   `~/Board` as the personal board, that board enables exactly tasks,
   evals, runs, rules, plans and share, and `~/.claude/skills` holds only
   their skills.

It writes `.build/dmg/Board-<version>-<release id>.dmg`, with
`-unnotarised` before `.dmg` when the image is not notarised. The image
gets that name only after every check passes. A failed check is an error.

## What it needs

- The `bin/bundle` tools, XcodeGen and Xcode.
- A "Developer ID Application" identity of team `78HLU526FA` in the keychain.
- Xcode signed in to an Apple ID in that team, under Xcode > Settings >
  Accounts. Without it the archive fails with `No Account for Team`.
- For notarisation, a notarytool keychain profile named by `NOTARY_PROFILE`,
  by default `board-notary`. The owner stores it once:

  ```bash
  xcrun notarytool store-credentials board-notary --apple-id <apple-id> --team-id 78HLU526FA
  ```

  When the default profile is not stored, `bin/dmg` ends with a signed
  image that is not notarised, and prints notarytool's error. Any other
  notarytool error, and a profile named in `NOTARY_PROFILE` that does not
  work, stops it with an error.

## Installing from it

Drag Board.app to `/Applications` and open it. The Board window offers to
install the release it carries ([window](window.md#installing-board)). An
agent can run the installer instead, as
[INSTALL.md](../Install/INSTALL.md) says.

## Not built

- Only the image carries a stapled ticket. The app dragged out of it does
  not, so its first launch needs Gatekeeper's online check of the ticket.
- When the image is not notarised, a Mac that downloaded it blocks the app,
  and also the `board` and `board-sign` the installer copies into
  `~/.local/bin`, until the owner allows each in System Settings > Privacy &
  Security.
- Nothing checks for a newer image. A version tag publishes one, as
  [releasing](release.md) says.
