# Release secrets

The owner adds five secrets to the [`release` environment](release-environment.md)
after he creates it. Only the owner handles them; no agent creates, reads,
copies or prints one.

| Secret | What it holds |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | The "Developer ID Application" certificate of team `78HLU526FA` with its private key, as a `.p12` file in base64. |
| `DEVELOPER_ID_P12_PASSWORD` | The password the `.p12` file was exported with. |
| `ASC_API_KEY_P8_BASE64` | An App Store Connect team API key with the Admin role, which may create the Developer ID provisioning profile, as the `.p8` file in base64. |
| `ASC_API_KEY_ID` | That key's ID. |
| `ASC_API_ISSUER_ID` | The issuer ID shown above the keys in App Store Connect. |

## Exporting each one without exposing it

`gh secret set <NAME> --env release --repo crumbkit/board-app` reads the
value from stdin, or prompts for it without echoing it when stdin is a
terminal. A value therefore never goes on a command line, the shell
history or the process list, and never reaches the terminal's scrollback.
The files go in a fresh directory that is deleted at the end.

```bash
dir=$(mktemp -d)
set_secret() { gh secret set "$1" --env release --repo crumbkit/board-app; }
```

1. In Keychain Access, under login > My Certificates, export the
   "Developer ID Application" identity as `$dir/developer-id.p12`, with a
   new password. Then:

   ```bash
   base64 -i "$dir/developer-id.p12" | set_secret DEVELOPER_ID_P12_BASE64
   set_secret DEVELOPER_ID_P12_PASSWORD   # type the export password at the prompt
   ```

2. In App Store Connect, under Users and Access > Integrations > Team Keys,
   generate a key with the Admin role and download `AuthKey_<id>.p8` once,
   into `$dir`. Then:

   ```bash
   base64 -i "$dir"/AuthKey_*.p8 | set_secret ASC_API_KEY_P8_BASE64
   set_secret ASC_API_KEY_ID      # type the key ID from the same page
   set_secret ASC_API_ISSUER_ID   # type the issuer ID from the same page
   ```

3. Delete the exported files, and check that the five names are set.
   `gh secret list` prints names and dates, never values.

   ```bash
   rm -rf "$dir"
   gh secret list --env release --repo crumbkit/board-app
   ```

When a certificate or key expires or is revoked, the `dmg` job stops at
the step that uses it. The owner renews it and sets the secret again in
the same way.
