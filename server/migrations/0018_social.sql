-- Character-scoped relationships. No client can select an account or grant a role.
CREATE TABLE friendships (
    low_id UUID NOT NULL REFERENCES characters(id),
    high_id UUID NOT NULL REFERENCES characters(id),
    requester_id UUID NOT NULL REFERENCES characters(id),
    status TEXT NOT NULL CHECK (status IN ('pending','accepted','rejected')),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    PRIMARY KEY(low_id,high_id),
    CHECK (low_id < high_id AND requester_id IN (low_id,high_id))
);
CREATE INDEX friendships_high ON friendships(high_id);
CREATE TABLE guilds (
    id UUID PRIMARY KEY,
    name TEXT NOT NULL CHECK (char_length(name) BETWEEN 2 AND 12),
    name_key TEXT COLLATE "C" NOT NULL UNIQUE,
    announcement TEXT NOT NULL DEFAULT '' CHECK (char_length(announcement) <= 120),
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE guild_members (
    character_id UUID PRIMARY KEY REFERENCES characters(id),
    guild_id UUID NOT NULL REFERENCES guilds(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('leader','member')),
    joined_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX guild_members_guild ON guild_members(guild_id);
CREATE UNIQUE INDEX guild_one_leader ON guild_members(guild_id) WHERE role='leader';
CREATE TABLE guild_applications (
    guild_id UUID NOT NULL REFERENCES guilds(id) ON DELETE CASCADE,
    character_id UUID NOT NULL REFERENCES characters(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    PRIMARY KEY(guild_id,character_id)
);
CREATE INDEX guild_applications_character ON guild_applications(character_id);
CREATE TABLE social_receipts (
    character_id UUID NOT NULL REFERENCES characters(id),
    operation_id UUID NOT NULL,
    request_digest BYTEA NOT NULL CHECK (octet_length(request_digest)=32),
    result JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    PRIMARY KEY(character_id,operation_id)
);
