# TempleFloor

The maze floor: muted grey temple flagstones.

| Folder | What it is |
|---|---|
| `raw/` | As generated (`TempleFloorSubtle` in the place: base Slate, pattern Regular) |
| `softened/` | After `tools/textures/soften.py`. This is what the game uses |

`soften.py` removes most of the moss (its green, shading and bumps), evens out the big
light/dark blotches that make each tile recognisable, flattens the surface relief and evens the
roughness. It blurs with wrap-around, so the texture still tiles. The settings are at the top of
the script.

## In the game

Uploaded 2026-11-18 as the MaterialVariant `TempleFloorSoft` in
`MaterialService.FloorVariations`: base Slate, **15 studs per tile** (bigger than the generated
10, so it repeats less often). Metalness reuses the generated map. MazeBuilder's `FLOOR_VARIANT`
uses it for the maze floor and the spawn-room floors, tinted with `FLOOR_COLOR`.

| Map | Asset id |
|---|---|
| Colour | 96446933170433 |
| Normal | 80883530991122 |
| Roughness | 127966689620546 |
