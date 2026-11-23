-- PROTECTION from monsters' direct captures (a catch: Devour, the stand-in's lunge or touch). Shared
-- by the server (which refuses the catch: Abilities.refusesCatch) and players' computers (which
-- hide or mark accordingly). Environmental hazards (crushing walls) still get you.
--
--   Protection.deflecting(who)  -- Sara's Flourish, while she spins ("DeflectUntil", server time):
--                                  a catch is deflected (sparks), the monster isn't stunned by it
--   Protection.encrypted(who)   -- Kai's Encrypt ("EncryptedUntil"): uncatchable, and hidden from the
--                                  monster side (only circuit indicators show; see ServerStorage.Encrypt)
--   Protection.immune(who)      -- either
-- who: a player or a survivor bot (on the server, its bot object; on players' computers, its body)

local Protection = {}

function Protection.deflecting(who)
	return (who:GetAttribute("DeflectUntil") or 0) > workspace:GetServerTimeNow()
end

function Protection.encrypted(who)
	return (who:GetAttribute("EncryptedUntil") or 0) > workspace:GetServerTimeNow()
end

function Protection.immune(who)
	return Protection.deflecting(who) or Protection.encrypted(who)
end

return Protection
