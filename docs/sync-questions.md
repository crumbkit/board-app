# Sync: questions

Zone `Requests` also carries agents' questions to the phone and the owner's
answers back. An answer is not signed and needs no Face ID.

- Every 10 seconds the Mac app runs `board --personal call plans.open
  --limit 1000 --json` and shares each open question, mounted boards
  included, as a `Question` named by the git blob id of its path.
- A `Question` holds the string fields `plans.open` prints: `path`,
  `question`, `asked`, `session`, `recommendation`, `blocks`, `why`, `note`,
  `mount` and `contextPath`. `options` is a JSON array of `id` and `text`.
  `board` is the git remote of the mount's repository, from the mount's
  record, or else the mount's last segment, or with no mount the personal
  board's remote.
- The Mac saves a `Question` again only when a field changed, and deletes
  each one `plans.open` no longer lists. When `plans.open` fails, the shared
  questions stay as they were.
- The phone checks each `Question` against its record's name, so a record
  cannot show one question and answer another.
- The phone writes `QuestionAnswer`, named `qanswer-<question record name>`,
  with the `path`, the `option` id or `none` for "Something else", and the
  owner's `note`, which may be empty. It marks the row "Sending your answer…"
  before saving, so a second tap sends nothing, and clears the mark if the
  save fails. Otherwise the mark stays until the question leaves the list or
  Board refuses the answer. It logs each save and failed save, with the
  path, in `com.stemmacorp.board`, category `inbox`.
- The Mac runs `board --personal call plans.answer --path <path> --option
  <id> --written_by board-app/phone --json`, with `--words <note>` when the
  note is not empty; otherwise Board uses the option's text. The arguments
  are an argv array.
- When Board records the answer, the Mac deletes the `QuestionAnswer` and
  remembers it until the app quits. A later copy with the same name, option
  and note is deleted unrecorded, and logged as a dropped repeat. A
  different answer still goes to Board.
- When `plans.answer` refuses with a `plans::answer::` code, the Mac reads
  the `board/failure/v1` it prints and, in one save, deletes the answer and
  writes `QuestionRefused`, named `qrefused-<question record name>`, with the
  `question` record name, `code` and `message`. Any other failure leaves
  the answer in iCloud to try again.
- The phone shows each `QuestionRefused` once as an alert and deletes it.
  `plans::answer::already_answered` reads "Already Answered"; other codes
  show Board's message.
