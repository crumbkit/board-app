# Building Board.dmg

`bin/dmg [board-ref] [attention-ref]` builds a disk image for installing
Board.app on another Mac. The refs go to `bin/bundle`.

## What it does

1. Runs `bin/bundle`, then `bin/project`, so the app carries the release.
2. Archives Board-macOS and exports it for Developer ID. Xcode fetches the
   provisioning profile the iCloud entitlements need.
3. Signs every Mach-O file in `Contents/Resources/board`, which today are
   `bin/board` and `bin/attention-sign`, with the Developer ID certificate
   the export used, the hardened runtime and a timestamp, then signs the
   app again with its exported entitlements.
4. Checks the exported app: it passes `codesign --verify --deep --strict`,
   and each bundled executable has the Developer ID authority and the
   hardened runtime.
5. Puts the app and an `/Applications` link in a compressed image, and signs
   the image.
6. Notarises the image and staples the ticket to it, when the notarytool
   keychain profile works.
7. Mounts the image and checks it: the app passes `codesign --verify --deep
   --strict` and `bin/board --version` runs. When notarised, `spctl` accepts
   the image and the app.

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

Drag Board.app to `/Applications`, then run its installer as
[INSTALL.md](../Install/INSTALL.md) says.

## Not built

- Only the image carries a stapled ticket. The app dragged out of it does
  not, so its first launch needs Gatekeeper's online check of the ticket.
- When the image is not notarised, a Mac that downloaded it blocks the app,
  and also the `board` and `attention-sign` the installer copies into
  `~/.local/bin`, until the owner allows each in System Settings > Privacy &
  Security.
- Nothing publishes the image or checks for a newer one.
