-- A refresh racing logout must not turn logout into a false success.
-- Previous, unexpired access tokens may revoke their session but never read it.
CREATE TABLE session_access_history (
    access_digest BYTEA PRIMARY KEY CHECK (octet_length(access_digest) = 32),
    session_id UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    expires_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX session_access_history_session ON session_access_history(session_id);
INSERT INTO session_access_history (access_digest, session_id, expires_at)
SELECT access_digest, id, access_expires_at FROM sessions;
