ALTER TABLE inventory_items DROP CONSTRAINT inventory_items_definition_id_check;
ALTER TABLE inventory_items DROP CONSTRAINT inventory_items_check;
ALTER TABLE inventory_items ADD CONSTRAINT inventory_items_definition_id_check
    CHECK (definition_id IN ('potion','sword','weapon_2','weapon_3','armor_2','armor_3'));
ALTER TABLE inventory_items ADD CONSTRAINT inventory_items_check
    CHECK (NOT equipped OR (definition_id <> 'potion' AND quantity = 1));
ALTER TABLE inventory_items ADD CONSTRAINT equipment_quantity_one
    CHECK (definition_id = 'potion' OR quantity = 1);
CREATE UNIQUE INDEX one_equipped_weapon ON inventory_items(character_id)
    WHERE equipped AND definition_id IN ('sword','weapon_2','weapon_3');
CREATE UNIQUE INDEX one_equipped_armor ON inventory_items(character_id)
    WHERE equipped AND definition_id IN ('armor_2','armor_3');
