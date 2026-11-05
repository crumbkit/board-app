# Sync: questions

Zone `Requests` also carries the questions agents asked the owner to the
phone, and the owner's answers back. An answer is not signed, so it needs no
Face ID.

- Every 10 seconds, on the same loop that shares requests, the Mac app runs
  `board --personal call plans.open --limit 1000 --json`. It shares each open
  question as a `Question`, named by the git blob id of the question's path.
  That includes questions in mounted boards.
- A `Question` holds the fields `plans.open` prints as strings: `path`,
  `question`, `asked`, `session`, `recommendation`, `blocks`, `why`, `note`,
  `mount` and `contextPath`. `options` is a JSON array of `id` and `text`.
  `board` names the board: the git remote of the mount's repository, read
  from the mount's record in the personal board, or the mount's last
  segment when the Mac cannot read it. A question with no mount is named by
  the personal board's remote.
- The Mac saves a `Question` again only when a field changed, and deletes
  each `Question` that `plans.open` no longer lists. When `plans.open`
  fails, as on a Board without the plans plugin, the Mac leaves the shared
  questions as they were and relays requests as before.
- The phone checks each `Question` against its record's name, so a record
  cannot show one question and be answered as another.
- The phone writes `QuestionAnswer`, named `qanswer-<question record name>`,
  with the `path`, the `option` id or `none` for "Something else", and the
  owner's `note`, which may be empty.
- The Mac runs `board --personal call plans.answer --path <path> --option
  <id> --written_by board-app/phone --json`, with `--words <note>` when the
  note is not empty. Board then uses the option's text as the words. The
  arguments are an argv array, never a shell line.
- When Board records the answer, the Mac deletes the `QuestionAnswer`. When
  `plans.answer` refuses it with a `plans::answer::` code, the Mac reads the `board/failure/v1` that `--json`
  prints and, in the same save, writes `QuestionRefused`, named
  `qrefused-<question record name>`, with the `question` record name, the
  `code` and the `message`, and deletes the answer. Any other failure leaves
  the answer in iCloud to be tried again.
- The phone shows each `QuestionRefused` once as an alert, then deletes it.
  `plans::answer::already_answered` reads "Already Answered"; any other code
  shows Board's message.
- After Answer, the phone marks the question's row "Sending your answer…"
  until the question leaves the list or Board refuses the answer.
