-- THE HEROES: who each character is and what their abilities do, shared by the server (which
-- carries abilities out and keeps cooldowns: Abilities) and players' computers (the ability bar,
-- the effects).
--
-- Every hero, survivor or monster, has three ability slots:
--   Primary   - right mouse button for survivors (their left click collects relics); LEFT for
--               monsters (AbilityControls)
--   Secondary - Q
--   Ultimate  - E
--
-- A player's hero is their "Hero" attribute (set by Match). Survivors' heroes are all different in a
-- match (the one picked in the lobby, "PreferredHero", if it's free; Heroes.survivorIds), repeating
-- only while there are fewer survivor heroes than survivors. Monsters are Config.DEFAULT_MONSTER_HERO.
-- A monster's body carries its hero in a "Hero" attribute too.
--
-- ADDING A HERO: one module per place, all named after the hero's id (e.g. "FearEater"):
--   ReplicatedStorage.HeroData.<Id>          -- who they are and their numbers (tune here)
--   ServerStorage.HeroAbilities.<Id>         -- what the abilities do (server)
--   StarterPlayerScripts.HeroVisuals.<Id>    -- how they look and sound (players' computers);
--                                               for a monster, also how its body moves
-- then add the id to Heroes.ORDER below. A monster hero also names its body ("rig", a model in
-- ServerStorage). See the README's "Heroes" section.

local Heroes = {}

Heroes.SLOTS = { "Primary", "Secondary", "Ultimate" }
Heroes.KEYS = { Primary = "RMB", Secondary = "Q", Ultimate = "E" }   -- (a monster's Primary: "LMB")
Heroes.ORDER = { "Sara", "Kai", "FearEater" }

Heroes.list = {}
local folder = script.Parent:WaitForChild("HeroData")
for _, id in Heroes.ORDER do
	local hero = require(folder:WaitForChild(id))
	hero.id = id
	Heroes.list[id] = hero
end

-- The survivor heroes, in ORDER
function Heroes.survivorIds()
	local ids = {}
	for _, id in Heroes.ORDER do
		if Heroes.list[id].role == "Survivor" then table.insert(ids, id) end
	end
	return ids
end

function Heroes.get(id)
	return id and Heroes.list[id] or nil
end

return Heroes
