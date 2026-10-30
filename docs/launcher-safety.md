# Launcher safety

A provider names commands, URLs and files. These rules limit what Board.app
does with them.

## What runs

- Board.app's own code never answers a Board request and never signs. It
  may open the signing window, where the owner signs with Touch ID.
- A provider's actions are the owner's own commands. Board.app runs them
  because the owner wrote them into the config, and they run as the owner.
- Every command runs from argv, with no shell. The contract refuses an
  argv whose first element is not an absolute path.
- Each command runs in a process group of its own. A command that passes
  a limit is sent SIGTERM, with everything it started, and SIGKILL a
  second later.
- Listing, parts and preview commands stop after 5 seconds or 1 MB of
  output. An action's command stops after 10 minutes or 1 MB.
- An action that fails shows at the top of the next open, marked Failed,
  with ↩ for its command and output. It stays until the next action runs.
- The log names the provider or the action and the outcome. It never holds
  a command line or its output.

## What opens

- An `open` action, and a link in a Markdown preview, open only http and
  https URLs. The contract refuses any other scheme.
- ↩ on an evidence file opens it in its default app. A file with the
  execute bit, a script, an app bundle or anything that is not a regular
  file is shown in Finder instead, so ↩ never launches it.
- The preview reads only regular files, never through a symlink, and at
  most 1 MB of text.
- The size and SHA-256 an evidence row shows are what the provider
  reported. Board.app does not check them.

## The config file

Board.app opens `~/.config/board/launcher.json` without following a
symlink, and checks and reads the one open file. It refuses the file when
it is not a regular file, belongs to another user, or the group or others
can write it. It also refuses two providers with one name. The panel says
why.

## Sandboxing

Board.app is not sandboxed. Sandboxing it would break providers: a
sandboxed app cannot run the owner's commands.
