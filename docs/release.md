# Releasing Board.app

`.github/workflows/release.yml` builds Board.dmg on GitHub's `xcode-27`
runner with [`bin/dmg`](bundle-dmg.md) and publishes it.

## Releasing a version

1. Land a pull request that sets `MARKETING_VERSION` in `project.yml` to
   the new version, such as `0.1.0`.
2. Tag the merge commit on main and push the tag:

   ```bash
   git tag v0.1.0 && git push origin v0.1.0
   ```

The `version` job stops the release when the tag is not `v` followed by
`MARKETING_VERSION`. The `dmg` job checks out crumbkit/board beside the app
and runs `bin/dmg origin/main`, so the app carries a Board release built
from Board's main. It then writes `SHA256SUMS` and a build provenance
attestation for `Board-<version>.dmg`. The `release` job attaches the image
and `SHA256SUMS` to a GitHub release named after the tag. Anyone can check
the image with:

```bash
gh attestation verify Board-0.1.0.dmg --repo crumbkit/board-app
```

A manual run of the workflow does the same build, signing and attestation
and publishes nothing. Its `board_ref` input names the Board ref the app
carries. A pull request that changes the workflow, `bin/bundle`, `bin/dmg`
or `bin/project` builds the Board release and both apps unsigned, which
needs no secrets.

## Secrets

The `dmg` job reads five repository secrets, and stops naming the first one
that is not set:

| Secret | What it holds |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | The "Developer ID Application" certificate of team `78HLU526FA` with its private key, exported from Keychain Access as a `.p12` file, in base64. |
| `DEVELOPER_ID_P12_PASSWORD` | The password the `.p12` file was exported with. |
| `ASC_API_KEY_P8_BASE64` | An App Store Connect team API key with the Admin role, which may create the Developer ID provisioning profile, the `.p8` file in base64. |
| `ASC_API_KEY_ID` | That key's ID. |
| `ASC_API_ISSUER_ID` | The issuer ID shown above the keys in App Store Connect. |

The job imports the certificate into a keychain that lives only for the
job. `bin/dmg` passes the API key to `xcodebuild` through `ASC_KEY_PATH`,
`ASC_KEY_ID` and `ASC_ISSUER_ID`, so Xcode fetches the Developer ID
provisioning profile that iCloud needs without a signed-in account.
notarytool uses the same key through the keychain profile `board-notary`.
