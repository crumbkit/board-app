# Effect fixtures

Each `<name>.statement` is what board's `board_model::Effect::approval`
printed for `<name>.effect.json`, at board 492317cd, through a program that
reads the effect on stdin and writes `effect.approval()` to stdout unchanged.
`vector.*` is board's `vectors/signing/v1` approval pair. `<name>.prior` is
the blob the effect's `prior` names. Regenerate a statement only from board's
code, never from this repository's.
