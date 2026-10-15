ALTER TABLE characters ADD COLUMN defeated_mask INTEGER NOT NULL DEFAULT 0 CHECK (defeated_mask BETWEEN 0 AND 15);
CREATE TABLE pve_battles (
    id UUID PRIMARY KEY,
    character_id UUID NOT NULL REFERENCES characters(id),
    rules_version TEXT NOT NULL CHECK (rules_version='qingyun-pve-v1'),
    state JSONB NOT NULL CHECK (jsonb_typeof(state)='object'),
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX one_active_pve_battle ON pve_battles(character_id) WHERE active;
ALTER TABLE characters ADD COLUMN active_battle_id UUID REFERENCES pve_battles(id);
CREATE TABLE pve_operation_receipts (
    character_id UUID NOT NULL REFERENCES characters(id),
    operation_id UUID NOT NULL,
    request_digest BYTEA NOT NULL CHECK (octet_length(request_digest)=32),
    result JSONB NOT NULL CHECK (jsonb_typeof(result)='object'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY(character_id, operation_id)
);
