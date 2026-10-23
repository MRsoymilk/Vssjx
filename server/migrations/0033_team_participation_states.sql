-- A member has exactly one standing choice: prepared/following or temporarily away.
-- Following members are prepared by default; preserve explicit temporary leave.
UPDATE team_members SET ready=leader OR following, following=leader OR following;
ALTER TABLE team_members ALTER COLUMN ready SET DEFAULT TRUE;
