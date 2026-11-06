# Sync: requests

Zone `Requests` carries pending effects and their threads to the phone, and
answers and replies back.

- The Mac app reads the committed files under `effects/pending/` in the
  personal board every 10 seconds from launch until it quits, whether or
  not its window is open. It shares each
  as a `Request` named by the effect id: the effect's bytes and the blob a
  put replaces, as assets, and the board's git remote, the commit time and
  the blob at the path now. It deletes requests no longer pending, and stamps `Shared`,
  named `mac`, with the time.
- Each `Request` also holds the thread, as an asset: what
  `board --personal call requests.thread --effect <id> --json` printed, with
  every version of the request and the owner's replies. `threadBlob`, its git
  blob id, tells the Mac when to save the record again. A Board without the
  requests plugin shares no thread, and the phone shows the request alone.
- The phone shows a thread once, by its latest version, when that version is
  shared too. Only the latest version can be approved, and the phone signs it
  from the `Request`'s own effect bytes, never from the thread.
- The phone shows a request only when its effect hashes to the record's
  name, and the old version only when it hashes to the blob the effect names. It writes `Answer`, named `answer-<id>`: approve with the armored
  signature, or refuse with an optional reason.
- A reply is `Reply`, named `reply-<effect id>-<time>`, with the effect id,
  the text and the time, such as `20261030T224454Z`. The Mac puts it with
  `board --personal put /requests/replies/<effect id>/<time> --expect none`, a
  `requests/reply/v1` record that needs no signature and names the effect as
  `sha256:<effect id>`, then deletes it, whether or not Board took it. That
  record needs a Board with crumbkit/board#117 or later. A reply approves and
  refuses nothing.
- The Mac runs `board --personal answer <id> approve --signature -` or
  `refuse --reason=…`, then deletes the answer and the request. When Board
  refuses the answer, or its request is no longer pending, the Mac deletes the
  answer alone.

Not built: push notifications.
