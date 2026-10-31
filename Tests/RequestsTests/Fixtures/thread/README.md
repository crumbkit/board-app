# Thread fixture

`thread.json` is what `board call requests.thread --effect <id> --json`
printed, at crumbkit/board 11ce4f56, for the latest version in a scratch board
that `make-board.py` filled:

- version 1, answered with a refusal and a reason, under `/effects/answered/`;
- version 2, pending and replaced;
- version 3, pending and latest;
- a reply to version 1 and a reply to version 2.

`latest.effect.json` and `replaced.effect.json` are versions 3 and 2 as Board
committed them. To regenerate: `git init`, `board init`, run
`python3 make-board.py .`, `board plugin enable requests`, commit, and run the
call again with version 3's id.
