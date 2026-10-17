-- Attribution deliberately survives session expiry/deletion. Never store bearer tokens,
-- password hashes, raw requests or chat text in this ledger.
CREATE TABLE security_audit (
    id BIGSERIAL PRIMARY KEY,
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    account_id UUID,
    character_id UUID,
    session_id UUID,
    operation_id UUID,
    action VARCHAR(64) NOT NULL,
    outcome TEXT NOT NULL CHECK (outcome IN ('accepted','rejected','replayed','observed')),
    code VARCHAR(64) NOT NULL,
    details JSONB NOT NULL CHECK (jsonb_typeof(details) = 'object' AND octet_length(details::text) <= 16384)
);
CREATE INDEX security_audit_account ON security_audit(account_id, id DESC);
CREATE INDEX security_audit_character ON security_audit(character_id, id DESC);
CREATE INDEX security_audit_time ON security_audit(created_at);
CREATE FUNCTION security_audit_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'security audit is append-only'; END $$;
CREATE TRIGGER security_audit_immutable BEFORE UPDATE OR DELETE ON security_audit
    FOR EACH ROW EXECUTE FUNCTION security_audit_immutable();

-- A shared database budget survives reconnects and multiple server processes.
CREATE TABLE gameplay_budgets (
    account_id UUID PRIMARY KEY REFERENCES accounts(id),
    window_start TIMESTAMPTZ NOT NULL,
    requests INTEGER NOT NULL CHECK (requests BETWEEN 1 AND 181)
);
CREATE TABLE operator_receipts (
    operation_id UUID PRIMARY KEY,
    request_digest BYTEA NOT NULL CHECK (octet_length(request_digest) = 32),
    result JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);
