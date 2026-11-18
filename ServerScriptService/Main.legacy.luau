-- Starts the game on the server. The real work lives in modules:
--   ServerStorage.Match       - runs matches one after another (lobby, countdown, play, results)
--   ServerStorage.MazeBuilder - generates and builds each maze
--   ServerStorage.MonsterAI   - the AI monsters
--   ReplicatedStorage.Config  - settings shared with players' computers

local Match = require(game:GetService("ServerStorage").Match)

Match.run()
