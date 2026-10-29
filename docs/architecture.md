# Architecture

## Swift package

- `SSHSig`: SSH signatures (`ssh-keygen -Y` format) for a P-256 key,
  parsing of the statements the owner signs, the approval statement of a
  Board pending effect, with the JSON form Board prints, and the text of an
  allowed signers line. It owns the bytes of every SSH signature
  ([signing](signing.md)).
- `Pairing`: the pairing code, scopes, and the writer of the allowed
  signers files. Pure logic, shared by both apps, tested with `ssh-keygen`.
- `Requests`: how the phone words a pending effect, orders the inbox,
  counts each board, and diffs a put line by line or field by field. Pure
  logic.
- `attention-sign`: the Mac command that shows a statement and signs it
  with Touch ID.

## Apps

- `Apps/iOS`: the iPhone and iPad app. It pairs with the Mac; once paired,
  it opens on the inbox, and a request opens on its own screen. A half-folded iPhone Duo shows the tabletop layout.
- `Apps/macOS`: the Mac app. It shows the pairing sheet and relays pending
  effects and answers between the personal board and the phone.
- `Apps/Shared`: the iCloud stores both apps use ([sync](sync.md)).
- Both are named Board, with bundle id `com.stemmacorp.board` and team
  `78HLU526FA`.

## Scripts

- `bin/lint`, `bin/test`: the package's gates. CI runs them on macOS.
  `bin/lint` first runs `bin/check-signing`, the signing firewall.
- `bin/project`: generates `Board.xcodeproj` from `project.yml` with
  XcodeGen. The project is not committed.
- `bin/install-phone`, `bin/install-mac`: build, sign and install an app.
- `bin/setup`: walks the owner through first-time setup.

Not built: the apps are not built in CI; the bundle of `board`, plugins,
skills and hooks.
