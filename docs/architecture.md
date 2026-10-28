# Architecture

## Swift package

- `SSHSig`: SSH signatures (`ssh-keygen -Y` format) for a P-256 key, and
  parsing of the statements the owner signs.
- `Pairing`: the pairing code, scopes, and allowed signers lines. Pure
  logic, shared by both apps, tested with `ssh-keygen`.
- `attention-sign`: the Mac command that shows a statement and signs it
  with Touch ID.

## Apps

- `Apps/iOS`: the iPhone and iPad app. It pairs with the Mac.
- `Apps/macOS`: the Mac app. It shows the pairing sheet.
- `Apps/Shared`: the iCloud store both apps use ([sync](sync.md)).
- Both are named Board, with bundle id `com.stemmacorp.board` and team
  `78HLU526FA`.

## Scripts

- `bin/lint`, `bin/test`: the package's gates. CI runs them on macOS.
- `bin/project`: generates `Board.xcodeproj` from `project.yml` with
  XcodeGen. The project is not committed.
- `bin/install-phone`, `bin/install-mac`: build, sign and install an app.
- `bin/setup`: walks the owner through first-time setup.

Not built: the apps are not built in CI; the bundle of `board`, plugins,
skills and hooks.
