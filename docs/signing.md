# Signing

## What is signed

- `attention-sign sign` signs an order statement in `attention/order/v1`.
- `attention-sign approve` signs a Board statement in the namespace its first
  line names: `board/approve/v1` for a pending effect, `board/write/v1` for the
  owner's own write under `effects/`.
- The phone signs `Effect.approval` of the effect it shows, in
  `board/approve/v1`, and a pairing transcript with no namespace.
- Each signature needs the device's biometry. [Security](security.md) covers
  the keys.

Board and attention verify approvals and orders with `ssh-keygen -Y verify`
against their allowed signers files; nothing here does. The Mac verifies one
signature itself: the phone's pairing proof, with CryptoKit, in `Pairing`.

## Owners

- `SSHSig` owns the bytes of every SSH signature: the namespaces, the SSHSIG
  blob and armor, the statement layouts and the text of an allowed signers
  line (`AllowedSigners`). `Pairing` owns the pairing transcript and checks
  its proof; it may import CryptoKit. The namespace constants have `package` access, so the
  apps reach a namespace only through `Approval` or an `AllowedSigners` line.
- `attention-sign` owns the Mac's key. `attention-sign line` prints the Mac's
  line for Board's file, so `bin/setup` holds no namespace. `bin/bundle`
  bundles it and `Install/install` installs it.
- `PhoneKey` owns the phone's key: it signs approvals and the pairing proof.
  The Mac's pairing sheet may use LocalAuthentication for Touch ID.
- `AllowedSignersFile.update` and `bin/setup` are the only writers of the
  allowed signers files. Review keeps this; no gate checks it.

`bin/check-signing`, run by `bin/lint`, holds a fixed list of signing
literals: the framework names, the Secure Enclave and key APIs, the
namespaces, the SSH signature markers, `allowed_signers`, `ssh-keygen` and
`attention-sign`. It searches every file outside docs, Markdown and the
vectors, following symlinks. `signing-owners.txt` names the paths that may
hold each literal; a hit anywhere else fails. Only tests may name `SecKey`.

## Vectors

`vectors/signing/` is a copy of Board's signing vectors, taken at crumbkit/board
86643748. `VectorTests` checks this repository's approval statement, namespaces,
key line and armor against them, parses the order statement, and that the lines it writes admit their
signatures in the right namespace only. `ManifestTests` refuses a copy whose
files differ from `manifest.json`. A new layout arrives as a new version
directory: copy it whole from crumbkit/board and leave `v1` as it is.

## Never

An agent never imports CryptoKit or LocalAuthentication outside the owners,
writes an allowed signers file, adds a namespace, or runs `bin/setup` or
`bin/install-phone`.
