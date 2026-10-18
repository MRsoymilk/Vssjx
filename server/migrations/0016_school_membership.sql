-- One-time reset requested by the owner. Preserve permanent progress and inventory.
ALTER TABLE characters DROP CONSTRAINT characters_school_check;
ALTER TABLE characters ADD CONSTRAINT characters_school_check CHECK (school BETWEEN 0 AND 3);
-- Transient encounters cannot retain effects from a membership being reset.
UPDATE pve_battles SET active=FALSE, updated_at=NOW() WHERE active;
UPDATE characters SET school=3, active_battle_id=NULL, state_revision=state_revision+1;
