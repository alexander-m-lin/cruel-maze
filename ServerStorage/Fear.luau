-- FEAR (Fear Eater's Instill Fear): marking a survivor as feared. Shared by the ability
-- (HeroAbilities.FearEater) and the dev Sandbox's "feared" spawns, so both are the same thing.
--
--   Fear.apply(survivor, def[, at])   -- def: Instill Fear's numbers (fearTime, fearSlow); at: server time
--
-- Feared = "FearedUntil" (server time), "FearSlow" (Movement slows them) and "RevealedUntil" (the
-- monster side sees them). Any dread they had is over.

local Fear = {}

function Fear.apply(survivor, def, at)
	at = at or workspace:GetServerTimeNow()
	survivor:SetAttribute("DreadUntil", nil)
	survivor:SetAttribute("FearSlow", def.fearSlow)
	survivor:SetAttribute("FearedUntil", math.max(survivor:GetAttribute("FearedUntil") or 0, at + def.fearTime))   -- (never shortened)
	survivor:SetAttribute("RevealedUntil", math.max(survivor:GetAttribute("RevealedUntil") or 0, at + def.fearTime))
end

return Fear
