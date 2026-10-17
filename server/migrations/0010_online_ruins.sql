-- Keep the first four defeat bits and existing characters unchanged.
ALTER TABLE characters DROP CONSTRAINT characters_defeated_mask_check;
ALTER TABLE characters ADD CONSTRAINT characters_defeated_mask_check CHECK (defeated_mask BETWEEN 0 AND 63);
ALTER TABLE characters ADD CONSTRAINT characters_playable_map_check CHECK (map_id IN ('qingyun_trail', 'ancient_ruins'));
