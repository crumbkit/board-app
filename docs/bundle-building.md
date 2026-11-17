# Building a release

- `bin/bundle [board-ref]` writes `Bundle/board`. The ref defaults to
  `origin/main` of the crumbkit/board checkout at `~/Code/crumbverse/board`;
  `BOARD_SRC` names another. It reads the checkout through git, so its
  working tree does not matter. It refuses to run while `Sources/`,
  `Install/`, `Package.swift` or `Package.resolved` has uncommitted changes.
- It needs cargo, jq, rsync, the Swift toolchain and `claude`, which
  validates each mod and the marketplace.
- It gives each mod the version `<version>+<board commit>`, because Claude
  Code caches a plugin by version.
- The Mac app ships `Bundle/board` when `bin/project` finds it. `Bundle/` is
  not committed.
- `Install/test` installs `Bundle/board` into scratch homes, with a scratch
  git identity and a stub `claude`. It covers a fresh home, a home with the
  Python attention plugin's links and an older release, a home where
  `board-controls` is installed, a board that still names `controls`, the
  `::` lines, and each refusal. `bin/test` runs it when `Bundle/board`
  exists. CI does not, because it has no bundle: `bin/bundle` needs
  crumbkit/board's source from GitHub, cargo and `claude`.

## Not built

- The mod commands are tested only against a stub `claude`, so nothing
  checks that the real `claude` accepts them.
