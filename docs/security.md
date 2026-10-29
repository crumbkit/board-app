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
- A paired device gets one line per file, limited by `namespaces=`:

  | Scope | File | Namespace |
  | --- | --- | --- |
  | Agent requests | board | `board/approve/v1` |
  | Orders | attention | `attention/order/v1` |

- No device gets `board/write/v1`, the owner's own protected writes.
  A phone paired before this changed keeps it until it pairs again.
- The line ends in `board-app/device/<id>`. Pairing again replaces it;
  every other line stays.
- The Mac writes the files after Touch ID. It follows a symlink and keeps
  the file's mode. It refuses what Board would not trust, a file that group
  or others may write or that neither the user nor root owns, and a file it
  cannot read, so a failed read never drops the Mac's line.
- A device id must be a UUID, so it cannot carry a newline or space into a
  line.
- A phone's key is replaced when its blob does not load, for example after
  a restore onto another phone. The blob is kept out of backups.

- The Mac's own line in Board's file names `board/approve/v1` and
  `board/write/v1`. The Mac's key signs the owner's own writes under
  `effects/` and the removal of `.board/board.json`. `bin/setup` adds the line,
  replacing any older line for the same key.
- `attention-sign approve` signs a statement in the namespace its first line
  names: `board/approve/v1` for a pending effect, `board/write/v1` for the owner's
  own write.

- The phone signs the statement `Effect.approval` builds from the effect
  it shows. Tests pin it to board's `Effect::approval`. Board verifies;
  the Mac only relays.

## Known gaps

- Any program running as the owner can edit the allowed signers files.
  Only the sandbox an agent runs in stops that.
- Whoever can write the owner's iCloud zone can refuse a request, but not
  approve one.
