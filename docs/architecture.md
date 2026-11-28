# Architecture

## Swift package

- `SSHSig`: SSH signatures (`ssh-keygen -Y` format) for a P-256 key,
  parsing of the statements the owner signs, the approval statement of a
  Board pending effect, with the JSON form Board prints, and the text of an
  allowed signers line. It owns the bytes of every SSH signature
  ([signing](signing.md)).
- `Pairing`: the pairing code, scopes, and the writer and reader of the
  allowed signers files. Pure logic, shared by both apps, tested with
  `ssh-keygen`.
- `Requests`: how the phone words a pending effect, orders the inbox,
  counts each board, diffs a put line by line or field by field, reads a
  request's thread of versions and replies, encodes a reply, and reads the
  answers Board recorded, and reads and answers agents' questions
  ([questions](sync-questions.md)). Pure logic.
- `Launcher`: the launcher's contract, screen model, provider runner and
  config check ([launcher](launcher.md)). Pure logic, with no AppKit.
- `Installer`: the release the Mac app carries and the one installed, the
  survey of known boards and old pieces the install sheet describes, the
  login shell's PATH, and the progress read from `install`'s lines
  ([bundle](bundle-install.md#lines-for-boardapp)). No AppKit.
- `board-sign`: the Mac command that shows a statement and signs it
  with Touch ID, and prints this Mac's allowed signers line.

## Apps

- `Apps/iOS`: the iPhone and iPad app. It pairs with the Mac; once paired,
  it opens on the inbox: agents' questions above requests. A request opens
  as a thread of its versions and replies; a question opens as its options
  and a note. On the open iPhone Duo in landscape, either sits beside the
  list. A half-folded iPhone Duo shows the inbox's tabletop layout.
- `Apps/macOS`: the Mac app. Its window lists what waits, what was
  answered and the paired iPhones, and opens pairing as a sheet
  ([window](window.md)). It offers to install the Board release it
  carries in a sheet on the same window. From launch until it quits, it relays pending
  effects, threads, answers, replies and open questions between the
  personal board and the phone. Its menu bar item and ⌃⌥Space open the
  launcher.
- `Apps/Shared`: the iCloud stores both apps use ([sync](sync.md)), and
  `AppIcon.icon`, the Icon Composer file that is both apps' icon.
- Both are named Board, with bundle id `com.stemmacorp.board` and team
  `78HLU526FA`.

## Scripts

- `bin/lint`, `bin/test`: the package's gates. CI runs them on macOS.
  `bin/lint` first runs `bin/check-signing`, the signing firewall.
- `bin/project`: generates `Board.xcodeproj` from `project.yml` with
  XcodeGen, adding `Bundle.yml` when `Bundle/board` exists. The project is
  not committed.
- `bin/build-apps`: builds both apps unsigned, as on a fresh clone. CI runs
  it.
- `bin/install-phone`, `bin/install-mac`: build, sign and install an app.
- `bin/dmg`: builds a Developer ID signed `Board.dmg` of the Mac app
  ([Board.dmg](bundle-dmg.md)).
- `bin/setup`: walks the owner through first-time setup.
