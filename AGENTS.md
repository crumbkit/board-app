# Board.app

Board.app is the macOS app that ships Board. Today it holds one part:
`attention-sign`, the Touch ID window in which the owner signs attention
directives and Board approvals.

## What exists

- `Sources/SSHSig`: builds the statement the owner signs and writes it as an
  SSH signature (`ssh-keygen -Y` format).
- `Sources/attention-sign`: the command and its window. `attention-sign key`
  makes or shows the Secure Enclave key, `sign` signs a directive and
  `approve` signs a Board approval.
- The key lives in `~/.config/attention/secure-enclave-key`, outside the
  keychain, so a rebuilt or re-signed app keeps using it.

The board-attention plugin runs `attention-sign` from `$ATTENTION_SIGN` or
the PATH.

## What comes next

Board.app will carry the `board` binary, every Board plugin at its latest
version, their skills and hooks, and a skill that installs or updates them
on a Mac. None of that is built yet.

## Gates

Run `bin/lint` and `bin/test` before every push. CI runs both on macOS.

## Writing

Use short sentences and plain words. Comments describe the code as it is.
