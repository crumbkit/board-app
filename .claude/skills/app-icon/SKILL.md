---
name: app-icon
description: Make or change Board.app's Liquid Glass app icon, an Icon Composer file at Apps/Shared/AppIcon.icon that both the iPhone and Mac apps use. Use when asked for an app icon, icon concepts, or a change to the icon.
---

# App icon

The icon is an Icon Composer file in git: `Apps/Shared/AppIcon.icon`, a
folder with `icon.json` and SVG layers in `Assets/`. You write both by hand.
The system adds the glass, highlights, shadow, mask, and the dark, tinted
and clear looks. Never draw those yourself.

Nothing visual reaches Board.app until the owner signs off its design. The icon
is no exception: the contact sheets go to him before the icon is added to
the targets.

- `tools/validate` checks `icon.json` against Icon Composer's schema and
  checks that every layer has a file.
- `tools/review` renders the icon with `ictool` into one contact sheet per
  platform.
- `reference/icon-format.md` documents every `icon.json` key, the
  specializations and the gotchas. `reference/more-cases.md` covers
  converting a flat icon and other cases.
- `NOTICE.md` says where these files come from.

## What makes it look like Apple made it

1. One idea. One object that says what Board does.
2. No text, no letters, no screenshots of the UI.
3. Your own drawing. Never an SF Symbol or a shape that looks like one: the
   SF Symbols licence forbids symbols in app icons.
4. Two or three layers, each one flat shape in white or one tint. Glass
   gives the depth. The main shape on top, a softer one behind.
5. A large glyph: about 45 to 55 percent of the canvas width. Thin parts
   vanish at 16 px.
6. Filled shapes only. A stroke on an open path leaves a faint glass line.
7. One background hue. `automatic-gradient` looks right almost every time.

## The file

```json
{
  "fill" : { "automatic-gradient" : "srgb:0.20000,0.42000,0.96000,1.00000" },
  "groups" : [
    {
      "layers" : [
        { "glass" : true, "image-name" : "front.svg", "name" : "front" },
        { "glass" : true, "image-name" : "back.svg", "name" : "back", "opacity" : 0.6 }
      ],
      "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
      "translucency" : { "enabled" : true, "value" : 0.5 }
    }
  ],
  "supported-platforms" : { "squares" : "shared" }
}
```

- `"squares": "shared"` makes one icon for the iPhone and the Mac.
- The first layer in the list sits on top.
- A look per appearance goes in `<key>-specializations`, such as
  `fill-specializations` with an entry for `dark`.
- The art fills the whole 1024 × 1024 square. Never draw the rounded
  square, a margin, a shadow or a sheen.

## Steps

1. Write three concepts in one line each: the object, the background colour,
   the layers. Pick one with the owner.

   Check: one concept is chosen and it uses no SF Symbol.

2. Write the layers as SVG files in `Apps/Shared/AppIcon.icon/Assets/`, on a
   1024 × 1024 canvas, as white filled shapes (`rect` with `rx`, `circle`,
   `path`). Write `icon.json` to list them. Delete layer files you no
   longer use.

3. Validate. The script needs `uv` on `PATH`:

   ```bash
   .claude/skills/app-icon/tools/validate
   # VALID: …/Apps/Shared/AppIcon.icon/icon.json
   ```

4. Review every look on both platforms:

   ```bash
   .claude/skills/app-icon/tools/review
   # wrote …/AppIcon-macOS.png
   # wrote …/AppIcon-iOS.png
   ```

   Read both PNGs. For an icon with no per-platform layers they are the
   same, so read one. The glyph reads in every look and is still recognisable
   at 16 px. If not, make it bigger, bolder or simpler. Change one thing per
   round, two or three rounds.

5. Send both contact sheets to the owner for sign-off. Stop until he signs off.

6. Once signed off, set `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` in
   each target's settings in `project.yml`. Both targets already list
   `Apps/Shared` as a source, so do not add the `.icon` again. Xcode
   compiles the `.icon` itself.

## Gotchas

- The folder must be named `AppIcon.icon`.
- A missing layer file: `ictool` still exits 0 and renders an empty
  background. Validate before you review.
- PDF layers do not render. Use SVG or PNG.
- `xcrun ictool` is a different tool. Icon Composer's `ictool` lives at
  `$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool`.
- Not yet checked in a build: how Xcode makes the older-style icon for
  iOS 17 and macOS 14 from the `.icon`.
