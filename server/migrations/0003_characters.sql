CREATE TABLE characters (
    id UUID PRIMARY KEY,
    account_id UUID NOT NULL UNIQUE REFERENCES accounts(id),
    display_name TEXT NOT NULL CHECK (char_length(display_name) BETWEEN 2 AND 12),
    name_key TEXT COLLATE "C" NOT NULL UNIQUE,
    name_rules_version TEXT NOT NULL CHECK (name_rules_version = 'nickname-v1'),
    rules_version TEXT NOT NULL CHECK (rules_version = 'creation-v1'),
    job SMALLINT NOT NULL CHECK (job BETWEEN 0 AND 2),
    gender SMALLINT NOT NULL CHECK (gender BETWEEN 0 AND 1),
    school SMALLINT NOT NULL CHECK (school BETWEEN 0 AND 2),
    level INTEGER NOT NULL DEFAULT 1 CHECK (level BETWEEN 1 AND 50),
    xp INTEGER NOT NULL DEFAULT 0 CHECK (xp >= 0),
    gold INTEGER NOT NULL DEFAULT 30 CHECK (gold >= 0),
    hp INTEGER NOT NULL CHECK (hp > 0),
    mp INTEGER NOT NULL CHECK (mp >= 0),
    quest_stage INTEGER NOT NULL DEFAULT 0 CHECK (quest_stage >= 0),
    map_id TEXT NOT NULL DEFAULT 'qingyun_trail',
    cell_x INTEGER NOT NULL DEFAULT 10 CHECK (cell_x BETWEEN 0 AND 31),
    cell_y INTEGER NOT NULL DEFAULT 16 CHECK (cell_y BETWEEN 0 AND 31),
    state_revision BIGINT NOT NULL DEFAULT 1 CHECK (state_revision > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (display_name COLLATE "C" ~ '^[A-Za-z0-9_一-鿿]+$'),
    CHECK (name_key = translate(display_name, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'))
);

CREATE TABLE inventory_items (
    id UUID PRIMARY KEY,
    character_id UUID NOT NULL REFERENCES characters(id),
    definition_id TEXT NOT NULL CHECK (definition_id IN ('potion', 'sword')),
    quantity INTEGER NOT NULL CHECK (quantity BETWEEN 1 AND 99),
    equipped BOOLEAN NOT NULL DEFAULT FALSE,
    UNIQUE (character_id, definition_id),
    CHECK (NOT equipped OR (definition_id = 'sword' AND quantity = 1))
);

CREATE TABLE account_operation_receipts (
    account_id UUID NOT NULL REFERENCES accounts(id),
    operation_id UUID NOT NULL,
    operation_type TEXT NOT NULL CHECK (operation_type = 'character.create'),
    request_digest BYTEA NOT NULL CHECK (octet_length(request_digest) = 32),
    http_status SMALLINT NOT NULL CHECK (http_status IN (201, 409, 422)),
    result JSONB NOT NULL CHECK (jsonb_typeof(result) = 'object'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (account_id, operation_id)
);
