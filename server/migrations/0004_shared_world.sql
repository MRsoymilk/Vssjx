ALTER TABLE characters ADD COLUMN owner_epoch BIGINT NOT NULL DEFAULT 0 CHECK (owner_epoch >= 0);
ALTER TABLE characters ADD COLUMN position_revision BIGINT NOT NULL DEFAULT 0 CHECK (position_revision >= 0);
CREATE TABLE world_tickets (
    digest BYTEA PRIMARY KEY CHECK (octet_length(digest)=32),
    session_id UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    character_id UUID NOT NULL REFERENCES characters(id),
    expires_at TIMESTAMPTZ NOT NULL,
    UNIQUE (session_id)
);
