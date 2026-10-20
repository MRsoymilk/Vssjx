-- Lazy conversion waits until no durable encounter owns the old rules.
ALTER TABLE characters ADD COLUMN balance_revision SMALLINT NOT NULL DEFAULT 0 CHECK(balance_revision BETWEEN 0 AND 1);
ALTER TABLE characters ADD COLUMN balance_respec_available BOOLEAN NOT NULL DEFAULT TRUE;
