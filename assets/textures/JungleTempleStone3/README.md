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

## In the game

Uploaded 2026-11-18 as MaterialVariants `JungleTempleStone3_V1`..`V4` (in
`MaterialService.WallVariations`, base Cobblestone, 10 studs per tile; metalness reuses the
original's map). MazeBuilder's `WALL_VARIANTS` lists them with the original, and each wall panel
picks one at random.

| Variant | Colour | Normal | Roughness |
|---|---|---|---|
| V1 | 79252408532207 | 118563323434796 | 135625723940166 |
| V2 | 113602389430361 | 88631979324847 | 138431187460297 |
| V3 | 117869914617965 | 135022853640135 | 95960798928170 |
| V4 | 78321734725827 | 84085364297526 | 80134679172251 |

The variations only join seamlessly because MazeBuilder builds walls as panels exactly one cell
(20 studs, 2 tiles) long, with posts at corners. Roblox starts a texture afresh at each part's
corner and does not line it up with neighbouring parts (tested 2026-11-18). Keep wall pieces a
whole number of tiles long and tall if the wall building changes.
