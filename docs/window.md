# Board window

The Mac app's window shows what Board relays and what waits for the owner.
It answers nothing: the owner answers on the iPhone or with `board answer`.
Closing it stops nothing. A click on the Dock icon, or Open Board Window in
the menu bar item's menu, opens it again.

## Relay

The app starts the relay when it launches, beside the launcher, and runs it
until the app quits ([sync](sync.md)). The relay keeps what the window
shows: the requests waiting, when iCloud first held each one, when it last
shared, and why the last share failed. Board.app does not start at login,
so after a restart nothing is shared until the owner opens it.

## Sidebar

- Waiting: the requests in the personal board's `effects/pending/`, one per
  thread, by board, as the iPhone inbox words them. A row says whether
  iCloud holds the request, or that no iPhone is paired, and shows the
  owner's latest reply.
- Answered: the records committed under `effects/seen/` in the last 7 days,
  with each effect from `effects/answered/`. An approval names the paired
  iPhone whose key its signature carries. Board checked the signature; the
  window only reads which key it names.
- iPhones: each device with a line in either allowed signers file
  ([security](security.md)). Its page shows what it may approve, read from
  the namespaces of its lines, its key's fingerprint and its lines. Pair
  Again to Change opens pairing, which replaces the lines. Remove iPhone
  deletes them after Touch ID ([devices](devices.md)).
- The footer says whether the relay is sharing and when it last did. When
  iCloud fails, a banner says what to do; when no iPhone is paired, a
  banner offers Add iPhone.

## Toolbar

The search button opens the launcher ([launcher](launcher.md)). Add iPhone
opens pairing as a sheet ([devices](devices.md)). The sheet's Cancel closes
it, and it closes once a phone is added.

## Installing Board

When the app launches and `~/.local/share/board/current` does not name the
release the app carries ([bundle](bundle.md)), the window opens with a
sheet. It waits while the pairing sheet is open.

- With no release installed, it offers Install Board on this Mac: the
  binaries, the skills and the plugins. When Board's config names no
  personal board, it shows the Board folder, `~/Board` until Choose…
  picks another in a folder picker that can create one, with the reason
  the installer would refuse it. When git also lacks a name or email, a
  "Your name for commits" section asks for them, filled with any value
  set. When a value is unset and the global git config has an
  `[includeIf]` section that may set it, the section shows the installer's
  refusal instead of its explanation and the fields. Install
  stays disabled until the folder passes and both are valid.
- With another release installed, it offers Update Board: both releases'
  crumbkit/board commits and dates, what the update replaces, updates and
  enables, that installed Claude Code mods are updated and keep their on or
  off state, and the boards that still name `controls`, with Open Migration
  Guide. A Removes row shows when one of the Python attention plugin's
  links exists. With no personal board it shows the folder picker below
  the box, and the identity section.
- Install or Update gets the PATH from the person's login shell (`$SHELL
  -l -c`, five seconds at most), then runs `install` through the one
  runner, with `--board-folder` when there is no personal board and only
  the git values git lacks. It never passes `--hooks`. When the shell
  fails, it runs with `~/.local/bin` before the app's PATH, and says so.
- While it runs, the sheet shows steps 1 to 6 and the installer's output.
  Afterwards it shows what each step did, with a warning sign on a step
  that left something for the person, and "Start a new Claude Code session
  to load the updated mods" when step 6 updated one; or why the install
  stopped, what that left behind, Show in Finder, Close and Try Again.
- Not Now closes the sheet until the next launch. Until the release is
  installed, the menu bar icon has a dot in the accent colour and the menu
  has Install Board… or Update Board…, which shows the sheet again.
- Quitting the app while it installs stops the installer and everything it
  started. `current` moves only at the end, so the sheet shows again on the
  next launch.

## Phone names

At pairing the Mac keeps the name the phone gave and the time, in its own
defaults. They are shown and never trusted: what a phone may sign comes
from the two files alone. A phone paired before the Mac kept names shows as
"iPhone" and the first 8 characters of its id until it pairs again.
