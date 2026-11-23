# Release checks

[Releasing](release.md) says when each run happens.

## A tag run

The `version` job stops the release, with a message that names the cause,
when:

- the tag is not `v` followed by `MARKETING_VERSION`;
- the tagged commit is not on main;
- crumbkit/board has no tag `v<version>`, or no published release for it.
  crumbkit/board's tag `v0.1.0` has no release, so a Board.app `v0.1.0`
  tag stops here.

The `dmg` job checks out crumbkit/board beside the app and runs
`bin/dmg v<version>`, so the app carries the Board release built from
crumbkit/board's tag of the same version. A rerun of a tag run builds the
same Board. The job then checks that the bundled `board --version` prints
that version, runs `xcrun stapler validate` on the image it publishes, and
writes `SHA256SUMS` and a build provenance attestation for
`Board-<version>.dmg`. The `release` job checks `SHA256SUMS` again and
attaches the image and `SHA256SUMS` to a GitHub release named after the
tag. Anyone can check the image with:

```bash
gh attestation verify Board-0.1.1.dmg --repo crumbkit/board-app
```

The image is published as `Board-<version>.dmg`, with no release id in the
name, and `SHA256SUMS` lists it under that name. The cask script in the
crumbkit/tap Homebrew tap reads that name from the latest release's
`SHA256SUMS`, so a change to the name must change that script too.

## A manual run

A manual run builds with the crumbkit/board ref its `board_ref` input
names, `origin/main` by default, and never publishes. When the ref is a
version tag such as `v0.1.1`, the run makes the same tag, release and
version checks as a tag run.

## A pull request

A pull request that changes the workflow, `bin/bundle`, `bin/dmg` or
`bin/project` builds the Board release and both apps unsigned, which needs
no secrets.
