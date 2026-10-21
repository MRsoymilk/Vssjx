ALTER TABLE characters ADD COLUMN endless_state JSONB NOT NULL DEFAULT '{"stage":1,"best":0,"level":0,"in_progress":false}'::jsonb;
ALTER TABLE characters ADD CONSTRAINT characters_endless_state_object CHECK (jsonb_typeof(endless_state) = 'object');
