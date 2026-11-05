# Building a release

- `bin/bundle [board-ref] [attention-ref]` writes `Bundle/board`. Each ref
  defaults to `origin/main` of the crumbkit/board checkout at
  `~/Code/crumbverse/board` and `~/Code/board-attention`; `BOARD_SRC` and `ATTENTION` name other checkouts. It reads them through git,
  so their working trees do not matter. It refuses to run while `Sources/`,
  `Install/`, `Package.swift` or `Package.resolved` has uncommitted changes.
- It needs cargo, jq, rsync, the Swift toolchain and `claude`, which
  validates each plugin it bundles.
- It gives each hook plugin the version `<version>+<commits>`, because Claude
  Code caches a plugin by version.
- The Mac app ships `Bundle/board` when `bin/project` finds it. `Bundle/` is
  not committed.
- `Install/test` installs `Bundle/board` into a scratch home, with a stub
  `claude`, and checks the links, binaries, refusals and enabled plugins.

## Not built

- The hook commands are tested only against a stub `claude`, so nothing
  checks that the real `claude` accepts them.
