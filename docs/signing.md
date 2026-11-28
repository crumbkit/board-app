# Signing

## What is signed

- `board-sign sign` signs an order statement in `attention/order/v1`.
- `board-sign approve` signs a Board statement in the namespace its first
  line names: `board/approve/v1` for a pending effect, `board/write/v1` for the
  owner's own write under `effects/`.
- The phone signs `Effect.approval` of the effect it shows, in
  `board/approve/v1`, and a pairing transcript with no namespace.
- Each signature needs biometry; [security](security.md) covers the keys.

Board verifies every signature with `ssh-keygen -Y verify` against
`~/.config/board/allowed_signers`. Only the phone's pairing proof is checked
here, with CryptoKit, in `Pairing`.

## Owners

- `SSHSig` owns the bytes of every SSH signature: the namespaces, the SSHSIG
  blob and armor, the statement layouts and the text of an allowed signers
  line (`AllowedSigners`). `Pairing` owns the pairing transcript and checks
  its proof; it may import CryptoKit. The namespace constants have `package` access, so the
  apps reach a namespace only through `Approval` or an `AllowedSigners` line.
- `board-sign` owns the Mac's key. It moves the older `attention-sign`'s
  key to Board's folder and leaves a link. `board-sign line` prints the
  Mac's line, so neither `bin/setup` nor the app holds a namespace.
- `PhoneKey` owns the phone's key: it signs approvals and the pairing proof.
  The Mac's pairing sheet and its signing step (`MacSigning`) may use
  LocalAuthentication for Touch ID.
- `AllowedSignersFile.update`, `AllowedSignersFile.setOwn` and `bin/setup`
  are the only writers of Board's allowed signers file. Review keeps this;
  no gate checks it.

`bin/check-signing`, run by `bin/lint`, holds a fixed list of signing
literals: the framework names, the Secure Enclave and key APIs, the
namespaces, the SSH signature markers, `allowed_signers`, `ssh-keygen` and
the two signers' names. It searches every file outside docs, Markdown and the
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
