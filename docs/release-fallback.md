# Releasing from the owner's Mac

When the `xcode-27` runner cannot start, for example because of a billing
block or a missing image, the image is built on the owner's Apple silicon
Mac. That Mac needs what [`bin/dmg`](bundle-dmg.md#what-it-needs) needs:
the Developer ID identity in the login keychain, Xcode signed in to an
Apple ID in the team, and the notarytool profile `board-notary`. An image
built this way has `SHA256SUMS` but no build provenance attestation, so
`gh attestation verify` fails for it, and its release notes say so.

1. From a crumbkit/board-app checkout, build in a clean worktree of the
   merge commit on main, through deadband. `NOTARY_PROFILE` is set, so
   `bin/dmg` stops instead of writing an image that is not notarised.

   ```bash
   git worktree add --detach ../board-app-release <merge commit SHA>
   cd ../board-app-release
   NOTARY_PROFILE=board-notary deadband run --label board-app-release -- bin/dmg v0.1.1
   ```

2. Make the same checks as the tag run, and give the image the published
   name:

   ```bash
   .build/dmg/export/Board.app/Contents/Resources/board/bin/board --version   # board 0.1.1+<commit>
   mkdir dist
   cp .build/dmg/Board-0.1.1-*.dmg dist/Board-0.1.1.dmg
   xcrun stapler validate dist/Board-0.1.1.dmg
   (cd dist && shasum -a 256 -- *.dmg > SHA256SUMS)
   ```

3. Tag the merge commit through `github.tag`, as
   [Releasing a version](release.md#releasing-a-version) says. The tag
   push starts a tag run; cancel it, so that it cannot publish later.

   ```bash
   gh run list --repo crumbkit/board-app --workflow release.yml --event push --limit 1
   gh run cancel <run id> --repo crumbkit/board-app
   ```

4. Publish the release through Board's `github.release-create`, which
   uploads every file in `dist` once the boundary passes the release:

   ```bash
   board call github.release-create --tag v0.1.1 --title "Board.app 0.1.1" --assets dist \
     --notes "Board.app 0.1.1 for macOS on Apple silicon, signed with the Developer ID and notarised, with SHA256SUMS. Built on the owner's Mac, so it has no build provenance attestation."
   ```
