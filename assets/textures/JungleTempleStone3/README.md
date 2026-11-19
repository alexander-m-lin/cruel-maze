# JungleTempleStone3 variations

Wall texture variations that all tile with each other, made from the `JungleTempleStone3`
MaterialVariant (base material Cobblestone, pattern Regular, 10 studs per tile), which the
maze walls currently use.

| Folder | What it is |
|---|---|
| `original/` | The `JungleTempleStone3` maps as uploaded (pulled back out of Studio) |
| `var1/` - `var4/` | Variations: same outer border as the original, new stonework inside |
| `preview_mosaic.png` | A 4x4 wall of random picks from the original and var1-4 |

Each folder has `color.png`, `normal.png`, `rough.png` and `metal.png` (512x512; metalness is
all black, the same for every variation).

## How they were made

1. Four new textures were generated with the original's prompt.
2. `tools/textures/variants.py` kept the original's outer border and filled the interior from
   one new texture each. The join is a minimum-difference seam that prefers dark mortar gaps,
   so whole stones are kept where possible. The outer 16 px are exactly the original's.

Because every variation shares the original's border, any two of them placed side by side
meet the way the original meets itself. A few interior seams still clip a stone. Rerun the
script with different settings (`BAND`, `DARK`, `FEATHER`) or new sources to change them.

## Using them

1. **Upload:** in Studio, add a MaterialVariant per folder (base material Cobblestone,
   StudsPerTile 10) and import its colour, normal, roughness and metalness maps. New images
   need Roblox moderation before they load.
2. **Build walls in whole tiles.** Roblox starts a part's texture at the part's own corner. It
   does not line up with neighbouring parts (tested 2026-11-18: one wall split at an odd
   point shows a visible jump). So a variation only joins seamlessly when each wall piece is
   a whole number of tiles long and tall: multiples of 10 studs at StudsPerTile 10. Today's
   walls are 22 studs long and overlap at the corners, so MazeBuilder needs a change first.
   One option is panels on the tile grid with corner posts.
3. Then pick a variation at random for each wall piece.
