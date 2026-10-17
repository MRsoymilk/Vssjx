-- Defeated bits are quest history. Missing deadlines let legacy kills respawn.
ALTER TABLE characters ADD COLUMN monster_respawns JSONB NOT NULL DEFAULT '{}'::jsonb
    CHECK (jsonb_typeof(monster_respawns) = 'object');
