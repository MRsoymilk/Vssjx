CREATE TABLE equipment_trades (
    id uuid PRIMARY KEY,
    sender uuid NOT NULL REFERENCES characters(id),
    recipient uuid NOT NULL REFERENCES characters(id),
    status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','active','completed','cancelled','expired')),
    offers jsonb NOT NULL,
    revision bigint NOT NULL DEFAULT 1,
    expires_at timestamptz NOT NULL DEFAULT clock_timestamp()+interval '10 minutes',
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CHECK(sender<>recipient)
);
CREATE INDEX direct_trade_sender ON equipment_trades(sender,status);
CREATE INDEX direct_trade_recipient ON equipment_trades(recipient,status);
CREATE INDEX direct_trade_expiry ON equipment_trades(expires_at) WHERE status IN ('pending','active');
