-- Keep the existing full catalog constraint and add two unique containers.
DO $$
DECLARE previous text;
BEGIN
    SELECT pg_get_constraintdef(oid) INTO STRICT previous FROM pg_constraint
        WHERE conrelid='inventory_items'::regclass AND conname='inventory_items_definition_id_check';
    ALTER TABLE inventory_items DROP CONSTRAINT inventory_items_definition_id_check;
    EXECUTE 'ALTER TABLE inventory_items ADD CONSTRAINT inventory_items_definition_id_check ' ||
        replace(previous, 'CHECK (', 'CHECK (definition_id IN (''supply/hp_gourd'',''supply/mp_gourd'') OR ');
END $$;
ALTER TABLE inventory_items ADD CONSTRAINT inventory_gourd_single CHECK
    (definition_id NOT IN ('supply/hp_gourd','supply/mp_gourd') OR (quantity=1 AND NOT equipped));
ALTER TABLE characters ADD COLUMN gourd_state jsonb NOT NULL DEFAULT '{}'::jsonb
    CHECK(jsonb_typeof(gourd_state)='object');
