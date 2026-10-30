# Launcher

The launcher is a search panel in Board.app on the Mac. ⌃⌥Space, or a
click on Board's menu bar item, opens it. Board.app keeps its Dock icon.

Providers fill it. A provider is a command that prints items as JSON.
[The contract](launcher-contract.md) says what a provider prints.
[Providers](launcher-providers.md) says how to set one up and write one.

## Using it

- The panel opens in the upper third of the screen with the mouse. It
  takes the keyboard without bringing Board.app forward.
- Typing filters the list. Every word must appear in an item's title,
  subtitle or keywords.
- ↑ and ↓ move the selection. The right pane shows the selected item.
- ↩ opens an item that has parts or more than two actions, and shows its
  actions, evidence, test runs and commits. ⌘↩ then runs its first
  action. On any other item, ↩ runs its first action and ⌘↩ its second.
- Esc, or Backspace in an empty field, goes back. Esc at the top closes
  the panel. So does losing focus, and any action that opens something.
- Inside an item, the sidebar button left of the field, or ⌃⌘S, hides
  or shows the list. Board.app remembers the choice.
- Space on an evidence file opens the preview window. ← and → move
  between the item's files, / searches them by name, ↩ opens the file in
  its default app, and Space or Esc closes the window. A program, script
  or app bundle is shown in Finder instead of opened. The window
  remembers its size and position.
- If another app holds ⌃⌥Space, Board.app logs it; the menu bar item
  still works.

## Safety

[Launcher safety](launcher-safety.md) says what Board.app runs, opens and
reads for a provider, and what it refuses.

Not built: actions that take input, nested items below parts, and
components supplied by plugins.
