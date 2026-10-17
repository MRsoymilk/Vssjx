-- Preserve existing characters in slot zero; each account has five independent slots.
ALTER TABLE characters DROP CONSTRAINT characters_account_id_key;
ALTER TABLE characters ADD COLUMN slot SMALLINT NOT NULL DEFAULT 0 CHECK (slot BETWEEN 0 AND 4);
CREATE UNIQUE INDEX characters_account_slot_key ON characters(account_id, slot);
