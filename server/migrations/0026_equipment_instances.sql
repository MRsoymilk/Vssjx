-- New instances coexist with legacy fixed inventory; ownership remains character-scoped.
ALTER TABLE characters ADD COLUMN loot_state JSONB NOT NULL DEFAULT '{}'::jsonb CHECK(jsonb_typeof(loot_state)='object');
