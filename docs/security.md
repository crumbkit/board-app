# Security

## Keys

- Each device has its own P-256 key in its Secure Enclave. Signing needs
  Touch ID or Face ID (`biometryCurrentSet`), so enrolling a new finger or
  face makes the key unusable.
- The Mac's key blob is `~/.config/board/secure-enclave-key`; the
  phone's is in the app's Application Support. A blob is useless on any
  other chip. No key is synced.

## Allowed signers

- Board checks approvals, the owner's own writes and orders against
  `~/.config/board/allowed_signers`, with principal `owner`.
- A paired device gets one line, limited by `namespaces=` to agent requests,
  orders or both. [Signing](signing.md) names the namespaces.
- No device may sign the owner's own protected writes. A phone paired
  before devices lost that permission keeps it until it pairs again.
- The line ends in `board-app/device/<id>`. Pairing again replaces every
  line in the file with that label or the phone's key, and removing the phone deletes
  them; every other line stays.
- The Mac writes the file after Touch ID, to add and to remove. It
  follows a symlink and keeps the file's mode, writing a file beside it
  with that mode and renaming it over the old one. It refuses what Board would not trust, a file that group
  or others may write or that neither the user nor root owns, and a file it
  cannot read, so a failed read never drops the Mac's line.
- A device id must be a UUID, so it cannot carry a newline or space into a
  line.
- A phone's key is replaced when its blob does not load, for example after
  a restore onto another phone. The blob is kept out of backups.

- The Mac's own line admits approvals, the owner's own writes under
  `effects/` and orders. The install sheet adds it after Touch ID
  ([signing step](signing-step.md)), as `bin/setup` does.

## Known gaps

- Any program running as the owner can edit the allowed signers file.
  Only the sandbox an agent runs in stops that.
- Whoever can write the owner's iCloud zone can refuse a request, but not
  approve one.
- Any program running as the owner can edit `~/.config/board/launcher.json`
  and so choose what the launcher runs. Board.app refuses the file only
  when someone else could write it ([launcher safety](launcher-safety.md)).
