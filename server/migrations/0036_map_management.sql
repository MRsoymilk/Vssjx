-- Operational configuration only; bundled terrain/art/quest identities stay immutable.
CREATE TABLE map_drafts (
    map_id text PRIMARY KEY,
    revision bigint NOT NULL CHECK (revision > 0),
    active_revision bigint NOT NULL DEFAULT 0,
    document jsonb NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE map_releases (
    revision bigserial PRIMARY KEY,
    map_id text NOT NULL,
    document jsonb NOT NULL,
    operation_id uuid NOT NULL UNIQUE,
    reason text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(map_id, revision)
);
CREATE TABLE map_active (
    map_id text PRIMARY KEY,
    revision bigint NOT NULL,
    FOREIGN KEY(map_id,revision) REFERENCES map_releases(map_id,revision)
);
CREATE TABLE map_operator_receipts (
    operation_id uuid PRIMARY KEY,
    request_digest bytea NOT NULL,
    result jsonb NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
