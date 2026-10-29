# Board.app

Board.app is the app that ships Board on the Mac, iPhone and iPad. Today it
holds `attention-sign`, the Touch ID window in which the owner signs
orders and Board approvals, and pairing of a phone with the Mac.

No screen is added unless the owner has signed off its design.
Agents never ship or install builds of the iPhone app, so never run
`bin/install-phone`; the owner installs them, through `bin/setup`.

## Docs

DOCS.md maps the docs in docs/. They say what is built. When a change lands,
update the doc it changes.

## What comes next

The phone will show pending requests and approve them with Face ID. That is
not built yet. The Mac app already carries a Board release; see
docs/bundle.md.

## Gates

Run `bin/lint` and `bin/test` before every push. CI runs both on macOS. They
cover the Swift package only. CI also builds both apps unsigned with
`bin/build-apps`; run it before a push that changes `Apps/` or `project.yml`.

## Writing

Use short sentences and plain words. Comments describe the code as it is.
