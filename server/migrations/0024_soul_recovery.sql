-- Preserve old living characters; death and recovery are one character transaction.
ALTER TABLE characters ADD COLUMN corpse JSONB DEFAULT NULL;
ALTER TABLE characters DROP CONSTRAINT characters_hp_check;
ALTER TABLE characters ADD CONSTRAINT characters_hp_check CHECK(hp >= 0);
ALTER TABLE characters ADD CONSTRAINT characters_soul_health_check CHECK(
    (corpse IS NULL AND hp > 0) OR
    (corpse IS NOT NULL AND hp = 0 AND jsonb_typeof(corpse) = 'object')
);
