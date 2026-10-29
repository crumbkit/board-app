# App icon: more cases

Learned converting Onyx (XcodeGen, 4 icon designs, 20 color themes) to
Icon Composer, October 2026.

## Contents

- Xcode or XcodeGen app
- Convert a flat icon
- Layer tricks

## Xcode or XcodeGen app

No `build.sh` or `make_icon.sh` needed: Xcode 26 compiles a `.icon` on its own.

1. Put `AppIcon.icon` anywhere inside the target's sources (Onyx uses
   `Onyx/Resources/AppIcon.icon`). XcodeGen 2.46 adds it as a `wrapper.icon`
   resource; in Xcode, drag it into the target.
2. Delete `AppIcon.appiconset` from the asset catalog. Two icons named
   AppIcon clash.
3. Keep `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`.

Check: the built app's `Contents/Resources` has `Assets.car` and
`AppIcon.icns`, and its `Info.plist` has `CFBundleIconName` = `AppIcon`.

## Convert a flat icon

A flat icon (an `.icns`, PNGs, or SVGs with the body drawn in) becomes
layers:

- Keep only the shapes: the object, its parts, the accent. Drop the rounded
  body, drop shadows, the rim light, sheens, glows, and inner blurs. The
  background color moves to `fill`.
- Art drawn inside the old 824 px body keeps its coordinates. Give the group
  `"position": {"scale": 1.2427, "translation-in-points": [0, 0]}` and it
  fills the square (1024 / 824).
- One shape per layer when it should catch its own light (a ball and a
  panel in front of it). Shapes that never overlap can share a layer.

## Layer tricks

- SVG `linearGradient` fills render fine in a layer. Put one gradient per
  shape for the accent.
- A different file per appearance:
  `"image-name-specializations": [{"value": "card.svg"}, {"appearance": "dark", "value": "card-dark.svg"}]`.
  Use it when grays that read on white vanish on the dark body.
- A different background per appearance:
  `"fill-specializations": [{"value": {...}}, {"appearance": "dark", "value": {...}}]`.
- A frosted panel in front of a colored shape: a white layer at
  `"opacity": 0.75` with glass on, listed above the colored layer.
