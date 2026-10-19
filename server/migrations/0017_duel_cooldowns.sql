-- Ordered pair: the rejected inviter must wait even after reconnect/server restart.
CREATE TABLE duel_invite_cooldowns (
    inviter_id uuid NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    target_id uuid NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    expires_at timestamptz NOT NULL,
    PRIMARY KEY (inviter_id, target_id),
    CHECK (inviter_id <> target_id)
);
CREATE INDEX duel_invite_cooldowns_expiry ON duel_invite_cooldowns(expires_at);
