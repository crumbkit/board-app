# Releasing Board.app

`.github/workflows/release.yml` builds Board.dmg on GitHub's `xcode-27`
runner with [`bin/dmg`](bundle-dmg.md) and publishes it. Board.app's
version is the version of the Board release it carries: Board.app 0.1.1
carries crumbkit/board v0.1.1.

- [Checks](release-checks.md): what a tag run, a manual run and a pull
  request run check and build.
- [Environment](release-environment.md): the `release` environment that
  holds the signing secrets, and who may reach it.
- [Secrets](release-secrets.md): the five secrets and how the owner
  exports each one without exposing it.
- [Fallback](release-fallback.md): building and publishing the image on
  the owner's Mac when the runner cannot start.

## Releasing a version

1. Check that crumbkit/board has a published release `v<version>`, such
   as `v0.1.1`. The app carries that Board release.
2. Land a pull request that sets `MARKETING_VERSION` in `project.yml` to
   the same version.
3. Start a manual run of the workflow on main with `board_ref` set to
   `v<version>`:

   ```bash
   gh workflow run release.yml --repo crumbkit/board-app --ref main -f board_ref=v0.1.1
   ```

   The run builds, signs, notarises, checks and attests the image exactly
   as the tag run will, and publishes nothing. Its artifact `board-dmg`
   holds the image and `SHA256SUMS`.
4. When that run passes and the owner approves the release, an agent tags
   the merge commit on main through Board's `github.tag`, which pushes a
   new tag only after the boundary passes it and never moves one:

   ```bash
   board call github.tag --name v0.1.1 --target <merge commit SHA> \
     --message "Board.app 0.1.1"
   ```

   The tag push starts the tag run, which publishes the release.

## The runner costs no minutes

`xcode-27` is a standard GitHub-hosted runner. The runner-images README
lists `xcode-27` and `xcode-27-xlarge` for the Xcode 27 image, and only the
`-large` and `-xlarge` labels are larger runners. GitHub's Actions billing
page says standard runners are free in public repositories and larger
runners are billed. crumbkit/board-app is public, and the Actions timing API
reports no billable minutes for its `xcode-27` jobs. Changing a job to
`xcode-27-xlarge` would bill its minutes.
