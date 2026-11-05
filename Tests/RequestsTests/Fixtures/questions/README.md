# Question fixtures

- `open-before-answer.json`: what `board call plans.open --json` printed for
  four questions under `/projects/` in the personal board, from a Board
  without `plans.answer`. It has no `why`, `note`, `mount` or
  `context_path`.
- `open.json`: the same four questions with those fields, filled from each
  question's record, as a Board with `plans.answer` prints them.
- `refused.json`: Board's failure for an answer to a question already
  answered, in the shape `board call --json` prints a failure.
