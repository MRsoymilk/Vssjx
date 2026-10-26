CREATE TABLE economy_receipts (
    character_id uuid NOT NULL REFERENCES characters(id),
    operation_id uuid NOT NULL,
    request_digest bytea NOT NULL,
    result jsonb NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    PRIMARY KEY(character_id,operation_id)
);
CREATE TABLE auction_listings (
    id uuid PRIMARY KEY,
    seller uuid NOT NULL REFERENCES characters(id),
    item jsonb NOT NULL CHECK (item->>'bound'='false' AND item->>'equipped'='false' AND item->>'legacy'='false'),
    item_id uuid NOT NULL,
    slot text NOT NULL, job smallint NOT NULL, quality text NOT NULL, level integer NOT NULL,
    starting_price integer NOT NULL CHECK(starting_price BETWEEN 1 AND 1000000000),
    buyout integer NOT NULL CHECK(buyout BETWEEN starting_price AND 1000000000),
    bid integer NOT NULL DEFAULT 0 CHECK(bid BETWEEN 0 AND 1000000000),
    bidder uuid REFERENCES characters(id),
    status text NOT NULL DEFAULT 'open' CHECK(status IN ('open','sold','expired','cancelled')),
    revision bigint NOT NULL DEFAULT 1,
    expires_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CHECK ((bid=0)=(bidder IS NULL))
);
CREATE UNIQUE INDEX auction_escrow_item ON auction_listings(item_id) WHERE status='open';
CREATE INDEX auction_expiry ON auction_listings(expires_at) WHERE status='open';
CREATE INDEX auction_seller ON auction_listings(seller,status);
CREATE TABLE economy_deliveries (
    id uuid PRIMARY KEY,
    character_id uuid NOT NULL REFERENCES characters(id),
    item jsonb,
    gold integer NOT NULL DEFAULT 0 CHECK(gold BETWEEN 0 AND 1000000000),
    reason text NOT NULL,
    source_id uuid NOT NULL,
    claimed boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CHECK ((item IS NOT NULL AND gold=0) OR (item IS NULL AND gold>0))
);
CREATE INDEX economy_delivery_inbox ON economy_deliveries(character_id,claimed,created_at);
