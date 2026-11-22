# Releasing Board.app

`.github/workflows/release.yml` builds Board.dmg on GitHub's `xcode-27`
runner with [`bin/dmg`](bundle-dmg.md) and publishes it.

## Releasing a version

1. Land a pull request that sets `MARKETING_VERSION` in `project.yml` to
   the new version, such as `0.1.0`.
2. Check that crumbkit/board has the tag `v<version>` of the same version
   and a published release for it. The app carries that Board release.
3. Start a manual run of the workflow on main with `board_ref` set to
   `v<version>`. The run builds, signs, notarises, checks and attests the
   image exactly as the tag run will, and publishes nothing. Its artifact
   `board-dmg` holds the image and `SHA256SUMS`.
4. When that run passes and the owner approves the release, tag the merge
   commit on main and push the tag:

   ```bash
   git tag v0.1.0 <merge commit> && git push origin v0.1.0
   ```

## What a tag run checks and builds

The `version` job stops the release, with a message that names the cause,
when:

- the tag is not `v` followed by `MARKETING_VERSION`;
- the tagged commit is not on main;
- crumbkit/board has no tag `v<version>`, or no published release for it.

The `dmg` job checks out crumbkit/board beside the app and runs
`bin/dmg v<version>`, so the app carries the Board release built from
crumbkit/board's tag of the same version. A rerun of a tag run builds the
same Board. The job then checks that the bundled `board --version` prints
that version, runs `xcrun stapler validate` on the image it publishes, and
writes `SHA256SUMS` and a build provenance attestation for
`Board-<version>.dmg`. The `release` job runs only for a tag push. It
checks `SHA256SUMS` again and attaches the image and `SHA256SUMS` to a
GitHub release named after the tag. Anyone can check the image with:

```bash
gh attestation verify Board-0.1.0.dmg --repo crumbkit/board-app
```

The image is published as `Board-<version>.dmg`, with no release id in the
name, and `SHA256SUMS` lists it under that name. The cask script in the
crumbkit/tap Homebrew tap reads that name from the latest release's
`SHA256SUMS`, so a change to the name must change that script too.

A manual run builds with the crumbkit/board ref its `board_ref` input
names, `origin/main` by default, and never publishes. When the ref is a
version tag such as `v0.1.0`, the run makes the same tag, release and
version checks as a tag run. A pull request that changes the workflow,
`bin/bundle`, `bin/dmg` or `bin/project` builds the Board release and both
apps unsigned, which needs no secrets.

## The release environment and its secrets

The `dmg` job runs in the GitHub environment `release` and reads five
secrets from it. It stops, naming the first secret that is not set. The
owner creates the environment once. Its deployment rule admits only main
and `v*` tags, so a run from any other branch cannot read the secrets. The
rule admits a `v*` tag on any commit, and a tag runs the release.yml of the
commit it names, so the rule alone lets a tag on another branch run an
edited workflow that reads the secrets. The owner is therefore a required
reviewer on the environment: every run waits for his approval before the
`dmg` job starts, and that approval is what keeps a tag on another branch
from reaching the secrets. The first command sets the owner, as the
signed-in `gh` user, as the reviewer, together with the deployment rule:

```bash
owner_id=$(gh api user --jq .id)
echo "{\"reviewers\":[{\"type\":\"User\",\"id\":$owner_id}],\"deployment_branch_policy\":{\"protected_branches\":false,\"custom_branch_policies\":true}}" |
  gh api --method PUT repos/crumbkit/board-app/environments/release --input -
gh api --method POST repos/crumbkit/board-app/environments/release/deployment-branch-policies \
  -f name=main -f type=branch
gh api --method POST repos/crumbkit/board-app/environments/release/deployment-branch-policies \
  -f name='v*' -f type=tag
```

A manual run started from another branch fails at the `dmg` job, because
the environment does not admit it.

The owner adds each secret with `gh secret set <NAME> --env release --repo
crumbkit/board-app`, which reads the value from stdin or prompts for it.
A value never goes on a command line, so it never reaches the shell
history or the process list.

| Secret | What it holds | How the owner adds it |
| --- | --- | --- |
| `DEVELOPER_ID_P12_BASE64` | The "Developer ID Application" certificate of team `78HLU526FA` with its private key, as a `.p12` file in base64. | Export the identity from Keychain Access, under login > My Certificates, as a `.p12` with a new password. Pipe `base64 -i <file>.p12` into `gh secret set`, then delete the `.p12`. |
| `DEVELOPER_ID_P12_PASSWORD` | The password the `.p12` file was exported with. | Type it at the `gh secret set` prompt. |
| `ASC_API_KEY_P8_BASE64` | An App Store Connect team API key with the Admin role, which may create the Developer ID provisioning profile, as the `.p8` file in base64. | Generate the key under Users and Access > Integrations > Team Keys and download `AuthKey_<id>.p8`. Pipe `base64 -i AuthKey_<id>.p8` into `gh secret set`. |
| `ASC_API_KEY_ID` | That key's ID. | Type it at the `gh secret set` prompt. |
| `ASC_API_ISSUER_ID` | The issuer ID shown above the keys in App Store Connect. | Type it at the `gh secret set` prompt. |

The job imports the certificate into a keychain that lives only for the
job, and deletes it when the job ends. `bin/dmg` passes the API key to
`xcodebuild` through `ASC_KEY_PATH`, `ASC_KEY_ID` and `ASC_ISSUER_ID`, so
Xcode fetches the Developer ID provisioning profile that iCloud needs
without a signed-in account. notarytool uses the same key through the
keychain profile `board-notary`. The job's log shows the notarisation
submission id and never a secret.
