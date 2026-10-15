CREATE TABLE accounts (
    id UUID PRIMARY KEY,
    username VARCHAR(32) NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    disabled BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (username ~ '^[a-z0-9_]{3,32}$')
);

CREATE TABLE sessions (
    id UUID PRIMARY KEY,
    account_id UUID NOT NULL REFERENCES accounts(id),
    access_digest BYTEA NOT NULL UNIQUE CHECK (octet_length(access_digest) = 32),
    refresh_digest BYTEA NOT NULL UNIQUE CHECK (octet_length(refresh_digest) = 32),
    access_expires_at TIMESTAMPTZ NOT NULL,
    refresh_expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX sessions_account_id ON sessions(account_id);
CREATE INDEX sessions_expiry ON sessions(refresh_expires_at);
