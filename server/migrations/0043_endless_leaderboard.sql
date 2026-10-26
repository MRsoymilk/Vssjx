CREATE TABLE endless_records (
    character_id UUID PRIMARY KEY REFERENCES characters(id) ON DELETE CASCADE,
    best INTEGER NOT NULL CHECK (best BETWEEN 1 AND 1000000),
    achieved_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX endless_records_ranking ON endless_records(best DESC, achieved_at, character_id);
-- Historical records have no achievement timestamp; retain them at migration time.
INSERT INTO endless_records(character_id,best)
SELECT id,(endless_state->>'best')::integer FROM characters
WHERE (endless_state->>'best')::integer>0;

CREATE TABLE endless_milestones (
    id BIGSERIAL PRIMARY KEY,
    character_id UUID NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    stage INTEGER NOT NULL CHECK (stage>=100 AND stage%10=0 AND stage<=1000000),
    display_name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    announced_at TIMESTAMPTZ,
    UNIQUE(character_id,stage)
);
CREATE INDEX endless_milestones_pending ON endless_milestones(id) WHERE announced_at IS NULL;
