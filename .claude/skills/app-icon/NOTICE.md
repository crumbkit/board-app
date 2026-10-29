# Sources

This skill copies files from two projects, unchanged unless noted.

- giginet/apple-icon-composer-skill at 43b96bf2, Apache-2.0 (LICENSE.apache-2.0):
  - `tools/icon-schema.json` and `tools/validate_icon.py`, unchanged.
  - `reference/icon-format.md` is adapted from its compose-app-icon SKILL.md:
    the frontmatter, the `uv` setup and the `create_icon.py` workflow are
    removed, and the validation section names `tools/validate`.
- daveebbelaar/bama at 15356bd8, MIT (LICENSE.mit), Copyright (c) 2026 Dave Ebbelaar:
  - `tools/icon_sheet.swift`, with its comment naming `tools/review`.
  - `reference/more-cases.md`, without its section on Dock icons that change.
  - `tools/review` is adapted from its `icon_review.sh`: it renders iOS as
    well as macOS, renders 16 px at 1x, and reads Board's icon path.
  - SKILL.md here is written for Board and follows its app-icon skill's method.
