-- One account counts once per Beijing calendar day, regardless of characters/reconnects.
CREATE TABLE daily_online_accounts (
    day DATE NOT NULL,
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    PRIMARY KEY (day, account_id)
);
CREATE TABLE online_stats_metadata (
    singleton BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (singleton),
    started_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);
INSERT INTO online_stats_metadata(singleton) VALUES(TRUE);

-- Historical observations are lower bounds, not invented complete attendance.
INSERT INTO daily_online_accounts(day,account_id)
SELECT DISTINCT (s.created_at AT TIME ZONE 'Asia/Shanghai')::date,s.account_id
FROM security_audit s JOIN accounts a ON a.id=s.account_id
WHERE s.action IN ('world.join','world.movement','world.leave')
  AND s.outcome='observed' AND s.code='OK'
  AND s.created_at >= ((clock_timestamp() AT TIME ZONE 'Asia/Shanghai')::date-89)::timestamp AT TIME ZONE 'Asia/Shanghai'
ON CONFLICT DO NOTHING;
