# Security

## Keys

- Each device has its own P-256 key in its Secure Enclave. Signing needs
  Touch ID or Face ID (`biometryCurrentSet`), so enrolling a new finger or
  face makes the key unusable.
- The Mac's key blob is `~/.config/attention/secure-enclave-key`; the
  phone's is in the app's Application Support. A blob is useless on any
  other chip. No key is synced.

## Allowed signers

- Board checks approvals against `~/.config/board/allowed_signers`;
  attention checks orders against `~/.config/attention/allowed_signers`.
  Both use principal `owner`.
- A paired device gets one line per file, limited by `namespaces=`: agent
  requests in Board's file, orders in attention's. [Signing](signing.md)
  names the namespaces.
- No device may sign the owner's own protected writes. A phone paired
  before devices lost that permission keeps it until it pairs again.
- The line ends in `board-app/device/<id>`. Pairing again replaces every
  line in the file with that label or the phone's key, and removing the phone deletes
  them from both files; every other line stays.
- The Mac writes the files after Touch ID, to add and to remove. It
  follows a symlink and keeps the file's mode, writing a file beside it
  with that mode and renaming it over the old one. It refuses what Board would not trust, a file that group
  or others may write or that neither the user nor root owns, and a file it
  cannot read, so a failed read never drops the Mac's line.
- A device id must be a UUID, so it cannot carry a newline or space into a
  line.
- A phone's key is replaced when its blob does not load, for example after
  a restore onto another phone. The blob is kept out of backups.

- The Mac's own line in Board's file admits approvals and the owner's own
  writes under `effects/`, such as the removal of `.board/board.json`.
  `bin/setup` adds the line `attention-sign line` prints, replacing any older
  line for the same key.

## Known gaps

- Any program running as the owner can edit the allowed signers files.
  Only the sandbox an agent runs in stops that.
- Whoever can write the owner's iCloud zone can refuse a request, but not
  approve one.
- Any program running as the owner can edit `~/.config/board/launcher.json`
  and so choose what the launcher runs. Board.app refuses the file only
  when someone else could write it ([launcher safety](launcher-safety.md)).
