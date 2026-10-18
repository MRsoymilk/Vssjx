-- AI generated layouts/quests are separate from recovered maps and the tutorial.
ALTER TABLE characters ADD COLUMN ai_progress jsonb NOT NULL DEFAULT '{"completed":[],"active":{},"respawns":{}}';
ALTER TABLE characters ADD CONSTRAINT characters_ai_progress_object CHECK(jsonb_typeof(ai_progress)='object' AND octet_length(ai_progress::text)<=65536);
ALTER TABLE characters DROP CONSTRAINT characters_playable_map_check;
ALTER TABLE characters ADD CONSTRAINT characters_playable_map_check CHECK (
  map_id IN ('qingyun_trail','ancient_ruins') OR
  CASE WHEN map_id ~ '^ai_[0-9]{3}$' THEN substring(map_id FROM 4)::integer BETWEEN 1 AND 214 ELSE FALSE END
);
