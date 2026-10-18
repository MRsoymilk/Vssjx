CREATE TABLE teams (id UUID PRIMARY KEY, created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp());
CREATE TABLE team_members (
    character_id UUID PRIMARY KEY REFERENCES characters(id),
    team_id UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    leader BOOLEAN NOT NULL DEFAULT FALSE,
    ready BOOLEAN NOT NULL DEFAULT FALSE,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX team_members_team ON team_members(team_id);
CREATE UNIQUE INDEX team_one_leader ON team_members(team_id) WHERE leader;
CREATE TABLE team_invites (
    id UUID PRIMARY KEY,
    team_id UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    target UUID NOT NULL REFERENCES characters(id),
    status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','rejected')),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()+interval '60 seconds',
    UNIQUE(team_id,target)
);
CREATE INDEX team_invites_target ON team_invites(target);
CREATE TABLE team_battles (
    id UUID PRIMARY KEY,
    team_id UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    active BOOLEAN NOT NULL,
    state JSONB NOT NULL,
    deadline_ms BIGINT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);
CREATE UNIQUE INDEX team_one_battle ON team_battles(team_id) WHERE active;
CREATE TABLE team_receipts (
    character_id UUID NOT NULL REFERENCES characters(id),
    operation_id UUID NOT NULL,
    request_digest BYTEA NOT NULL CHECK(octet_length(request_digest)=32),
    result JSONB NOT NULL,
    PRIMARY KEY(character_id,operation_id)
);
