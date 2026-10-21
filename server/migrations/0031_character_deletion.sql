-- Retain historical battle/audit references, but release active names and slots.
ALTER TABLE characters ADD COLUMN deleted_at TIMESTAMPTZ;
ALTER TABLE characters DROP CONSTRAINT characters_name_key_key;
DROP INDEX characters_account_slot_key;
CREATE UNIQUE INDEX characters_name_key_key ON characters(name_key) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX characters_account_slot_key ON characters(account_id,slot) WHERE deleted_at IS NULL;
ALTER TABLE account_operation_receipts DROP CONSTRAINT account_operation_receipts_operation_type_check;
ALTER TABLE account_operation_receipts ADD CHECK(operation_type IN ('character.create','character.delete'));
ALTER TABLE account_operation_receipts DROP CONSTRAINT account_operation_receipts_http_status_check;
ALTER TABLE account_operation_receipts ADD CHECK(http_status IN (200,201,409,422));
