# Letting this Mac sign

The install sheet's step that adds this Mac's line to
`~/.config/board/allowed_signers`, so Board trusts the approvals, writes and
orders this Mac signs. `Install/SIGNING.md`, which the release carries, says
the same to the owner.

- After Install, Done shows the step "Let this Mac sign" while this Mac's
  line is missing from `~/.config/board/allowed_signers` or lacks a
  namespace. The menu bar has Let This Mac Sign… for the same step until
  the line is there. Status runs `board-sign line` only when a key exists,
  and compares its exact line with the file's lines.
- With no key yet, the step lists the signing key and the approvals and
  orders it would admit, and Make Key runs `board-sign line`, which makes
  the key.
- It then shows the one line, the file, what the line admits and how many
  other lines the file keeps. Add with Touch ID asks for Touch ID alone,
  then checks the file and writes it with `AllowedSignersFile.setOwn`.
  Cancelling Touch ID leaves the line shown and writes nothing.
- Afterwards it shows "This Mac can sign" with the lines it kept; or "This
  Mac cannot sign" with board-sign's message and exit; or "Board did not add
  the line" with the file, its mode and owner, `chmod 644` and the request to
  read its lines, Show in Finder, Close and Try Again. How Board checks
  signatures opens `SIGNING.md` from the release.

## What it writes

- The line `board-sign line` prints: `board/approve/v1`, `board/write/v1`
  and `attention/order/v1`, ending in `board`.
- It replaces every line with the same key, where the first stood, and keeps
  every other line byte for byte. A line of an older key of this Mac stays,
  since it cannot be told apart from another Mac's.
- A new file gets mode 644, a missing `~/.config/board` is made, a symlink is
  followed and kept, and an existing file keeps its mode. The write is one
  rename. Board.app keeps no record of the step.
