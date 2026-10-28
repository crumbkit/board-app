# Board.app

Board.app is the app that ships Board on the Mac, iPhone and iPad. Today it
holds `attention-sign`, the Touch ID window in which the owner signs
directives and Board approvals, and pairing of a phone with the Mac.

No screen is added unless the owner has signed off its design.
Agents never ship or install builds of the iPhone app, so never run
`bin/install-phone`; the owner installs them, through `bin/setup`.

## Docs

DOCS.md maps the docs in docs/. They say what is built. When a change lands,
update the doc it changes.

## What comes next

The phone will show pending requests and approve them with Face ID. Board.app
will carry the `board` binary, every Board plugin at its latest
version, their skills and hooks, and a skill that installs or updates them
on a Mac. None of that is built yet.

## Gates

Run `bin/lint` and `bin/test` before every push. CI runs both on macOS. They
cover the Swift package only; the apps build through `bin/install-phone` and
`bin/install-mac`.

## Writing

Use short sentences and plain words. Comments describe the code as it is.
