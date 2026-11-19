-- What the fog of war knows, shared with other scripts on this player's computer (the minimap).
-- The FogOfWar script fills it in; others only read it.
--
--   tiles[x][z]  - one per fog tile: .explored (seen at some point), .onWall (a wall is there)
--   visible      - { [tile] = true } for tiles in view right now (yours and your team's)
--   count        - tiles along each side; tile (x, z) covers world X from (x-1)*tileSize - half
--   tileSize, half (half the maze's width, in studs)
--   maze         - the maze model these belong to (nil until the first fog is built)

return {
	tiles = nil,
	visible = {},
	count = 0,
	tileSize = 2,
	half = 0,
	maze = nil,
}
